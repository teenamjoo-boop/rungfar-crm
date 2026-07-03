-- =============================================================
-- STAGE 54A-6B — Case Appointments Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * ติดตาม "นัดหมาย / วันดำเนินการ" ภายในของเคส (public.case_appointments)
--     เช่น นัดเตรียมเอกสาร นัดยื่น นัดเก็บข้อมูลชีวภาพ นัดรับผล ฯลฯ
--
--   ❗ นี่คือ "การติดตามภายในบริษัท" เท่านั้น — ไม่ใช่ใบนัดราชการ
--     ไม่สร้าง/ปลอมเอกสารราชการ ไม่ automate เว็บราชการ e-WorkPermit
--   ❗ stage นี้ใช้ note เท่านั้น — ไม่มีไฟล์แนบ/ไม่มีทางอัปโหลดใหม่
--   ❗ ไม่มี hard delete — ยกเลิกนัด = เปลี่ยนสถานะ cancelled เท่านั้น
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE inbox/customer-doc-upload/
--     customer-doc-sign/delete approval/Meta/import-export/case checklist (54A-4)/
--     case payments (54A-6A)/employer establishments (54A-5)
--   ❗ เขียนทุกอย่างผ่าน RPC เท่านั้น — ❌ ไม่ grant สิทธิ์ตรงบนตารางใหม่
--   ❗ RPC ไม่คืน file_data / base64 / storage_path / storage_bucket / signed URL ใด ๆ
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A) ตารางนัดหมายของเคส
-- =============================================================
create table if not exists public.case_appointments (
  id                 bigserial primary key,
  case_id            bigint not null references public.cases(id) on delete cascade,
  appointment_type   text not null,
  appointment_title  text not null,
  appointment_status text not null default 'scheduled',
  appointment_date   date not null,
  appointment_time   time null,
  location           text null,
  officer_or_contact text null,
  note               text null,
  result_note        text null,
  created_by_code    text null,
  updated_by_code    text null,
  completed_at       timestamptz null,
  cancelled_at       timestamptz null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint case_appointments_type_check check (
    appointment_type in ('document_prepare','submission','biometrics','medical',
                         'training','payment','receive_result','follow_up','other')
  ),
  constraint case_appointments_status_check check (
    appointment_status in ('scheduled','completed','missed','postponed','cancelled')
  )
);

comment on table public.case_appointments is
  'STAGE 54A-6B: นัดหมาย/วันดำเนินการภายในของเคส (Phase 2) — ติดตามภายในบริษัทเท่านั้น ไม่ใช่ใบนัดราชการ. เขียนผ่าน RPC เท่านั้น (app_save_case_appointment / app_set_case_appointment_status) — ห้าม grant เขียนตรงให้ anon/authenticated. ไม่มี hard delete — ยกเลิก = เปลี่ยนสถานะ cancelled';

create index if not exists idx_case_appts_case
  on public.case_appointments (case_id);
create index if not exists idx_case_appts_status
  on public.case_appointments (appointment_status);
create index if not exists idx_case_appts_date
  on public.case_appointments (appointment_date);
create index if not exists idx_case_appts_type
  on public.case_appointments (appointment_type);
create index if not exists idx_case_appts_created
  on public.case_appointments (created_at desc);

-- =============================================================
-- ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2/3/4/5/6A)
-- =============================================================
revoke all on table public.case_appointments from public, anon, authenticated;
revoke all on sequence public.case_appointments_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_case_appointments — staff/admin อ่านนัดหมายของเคส
--     ❌ ไม่มี path/file/URL ใด ๆ (ตารางนี้ไม่มีไฟล์แนบตั้งแต่ต้น)
-- =============================================================
create or replace function public.app_list_case_appointments(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  id                 bigint,
  case_id            bigint,
  appointment_type   text,
  appointment_title  text,
  appointment_status text,
  appointment_date   date,
  appointment_time   time,
  location           text,
  officer_or_contact text,
  note               text,
  result_note        text,
  created_by_code    text,
  updated_by_code    text,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz,
  updated_at         timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok   boolean := false;
  v_case bigint;
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

  select cs.id into v_case from public.cases cs where cs.id = p_case_id;
  if v_case is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  return query
  select
    a.id, a.case_id, a.appointment_type, a.appointment_title, a.appointment_status,
    a.appointment_date, a.appointment_time, a.location, a.officer_or_contact,
    a.note, a.result_note, a.created_by_code, a.updated_by_code,
    a.completed_at, a.cancelled_at, a.created_at, a.updated_at
  from public.case_appointments a
  where a.case_id = p_case_id
  order by a.appointment_date asc, a.appointment_time asc nulls last, a.created_at desc;
end;
$$;

revoke all on function public.app_list_case_appointments(text, text, bigint) from public;
grant execute on function public.app_list_case_appointments(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B2) app_save_case_appointment — staff/admin สร้าง/แก้ไขนัดหมาย
--
--     ⚠️ ข้อแตกต่างจาก spec เดิมโดยตั้งใจ (เหตุผลเดียวกับ 54A-6A):
--     p_appointment_type/p_appointment_title/p_appointment_status/p_appointment_date
--     ใช้ default null — เพราะถ้า default เป็นค่าคงที่ ('scheduled') เวลา frontend
--     update บาง field แล้วไม่ส่งค่ามา PostgREST จะเติม default ให้อัตโนมัติ
--     → ทับสถานะ/ค่าเดิมโดยไม่ตั้งใจ. ที่นี่ null = "คงค่าเดิม" ตอน update,
--     และ create บังคับต้องส่ง type/title/date ('scheduled' เป็นค่าตั้งต้นของสถานะ)
--     * update mode ไม่รับ p_case_id — ❌ ห้ามย้ายนัดไปเคสอื่น
--     * text fields: null = คงเดิม, '' = ล้างค่า (ไม่มี destructive clearing โดยไม่ตั้งใจ)
-- =============================================================
create or replace function public.app_save_case_appointment(
  p_user_id            text,
  p_username           text,
  p_appointment_id     bigint default null,   -- null = สร้างใหม่
  p_case_id            bigint default null,   -- จำเป็นตอนสร้าง (update ไม่ใช้)
  p_appointment_type   text default null,     -- จำเป็นตอนสร้าง
  p_appointment_title  text default null,     -- จำเป็นตอนสร้าง
  p_appointment_status text default null,     -- null = 'scheduled' (create) / คงเดิม (update)
  p_appointment_date   date default null,     -- จำเป็นตอนสร้าง
  p_appointment_time   time default null,
  p_location           text default null,
  p_officer_or_contact text default null,
  p_note               text default null,
  p_result_note        text default null
)
returns table (id bigint, case_id bigint, appointment_title text, appointment_status text, appointment_date date)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_type      text := lower(btrim(coalesce(p_appointment_type, '')));
  v_status    text := lower(btrim(coalesce(p_appointment_status, '')));
  v_case      bigint;
  v_old       record;
  v_id        bigint;
  v_action    text;
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

  if v_type <> '' and v_type not in ('document_prepare','submission','biometrics','medical',
                                     'training','payment','receive_result','follow_up','other') then
    raise exception 'invalid_appointment_type' using errcode = 'P0003';
  end if;
  if v_status <> '' and v_status not in ('scheduled','completed','missed','postponed','cancelled') then
    raise exception 'invalid_appointment_status' using errcode = 'P0003';
  end if;

  if p_appointment_id is null then
    -- ── CREATE: ต้องมีเคสจริง + type/title/date ครบ ──
    if p_case_id is null or v_type = ''
       or coalesce(btrim(coalesce(p_appointment_title,'')),'') = ''
       or p_appointment_date is null then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    select cs.id into v_case from public.cases cs where cs.id = p_case_id;
    if v_case is null then
      raise exception 'case_not_found' using errcode = 'P0002';
    end if;
    if v_status = '' then v_status := 'scheduled'; end if;

    insert into public.case_appointments
      (case_id, appointment_type, appointment_title, appointment_status,
       appointment_date, appointment_time, location, officer_or_contact,
       note, result_note, completed_at, cancelled_at, created_by_code, updated_by_code)
    values
      (v_case, v_type, btrim(p_appointment_title), v_status,
       p_appointment_date, p_appointment_time,
       nullif(btrim(coalesce(p_location,'')),''),
       nullif(btrim(coalesce(p_officer_or_contact,'')),''),
       nullif(btrim(coalesce(p_note,'')),''),
       nullif(btrim(coalesce(p_result_note,'')),''),
       case when v_status = 'completed' then now() else null end,
       case when v_status = 'cancelled' then now() else null end,
       p_username, p_username)
    returning case_appointments.id into v_id;
    v_action := 'case.appointment.create';
  else
    -- ── UPDATE: แก้เฉพาะ field ที่ส่งมา (❌ ไม่ย้ายเคสของนัดเดิม) ──
    select a.case_id, a.appointment_status, a.completed_at, a.cancelled_at into v_old
    from public.case_appointments a
    where a.id = p_appointment_id;
    if v_old.case_id is null then
      raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;
    v_case := v_old.case_id;
    if v_status = '' then v_status := v_old.appointment_status; end if;

    update public.case_appointments a
    set appointment_type   = case when v_type = '' then a.appointment_type else v_type end,
        appointment_title  = coalesce(nullif(btrim(coalesce(p_appointment_title,'')),''), a.appointment_title),
        appointment_status = v_status,
        appointment_date   = coalesce(p_appointment_date, a.appointment_date),
        appointment_time   = coalesce(p_appointment_time, a.appointment_time),
        location           = case when p_location is null then a.location else nullif(btrim(p_location),'') end,
        officer_or_contact = case when p_officer_or_contact is null then a.officer_or_contact else nullif(btrim(p_officer_or_contact),'') end,
        note               = case when p_note is null then a.note else nullif(btrim(p_note),'') end,
        result_note        = case when p_result_note is null then a.result_note else nullif(btrim(p_result_note),'') end,
        completed_at       = case when v_status = 'completed' and v_old.completed_at is null then now() else a.completed_at end,
        cancelled_at       = case when v_status = 'cancelled' and v_old.cancelled_at is null then now() else a.cancelled_at end,
        updated_by_code    = p_username,
        updated_at         = now()
    where a.id = p_appointment_id
    returning a.id into v_id;
    v_action := 'case.appointment.update';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_appointment', v_id::text,
            jsonb_build_object('case_id', v_case, 'status', v_status, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select a.id, a.case_id, a.appointment_title, a.appointment_status, a.appointment_date
  from public.case_appointments a where a.id = v_id;
end;
$$;

revoke all on function public.app_save_case_appointment(
  text, text, bigint, bigint, text, text, text, date, time, text, text, text, text
) from public;
grant execute on function public.app_save_case_appointment(
  text, text, bigint, bigint, text, text, text, date, time, text, text, text, text
) to anon, authenticated;

-- =============================================================
-- B3) app_set_case_appointment_status — staff/admin เปลี่ยนสถานะเท่านั้น (soft)
--     completed/cancelled ประทับเวลาเฉพาะครั้งแรก — ไม่ล้างเวลาเดิมทิ้ง
-- =============================================================
create or replace function public.app_set_case_appointment_status(
  p_user_id            text,
  p_username           text,
  p_appointment_id     bigint,
  p_appointment_status text,
  p_result_note        text default null
)
returns table (id bigint, appointment_status text, completed_at timestamptz, cancelled_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_status    text := lower(btrim(coalesce(p_appointment_status, '')));
  v_id        bigint;
  v_case_id   bigint;
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

  if v_status not in ('scheduled','completed','missed','postponed','cancelled') then
    raise exception 'invalid_appointment_status' using errcode = 'P0003';
  end if;

  update public.case_appointments a
  set appointment_status = v_status,
      result_note        = case when p_result_note is null then a.result_note else nullif(btrim(p_result_note),'') end,
      completed_at       = case when v_status = 'completed' and a.completed_at is null then now() else a.completed_at end,
      cancelled_at       = case when v_status = 'cancelled' and a.cancelled_at is null then now() else a.cancelled_at end,
      updated_by_code    = p_username,
      updated_at         = now()
  where a.id = p_appointment_id
  returning a.id, a.case_id into v_id, v_case_id;

  if v_id is null then
    raise exception 'appointment_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.appointment.status', 'case_appointment', v_id::text,
            jsonb_build_object('case_id', v_case_id, 'status', v_status, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select a.id, a.appointment_status, a.completed_at, a.cancelled_at
  from public.case_appointments a where a.id = v_id;
end;
$$;

revoke all on function public.app_set_case_appointment_status(text, text, bigint, text, text) from public;
grant execute on function public.app_set_case_appointment_status(text, text, bigint, text, text) to anon, authenticated;

-- =============================================================
-- B4) app_case_appointment_summary — นับนัดหมายของเคส (สำหรับ chip ใน case detail)
--     upcoming = scheduled และ appointment_date >= วันนี้
--     overdue  = scheduled และ appointment_date < วันนี้
-- =============================================================
create or replace function public.app_case_appointment_summary(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  total_count     bigint,
  scheduled_count bigint,
  completed_count bigint,
  missed_count    bigint,
  postponed_count bigint,
  cancelled_count bigint,
  upcoming_count  bigint,
  overdue_count   bigint
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
    count(*)                                                        as total_count,
    count(*) filter (where a.appointment_status = 'scheduled')      as scheduled_count,
    count(*) filter (where a.appointment_status = 'completed')      as completed_count,
    count(*) filter (where a.appointment_status = 'missed')         as missed_count,
    count(*) filter (where a.appointment_status = 'postponed')      as postponed_count,
    count(*) filter (where a.appointment_status = 'cancelled')      as cancelled_count,
    count(*) filter (where a.appointment_status = 'scheduled'
                     and a.appointment_date >= current_date)        as upcoming_count,
    count(*) filter (where a.appointment_status = 'scheduled'
                     and a.appointment_date < current_date)         as overdue_count
  from public.case_appointments a
  where a.case_id = p_case_id;
end;
$$;

revoke all on function public.app_case_appointment_summary(text, text, bigint) from public;
grant execute on function public.app_case_appointment_summary(text, text, bigint) to anon, authenticated;
