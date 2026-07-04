-- =====================================================================
-- STAGE 54A-10B — Registration-Resolution Category Infrastructure (additive)
--   เพิ่มค่าหมวดใหม่ 'registration_resolution' = "ขึ้นทะเบียนตามมติ ครม."
--   (Cabinet-resolution registration) เพื่อรองรับ template family ใหม่ในอนาคต
--
--   ⚠️ INFRASTRUCTURE ONLY — ไม่ seed แม่แบบใด ๆ · ไม่แตะเนื้อหาแม่แบบเดิม 16 รายการ
--   ⚠️ CI_MYANMAR ยังคงเป็นงาน CI/เอกสาร/สถานะ ของพม่าเท่านั้น
--      — ไม่ใช่ถังของงานขึ้นทะเบียนตามมติ ครม. (ดู REGISTRATION_RESOLUTION_TEMPLATE_PLAN.md)
--   ⚠️ แม่แบบจริงรายมติ ต้องมี PDF/คู่มือของมตินั้นที่ตรวจแล้ว (1 มติ = 1 แม่แบบ) — ทำในสเตจถัดไป
--
--   สิ่งที่ทำ (ทั้งหมด additive + idempotent):
--     1) ขยาย CHECK constraint ของ public.case_templates.category
--     2) ขยาย CHECK constraint ของ public.cases.case_category
--        (เพราะ app_create_case คัดลอก template.category → cases.case_category)
--     3) create or replace app_admin_save_case_template — ยอมรับหมวดใหม่ตอน save แม่แบบ
--     4) create or replace app_list_cases — ยอมรับหมวดใหม่ในตัวกรอง (filter enum)
--   ❌ ไม่แตะ: seed/แถวข้อมูล, checklist, payment, appointment, tracking,
--      storage/upload, login/LINE, import/export, delete-approval, RLS/grants เดิม
--   ❌ ไม่รันกับ Supabase (เตรียมไว้ให้เจ้าของรันเองภายหลัง)
--
--   FUNCTION BODIES ด้านล่าง (2)(3)(4) คัดลอกตรงจากนิยามล่าสุด
--     - app_list_cases: 20260802_basic_case_management.sql
--     - app_admin_save_case_template: 20260808_case_template_metadata.sql
--   โดยแก้ "เฉพาะบรรทัด enum หมวด" เพิ่ม 'registration_resolution' เท่านั้น
--   signature เดิมทุกตัว → create or replace รักษา grant เดิม (ออก grant ซ้ำเพื่อความชัด)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) case_templates.category — ขยายรายการหมวด (drop+add = idempotent, ไม่ลบข้อมูล)
--    แถวเดิม 16 รายการใช้หมวดใน list เดิมทั้งหมด → drop/add ปลอดภัย
-- ---------------------------------------------------------------------
alter table public.case_templates drop constraint if exists case_templates_category_check;
alter table public.case_templates add constraint case_templates_category_check
  check (category in ('mou','ci','visa','work_permit','report_90',
                      'change_employer','renewal','notification','registration_resolution','other'));

-- ---------------------------------------------------------------------
-- 2) cases.case_category — ขยายให้ตรงกับ template.category (enum ใช้ร่วมกัน)
--    ยังไม่มีเคสใดใช้หมวดใหม่ (ยังไม่มีแม่แบบหมวดนี้) → drop/add ปลอดภัย
-- ---------------------------------------------------------------------
alter table public.cases drop constraint if exists cases_category_check;
alter table public.cases add constraint cases_category_check
  check (case_category in ('mou','ci','visa','work_permit','report_90',
                           'change_employer','renewal','notification','registration_resolution','other'));

-- ---------------------------------------------------------------------
-- 3) app_admin_save_case_template — ยอมรับหมวด 'registration_resolution'
--    (คัดลอกจาก 20260808 · แก้เฉพาะ enum หมวด)
-- ---------------------------------------------------------------------
create or replace function public.app_admin_save_case_template(
  p_user_id                 text,
  p_username                text,
  p_template_id             bigint default null,   -- null = สร้างใหม่
  p_template_code           text default null,
  p_template_name_th        text default null,
  p_template_name_en        text default null,
  p_category                text default null,
  p_description             text default null,
  p_default_case_status     text default null,
  p_sort_order              integer default null,
  p_cabinet_resolution_refs jsonb default null,
  p_law_refs                jsonb default null,
  p_form_refs               jsonb default null,
  p_eligibility_note        text default null,
  p_internal_guidance       text default null,
  p_process_summary         text default null,
  p_source_note             text default null
)
returns table (id bigint, template_code text, template_name_th text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_code      text := upper(btrim(coalesce(p_template_code, '')));
  v_cat       text := lower(btrim(coalesce(p_category, '')));
  v_status    text := lower(btrim(coalesce(p_default_case_status, '')));
  v_id        bigint;
  v_action    text;
begin
  -- ── ตัวตน + admin เท่านั้น (server-side บังคับจริง) ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate ค่า enum (เฉพาะเมื่อส่งมา) ──
  if v_cat <> '' and v_cat not in ('mou','ci','visa','work_permit','report_90',
                                   'change_employer','renewal','notification','registration_resolution','other') then
    raise exception 'invalid_category' using errcode = 'P0003';
  end if;
  if v_status <> '' and v_status not in ('draft','preparing_documents','ready_to_submit','submitted',
                                         'waiting_result','approved','rejected','cancelled','completed') then
    raise exception 'invalid_default_case_status' using errcode = 'P0003';
  end if;
  if v_code <> '' and v_code !~ '^[A-Z0-9_]{2,60}$' then
    raise exception 'invalid_template_code' using errcode = 'P0003';
  end if;

  -- ── validate jsonb refs: ถ้าส่งมา ต้องเป็น array เท่านั้น ──
  if p_cabinet_resolution_refs is not null and jsonb_typeof(p_cabinet_resolution_refs) <> 'array' then
    raise exception 'invalid_cabinet_resolution_refs' using errcode = 'P0003';
  end if;
  if p_law_refs is not null and jsonb_typeof(p_law_refs) <> 'array' then
    raise exception 'invalid_law_refs' using errcode = 'P0003';
  end if;
  if p_form_refs is not null and jsonb_typeof(p_form_refs) <> 'array' then
    raise exception 'invalid_form_refs' using errcode = 'P0003';
  end if;

  if p_template_id is null then
    -- ── CREATE ──
    if v_code = '' or coalesce(btrim(p_template_name_th), '') = '' or v_cat = '' then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    insert into public.case_templates
      (template_code, template_name_th, template_name_en, category, description,
       default_case_status, sort_order,
       cabinet_resolution_refs, law_refs, form_refs,
       eligibility_note, internal_guidance, process_summary, source_note, updated_by_code)
    values
      (v_code, btrim(p_template_name_th), nullif(btrim(coalesce(p_template_name_en,'')),''),
       v_cat, nullif(btrim(coalesce(p_description,'')),''),
       case when v_status = '' then 'draft' else v_status end,
       coalesce(p_sort_order, 100),
       coalesce(p_cabinet_resolution_refs, '[]'::jsonb),
       coalesce(p_law_refs, '[]'::jsonb),
       coalesce(p_form_refs, '[]'::jsonb),
       nullif(btrim(coalesce(p_eligibility_note,'')),''),
       nullif(btrim(coalesce(p_internal_guidance,'')),''),
       nullif(btrim(coalesce(p_process_summary,'')),''),
       nullif(btrim(coalesce(p_source_note,'')),''),
       p_username)
    returning case_templates.id into v_id;
    v_action := 'case_template.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา ──
    update public.case_templates t
    set template_code           = case when v_code = '' then t.template_code else v_code end,
        template_name_th        = coalesce(nullif(btrim(coalesce(p_template_name_th,'')),''), t.template_name_th),
        template_name_en        = case when p_template_name_en is null then t.template_name_en
                                       else nullif(btrim(p_template_name_en),'') end,
        category                = case when v_cat = '' then t.category else v_cat end,
        description             = case when p_description is null then t.description
                                       else nullif(btrim(p_description),'') end,
        default_case_status     = case when v_status = '' then t.default_case_status else v_status end,
        sort_order              = coalesce(p_sort_order, t.sort_order),
        cabinet_resolution_refs = coalesce(p_cabinet_resolution_refs, t.cabinet_resolution_refs),
        law_refs                = coalesce(p_law_refs, t.law_refs),
        form_refs               = coalesce(p_form_refs, t.form_refs),
        eligibility_note        = case when p_eligibility_note is null then t.eligibility_note
                                       else nullif(btrim(p_eligibility_note),'') end,
        internal_guidance       = case when p_internal_guidance is null then t.internal_guidance
                                       else nullif(btrim(p_internal_guidance),'') end,
        process_summary         = case when p_process_summary is null then t.process_summary
                                       else nullif(btrim(p_process_summary),'') end,
        source_note             = case when p_source_note is null then t.source_note
                                       else nullif(btrim(p_source_note),'') end,
        updated_by_code         = p_username,
        updated_at              = now()
    where t.id = p_template_id
    returning t.id into v_id;

    if v_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    v_action := 'case_template.update';
  end if;

  -- ── audit log ฝั่ง server (best-effort — พังไม่ทำให้ save ล้ม) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_template', v_id::text,
            jsonb_build_object('template_code', v_code, 'category', v_cat, 'internal_draft', true));
  exception when others then null;
  end;

  return query
  select t.id, t.template_code, t.template_name_th
  from public.case_templates t where t.id = v_id;
end;
$$;

revoke all on function public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer,
  jsonb, jsonb, jsonb, text, text, text, text
) from public;
grant execute on function public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer,
  jsonb, jsonb, jsonb, text, text, text, text
) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) app_list_cases — ยอมรับหมวด 'registration_resolution' ในตัวกรอง
--    (คัดลอกจาก 20260802 · แก้เฉพาะ enum หมวด)
-- ---------------------------------------------------------------------
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
                   'change_employer','renewal','notification','registration_resolution','other') then
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
