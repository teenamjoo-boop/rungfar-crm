-- =============================================================
-- STAGE 54A-3 — Basic Case Management Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * สร้างชั้น "เคสงาน" แรกของ Phase 2: ตาราง cases + case_status_logs
--     ผูกกับลูกค้า/แรงงานเดิม (customers) และแม่แบบงาน (case_templates 54A-2)
--   * ยังไม่ทำ: checklist instance / ผูกเอกสาร / การเงิน / นัดหมาย / e-WorkPermit tracking
--
--   ❗ เคส = งานติดตามภายในบริษัทเท่านั้น:
--     - ไม่ใช่เอกสารราชการ, ไม่สร้าง/ไม่ปลอมเอกสารราชการ
--     - ไม่ automate ใด ๆ กับเว็บราชการ e-WorkPermit
--     - ewp_request_no เป็นแค่ช่องจดเลขอ้างอิงที่ระบบราชการออกให้จริง (พิมพ์เอง, optional)
--     - case_code เป็นรหัสภายใน (CASE-YYYYMMDD-xxxxxx) ไม่ใช่เลขคำขอราชการ
--
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE inbox/customer-doc-upload/
--     import-export/delete approval/Meta Ads/Storage — และ "ไม่แก้แถว customers ใด ๆ"
--   ❗ ไม่มี hard delete ของเคสใน stage นี้ (ยกเลิก = เปลี่ยนสถานะ cancelled)
--   ❗ เขียนทุกอย่างผ่าน RPC เท่านั้น — ❌ ไม่ grant สิทธิ์ตรงบนตารางใหม่ให้ anon/authenticated
--   ❗ RPC ไม่คืน file_data / base64 / storage_path / signed URL ใด ๆ
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A1) ตารางเคสงาน
--     หมายเหตุ: customer_id/employer_id ตั้งใจ "ไม่ใส่ FK" — ลูกค้าใช้ soft delete
--     (deleted_at) อยู่แล้ว และไม่อยากให้เคสเก่า block งานตารางลูกค้าในอนาคต
-- =============================================================
create table if not exists public.cases (
  id               bigserial primary key,
  case_code        text not null unique,
  customer_id      bigint not null,
  employer_id      bigint null,
  template_id      bigint null references public.case_templates(id) on delete set null,
  template_code    text null,
  case_title       text not null,
  case_category    text not null,
  case_status      text not null default 'draft',
  priority         text not null default 'normal',
  assigned_to_code text null,
  ewp_request_no   text null,
  due_date         date null,
  submitted_at     timestamptz null,
  completed_at     timestamptz null,
  cancelled_at     timestamptz null,
  note             text null,
  created_by_code  text null,
  updated_by_code  text null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint cases_status_check check (
    case_status in ('draft','preparing_documents','ready_to_submit','submitted',
                    'waiting_result','approved','rejected','cancelled','completed')
  ),
  constraint cases_priority_check check (
    priority in ('low','normal','high','urgent')
  ),
  constraint cases_category_check check (
    case_category in ('mou','ci','visa','work_permit','report_90',
                      'change_employer','renewal','notification','other')
  )
);

comment on table public.cases is
  'STAGE 54A-3: เคสงานภายในบริษัท (Phase 2) — งานติดตามภายในเท่านั้น ไม่ใช่เอกสารราชการ และระบบไม่ยื่นงานแทนเว็บราชการ. เขียนผ่าน RPC เท่านั้น (app_create_case / app_update_case / app_change_case_status) — ห้าม grant เขียนตรงให้ anon/authenticated. ไม่มี hard delete.';

create index if not exists idx_cases_customer      on public.cases (customer_id, created_at desc);
create index if not exists idx_cases_employer      on public.cases (employer_id, created_at desc);
create index if not exists idx_cases_template      on public.cases (template_id);
create index if not exists idx_cases_status_due    on public.cases (case_status, due_date);
create index if not exists idx_cases_assignee      on public.cases (assigned_to_code, case_status);
create index if not exists idx_cases_cat_status    on public.cases (case_category, case_status);

-- =============================================================
-- A2) ตารางประวัติสถานะเคส
-- =============================================================
create table if not exists public.case_status_logs (
  id         bigserial primary key,
  case_id    bigint not null references public.cases(id) on delete cascade,
  old_status text null,
  new_status text not null,
  note       text null,
  actor_code text null,
  created_at timestamptz not null default now()
);

comment on table public.case_status_logs is
  'STAGE 54A-3: ประวัติการเปลี่ยนสถานะเคส — เขียนโดย RPC ฝั่ง server เท่านั้น (app_create_case / app_change_case_status)';

create index if not exists idx_case_status_logs_case
  on public.case_status_logs (case_id, created_at desc);

-- =============================================================
-- A3) ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2 / 20260721-23)
-- =============================================================
revoke all on table public.cases from public, anon, authenticated;
revoke all on table public.case_status_logs from public, anon, authenticated;
revoke all on sequence public.cases_id_seq from public, anon, authenticated;
revoke all on sequence public.case_status_logs_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_cases — staff/admin อ่านรายการเคส (metadata เท่านั้น)
--     ❌ ไม่มี storage_path / file_data / base64 / signed URL
-- =============================================================
create or replace function public.app_list_cases(
  p_user_id          text,
  p_username         text,
  p_search           text default null,
  p_customer_id      bigint default null,
  p_employer_id      bigint default null,
  p_status           text default null,
  p_category         text default null,
  p_assigned_to_code text default null,
  p_due_from         date default null,
  p_due_to           date default null,
  p_limit            integer default 50,
  p_offset           integer default 0
)
returns table (
  id               bigint,
  case_code        text,
  case_title       text,
  case_category    text,
  case_status      text,
  priority         text,
  due_date         date,
  submitted_at     timestamptz,
  completed_at     timestamptz,
  customer_id      bigint,
  customer_name    text,
  passport_no      text,
  alien_id         text,
  wp_no            text,
  employer_id      bigint,
  employer_name    text,
  template_id      bigint,
  template_code    text,
  template_name_th text,
  assigned_to_code text,
  created_at       timestamptz,
  updated_at       timestamptz,
  total_count      bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok     boolean := false;
  v_limit  integer := coalesce(p_limit, 50);
  v_offset integer := coalesce(p_offset, 0);
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_cat    text := lower(btrim(coalesce(p_category, '')));
begin
  -- ── ตัวตน: ผู้ใช้ active (staff/admin) — predicate เดียวกับ RPC อื่นของระบบ ──
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate filter enum ('' = ไม่กรอง) ──
  if v_status not in ('','draft','preparing_documents','ready_to_submit','submitted',
                      'waiting_result','approved','rejected','cancelled','completed') then
    raise exception 'invalid_status' using errcode = 'P0003';
  end if;
  if v_cat not in ('','mou','ci','visa','work_permit','report_90',
                   'change_employer','renewal','notification','other') then
    raise exception 'invalid_category' using errcode = 'P0003';
  end if;

  -- ── clamp pagination ──
  if v_limit is null or v_limit < 1 then v_limit := 50;
  elsif v_limit > 100 then v_limit := 100; end if;
  if v_offset is null or v_offset < 0 then v_offset := 0; end if;

  return query
  select
    cs.id, cs.case_code, cs.case_title, cs.case_category, cs.case_status,
    cs.priority, cs.due_date, cs.submitted_at, cs.completed_at,
    cs.customer_id, c.name as customer_name, c.passport_no, c.alien_id, c.wp_no,
    cs.employer_id, e.name as employer_name,
    cs.template_id, cs.template_code, t.template_name_th,
    cs.assigned_to_code, cs.created_at, cs.updated_at,
    count(*) over () as total_count
  from public.cases cs
  left join public.customers c on c.id = cs.customer_id
  left join public.employers e on e.id = cs.employer_id
  left join public.case_templates t on t.id = cs.template_id
  where
    (p_customer_id is null or cs.customer_id = p_customer_id)
    and (p_employer_id is null or cs.employer_id = p_employer_id)
    and (v_status = '' or cs.case_status = v_status)
    and (v_cat = '' or cs.case_category = v_cat)
    and (p_assigned_to_code is null or p_assigned_to_code = ''
         or cs.assigned_to_code = p_assigned_to_code)
    and (p_due_from is null or cs.due_date >= p_due_from)
    and (p_due_to   is null or cs.due_date <= p_due_to)
    and (
      p_search is null or p_search = ''
      or cs.case_code      ilike '%' || p_search || '%'
      or cs.case_title     ilike '%' || p_search || '%'
      or cs.ewp_request_no ilike '%' || p_search || '%'
      or c.name            ilike '%' || p_search || '%'
      or c.passport_no     ilike '%' || p_search || '%'
      or c.alien_id        ilike '%' || p_search || '%'
    )
  order by cs.created_at desc
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.app_list_cases(
  text, text, text, bigint, bigint, text, text, text, date, date, integer, integer
) from public;
grant execute on function public.app_list_cases(
  text, text, text, bigint, bigint, text, text, text, date, date, integer, integer
) to anon, authenticated;

-- =============================================================
-- B2) app_get_case_detail — staff/admin อ่านรายละเอียดเคส + ประวัติสถานะ (jsonb)
-- =============================================================
create or replace function public.app_get_case_detail(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok   boolean := false;
  v_case jsonb;
  v_logs jsonb;
begin
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select to_jsonb(x) into v_case
  from (
    select
      cs.id, cs.case_code, cs.case_title, cs.case_category, cs.case_status,
      cs.priority, cs.due_date, cs.submitted_at, cs.completed_at, cs.cancelled_at,
      cs.ewp_request_no, cs.note, cs.assigned_to_code,
      cs.customer_id, c.name as customer_name, c.passport_no, c.alien_id, c.wp_no,
      c.phone as customer_phone, c.nationality as customer_nationality,
      cs.employer_id, e.name as employer_name,
      cs.template_id, cs.template_code, t.template_name_th,
      cs.created_by_code, cs.updated_by_code, cs.created_at, cs.updated_at
    from public.cases cs
    left join public.customers c on c.id = cs.customer_id
    left join public.employers e on e.id = cs.employer_id
    left join public.case_templates t on t.id = cs.template_id
    where cs.id = p_case_id
  ) x;

  if v_case is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc, l.id desc), '[]'::jsonb)
    into v_logs
  from (
    select id, case_id, old_status, new_status, note, actor_code, created_at
    from public.case_status_logs
    where case_id = p_case_id
  ) l;

  return jsonb_build_object('case', v_case, 'status_logs', v_logs);
end;
$$;

revoke all on function public.app_get_case_detail(text, text, bigint) from public;
grant execute on function public.app_get_case_detail(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B3) app_create_case — staff/admin สร้างเคสจากลูกค้าเดิม + แม่แบบ active
--     case_code = CASE-YYYYMMDD-xxxxxx (รหัสภายใน — ไม่ใช่เลขคำขอราชการ)
--     ❌ ไม่แก้แถว customers ใด ๆ (อ่าน employer_id มาใส่เคสเท่านั้น)
-- =============================================================
create or replace function public.app_create_case(
  p_user_id          text,
  p_username         text,
  p_customer_id      bigint,
  p_template_id      bigint,
  p_case_title       text default null,
  p_priority         text default 'normal',
  p_assigned_to_code text default null,
  p_due_date         date default null,
  p_note             text default null
)
returns table (id bigint, case_code text, case_title text, case_status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_cust      record;
  v_tpl       record;
  v_pri       text := lower(btrim(coalesce(p_priority, 'normal')));
  v_title     text;
  v_new_id    bigint;
  v_code      text;
  v_status    text;
begin
  -- ── ตัวตน: staff/admin active ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_pri = '' then v_pri := 'normal'; end if;
  if v_pri not in ('low','normal','high','urgent') then
    raise exception 'invalid_priority' using errcode = 'P0003';
  end if;

  -- ── ลูกค้าต้องมีจริงและไม่ถูก soft delete ──
  select c.id, c.name, c.employer_id into v_cust
  from public.customers c
  where c.id = p_customer_id and c.deleted_at is null;
  if v_cust.id is null then
    raise exception 'customer_not_found' using errcode = 'P0002';
  end if;

  -- ── แม่แบบต้องมีจริงและ active ──
  select t.id, t.template_code, t.template_name_th, t.category, t.default_case_status
    into v_tpl
  from public.case_templates t
  where t.id = p_template_id and t.is_active = true;
  if v_tpl.id is null then
    raise exception 'template_not_found_or_inactive' using errcode = 'P0002';
  end if;

  v_status := v_tpl.default_case_status;
  v_title  := coalesce(nullif(btrim(coalesce(p_case_title, '')), ''),
                       v_tpl.template_name_th || ' — ' || v_cust.name);

  -- ── รหัสเคสภายใน: จองเลขจาก sequence ก่อน → unique เสมอ ──
  v_new_id := nextval('public.cases_id_seq');
  v_code   := 'CASE-' || to_char(now() at time zone 'Asia/Bangkok', 'YYYYMMDD')
              || '-' || lpad(v_new_id::text, 6, '0');

  insert into public.cases
    (id, case_code, customer_id, employer_id, template_id, template_code,
     case_title, case_category, case_status, priority, assigned_to_code,
     due_date, note, created_by_code, updated_by_code)
  values
    (v_new_id, v_code, v_cust.id, v_cust.employer_id, v_tpl.id, v_tpl.template_code,
     v_title, v_tpl.category, v_status, v_pri,
     nullif(btrim(coalesce(p_assigned_to_code, '')), ''),
     p_due_date, nullif(btrim(coalesce(p_note, '')), ''),
     p_username, p_username);

  -- ── ประวัติสถานะแถวแรก ──
  insert into public.case_status_logs (case_id, old_status, new_status, note, actor_code)
  values (v_new_id, null, v_status, 'สร้างเคส', p_username);

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.create', 'case', v_new_id::text,
            jsonb_build_object('case_code', v_code, 'customer_id', v_cust.id,
                               'template_code', v_tpl.template_code, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select cs.id, cs.case_code, cs.case_title, cs.case_status
  from public.cases cs where cs.id = v_new_id;
end;
$$;

revoke all on function public.app_create_case(
  text, text, bigint, bigint, text, text, text, date, text
) from public;
grant execute on function public.app_create_case(
  text, text, bigint, bigint, text, text, text, date, text
) to anon, authenticated;

-- =============================================================
-- B4) app_update_case — staff/admin แก้ metadata ปกติ (❌ ไม่เปลี่ยนสถานะที่นี่)
--     แก้เฉพาะ field ที่ส่งมา (ไม่ null) — server-stamp updated_at/updated_by_code
-- =============================================================
create or replace function public.app_update_case(
  p_user_id          text,
  p_username         text,
  p_case_id          bigint,
  p_case_title       text default null,
  p_priority         text default null,
  p_assigned_to_code text default null,
  p_due_date         date default null,
  p_ewp_request_no   text default null,
  p_note             text default null
)
returns table (id bigint, case_code text, updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_pri       text := lower(btrim(coalesce(p_priority, '')));
  v_id        bigint;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_pri <> '' and v_pri not in ('low','normal','high','urgent') then
    raise exception 'invalid_priority' using errcode = 'P0003';
  end if;

  update public.cases cs
  set case_title       = coalesce(nullif(btrim(coalesce(p_case_title,'')),''), cs.case_title),
      priority         = case when v_pri = '' then cs.priority else v_pri end,
      assigned_to_code = case when p_assigned_to_code is null then cs.assigned_to_code
                              else nullif(btrim(p_assigned_to_code),'') end,
      due_date         = coalesce(p_due_date, cs.due_date),
      ewp_request_no   = case when p_ewp_request_no is null then cs.ewp_request_no
                              else nullif(btrim(p_ewp_request_no),'') end,
      note             = case when p_note is null then cs.note
                              else nullif(btrim(p_note),'') end,
      updated_by_code  = p_username,
      updated_at       = now()
  where cs.id = p_case_id
  returning cs.id into v_id;

  if v_id is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.update', 'case', v_id::text,
            jsonb_build_object('internal_only', true));
  exception when others then null;
  end;

  return query
  select cs.id, cs.case_code, cs.updated_at
  from public.cases cs where cs.id = v_id;
end;
$$;

revoke all on function public.app_update_case(
  text, text, bigint, text, text, text, date, text, text
) from public;
grant execute on function public.app_update_case(
  text, text, bigint, text, text, text, date, text, text
) to anon, authenticated;

-- =============================================================
-- B5) app_change_case_status — staff/admin เปลี่ยนสถานะ + เขียน log + stamp เวลา
-- =============================================================
create or replace function public.app_change_case_status(
  p_user_id    text,
  p_username   text,
  p_case_id    bigint,
  p_new_status text,
  p_note       text default null
)
returns table (id bigint, case_code text, case_status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_new       text := lower(btrim(coalesce(p_new_status, '')));
  v_old       text;
  v_id        bigint;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_new not in ('draft','preparing_documents','ready_to_submit','submitted',
                   'waiting_result','approved','rejected','cancelled','completed') then
    raise exception 'invalid_status' using errcode = 'P0003';
  end if;

  select cs.case_status into v_old
  from public.cases cs where cs.id = p_case_id
  for update;
  if v_old is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;
  if v_old = v_new then
    raise exception 'same_status' using errcode = 'P0003';
  end if;

  update public.cases cs
  set case_status  = v_new,
      submitted_at = case when v_new = 'submitted' and cs.submitted_at is null
                          then now() else cs.submitted_at end,
      completed_at = case when v_new in ('approved','completed') and cs.completed_at is null
                          then now() else cs.completed_at end,
      cancelled_at = case when v_new = 'cancelled' and cs.cancelled_at is null
                          then now() else cs.cancelled_at end,
      updated_by_code = p_username,
      updated_at      = now()
  where cs.id = p_case_id
  returning cs.id into v_id;

  insert into public.case_status_logs (case_id, old_status, new_status, note, actor_code)
  values (v_id, v_old, v_new, nullif(btrim(coalesce(p_note,'')),''), p_username);

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.status', 'case', v_id::text,
            jsonb_build_object('from', v_old, 'to', v_new, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select cs.id, cs.case_code, cs.case_status
  from public.cases cs where cs.id = v_id;
end;
$$;

revoke all on function public.app_change_case_status(text, text, bigint, text, text) from public;
grant execute on function public.app_change_case_status(text, text, bigint, text, text) to anon, authenticated;

-- =============================================================
-- B6) app_case_summary — นับเคสแยกสถานะ + ใกล้ครบกำหนด/เลยกำหนด (สำหรับ card/badge)
--     open = สถานะที่ยังไม่จบ (ไม่ใช่ approved/rejected/cancelled/completed)
-- =============================================================
create or replace function public.app_case_summary(
  p_user_id  text,
  p_username text
)
returns table (
  total_open           bigint,
  draft                bigint,
  preparing_documents  bigint,
  ready_to_submit      bigint,
  submitted            bigint,
  waiting_result       bigint,
  approved             bigint,
  rejected             bigint,
  cancelled            bigint,
  completed            bigint,
  due_soon             bigint,
  overdue              bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select
    count(*) filter (where cs.case_status not in ('approved','rejected','cancelled','completed')) as total_open,
    count(*) filter (where cs.case_status = 'draft')               as draft,
    count(*) filter (where cs.case_status = 'preparing_documents') as preparing_documents,
    count(*) filter (where cs.case_status = 'ready_to_submit')     as ready_to_submit,
    count(*) filter (where cs.case_status = 'submitted')           as submitted,
    count(*) filter (where cs.case_status = 'waiting_result')      as waiting_result,
    count(*) filter (where cs.case_status = 'approved')            as approved,
    count(*) filter (where cs.case_status = 'rejected')            as rejected,
    count(*) filter (where cs.case_status = 'cancelled')           as cancelled,
    count(*) filter (where cs.case_status = 'completed')           as completed,
    count(*) filter (where cs.case_status not in ('approved','rejected','cancelled','completed')
                     and cs.due_date is not null
                     and cs.due_date >= current_date
                     and cs.due_date <= current_date + 7)          as due_soon,
    count(*) filter (where cs.case_status not in ('approved','rejected','cancelled','completed')
                     and cs.due_date is not null
                     and cs.due_date < current_date)               as overdue
  from public.cases cs;
end;
$$;

revoke all on function public.app_case_summary(text, text) from public;
grant execute on function public.app_case_summary(text, text) to anon, authenticated;
