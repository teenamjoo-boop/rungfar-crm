-- =============================================================
-- STAGE 54A-5 — Employer Profile + Establishments Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * ขยาย metadata นายจ้าง (public.employers = master เดิม — ไม่ rename/ไม่ลบคอลัมน์)
--   * เพิ่มตาราง establishments (สถานที่ทำงาน/สาขา ใต้นายจ้าง)
--   * RPC อ่านรายละเอียดนายจ้าง (แรงงานใต้สังกัด + establishments + สรุปเอกสาร)
--   * เตรียมรองรับเอกสารนายจ้างด้วยโครง owner_type='employer' จาก 54A-1B
--     (อ่านนับจำนวนเท่านั้น — ❌ ไม่สร้างทางอัปโหลดใหม่ใน stage นี้)
--
--   หมายเหตุคอลัมน์ที่ "ไม่เพิ่ม" เพราะมีของเดิมใช้แทนอยู่แล้ว:
--     contact_person / phone / address / note / updated_at → ใช้คอลัมน์เดิม
--     (spec แนะ contact_phone/address_line — ซ้ำกับ phone/address เดิม จึงไม่เพิ่ม)
--
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE/Meta/import-export/
--     delete approval/customer-doc-upload/Storage — และไม่แตะพฤติกรรม employer เดิม
--   ❗ additive + idempotent ล้วน — ไม่มี DROP/RENAME/DELETE ของ object เดิม
--   ❗ establishments: เขียนผ่าน RPC เท่านั้น, soft active/inactive, ❌ ไม่มี hard delete
--   ❗ FK establishments.employer_id → employers(id) แบบ "ไม่ cascade"
--     (ห้ามลบนายจ้างที่มีสถานประกอบการ — restrict โดย default)
--   ❗ ไม่สร้าง/ไม่ปลอมเอกสารราชการ, ไม่ automate เว็บราชการ
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A1) คอลัมน์ใหม่ของ employers (additive — ไม่แตะคอลัมน์/แถวเดิม)
-- =============================================================
alter table public.employers add column if not exists employer_kind text not null default 'company';
alter table public.employers add column if not exists registration_no text;
alter table public.employers add column if not exists tax_id text;
alter table public.employers add column if not exists contact_email text;
alter table public.employers add column if not exists line_id text;
alter table public.employers add column if not exists subdistrict text;
alter table public.employers add column if not exists district text;
alter table public.employers add column if not exists province text;
alter table public.employers add column if not exists postcode text;
alter table public.employers add column if not exists business_description text;
alter table public.employers add column if not exists authorized_signatory text;
alter table public.employers add column if not exists authorized_signatory_position text;
alter table public.employers add column if not exists phase2_note text;
alter table public.employers add column if not exists updated_by_code text;

-- CHECK employer_kind (guarded — แถวเดิมได้ 'company' จาก default อัตโนมัติ)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'employers_kind_check'
      and conrelid = 'public.employers'::regclass
  ) then
    alter table public.employers
      add constraint employers_kind_check
      check (employer_kind in ('company','individual','other'));
  end if;
end$$;

-- =============================================================
-- A2) ตาราง establishments — สถานที่ทำงาน/สาขา ใต้นายจ้าง
-- =============================================================
create table if not exists public.establishments (
  id                 bigserial primary key,
  employer_id        bigint not null references public.employers(id),
  establishment_code text null,
  name               text not null,
  branch_name        text null,
  address_line       text null,
  subdistrict        text null,
  district           text null,
  province           text null,
  postcode           text null,
  contact_person     text null,
  contact_phone      text null,
  note               text null,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  created_by_code    text null,
  updated_at         timestamptz null,
  updated_by_code    text null
);

comment on table public.establishments is
  'STAGE 54A-5: สถานประกอบการ/สถานที่ทำงานใต้นายจ้าง (Phase 2) — ข้อมูลภายใน CRM เท่านั้น. เขียนผ่าน RPC เท่านั้น (app_save_establishment / app_set_establishment_active) — ห้าม grant เขียนตรงให้ anon/authenticated. soft active/inactive เท่านั้น ไม่มี hard delete';

create index if not exists idx_establishments_employer
  on public.establishments (employer_id, is_active, name);
create index if not exists idx_establishments_province
  on public.establishments (province);

-- ── ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2/3/4) ──
revoke all on table public.establishments from public, anon, authenticated;
revoke all on sequence public.establishments_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_employers_phase2 — staff/admin อ่านรายชื่อนายจ้าง + จำนวนแรงงาน/สาขา
--     metadata เท่านั้น — ❌ ไม่มี path/file/URL ใด ๆ
-- =============================================================
create or replace function public.app_list_employers_phase2(
  p_user_id  text,
  p_username text,
  p_search   text default null,
  p_limit    integer default 100,
  p_offset   integer default 0
)
returns table (
  id                  bigint,
  name                text,
  business_type       text,
  employer_kind       text,
  registration_no     text,
  tax_id              text,
  phone               text,
  contact_person      text,
  province            text,
  worker_count        bigint,
  establishment_count bigint,
  updated_at          timestamptz,
  total_count         bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok     boolean := false;
  v_limit  integer := coalesce(p_limit, 100);
  v_offset integer := coalesce(p_offset, 0);
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

  if v_limit is null or v_limit < 1 then v_limit := 100;
  elsif v_limit > 200 then v_limit := 200; end if;
  if v_offset is null or v_offset < 0 then v_offset := 0; end if;

  return query
  select
    e.id, e.name, e.business_type, e.employer_kind, e.registration_no, e.tax_id,
    e.phone, e.contact_person, e.province,
    (select count(*) from public.customers c
      where c.employer_id = e.id and c.deleted_at is null)          as worker_count,
    (select count(*) from public.establishments s
      where s.employer_id = e.id and s.is_active)                   as establishment_count,
    e.updated_at,
    count(*) over ()                                                as total_count
  from public.employers e
  where (
    p_search is null or p_search = ''
    or e.name            ilike '%' || p_search || '%'
    or e.business_type   ilike '%' || p_search || '%'
    or e.registration_no ilike '%' || p_search || '%'
    or e.tax_id          ilike '%' || p_search || '%'
    or e.contact_person  ilike '%' || p_search || '%'
  )
  order by e.name
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.app_list_employers_phase2(text, text, text, integer, integer) from public;
grant execute on function public.app_list_employers_phase2(text, text, text, integer, integer) to anon, authenticated;

-- =============================================================
-- B2) app_get_employer_detail — jsonb {employer, establishments, workers, documents_summary}
--     workers = customers ที่ employer_id ตรงและไม่ถูก soft delete
--     documents_summary = นับเอกสาร owner_type='employer' (โครง 54A-1B) — อ่านอย่างเดียว
--     ❌ ไม่มี storage_path / file_data / base64 / signed URL
-- =============================================================
create or replace function public.app_get_employer_detail(
  p_user_id     text,
  p_username    text,
  p_employer_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    boolean := false;
  v_emp   jsonb;
  v_est   jsonb;
  v_wrk   jsonb;
  v_docs  bigint := 0;
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

  select to_jsonb(x) into v_emp
  from (
    select id, name, business_type, employer_kind, registration_no, tax_id,
           phone, contact_person, contact_email, line_id,
           address, subdistrict, district, province, postcode,
           business_description, authorized_signatory, authorized_signatory_position,
           phase2_note, note, updated_at, updated_by_code
    from public.employers
    where id = p_employer_id
  ) x;

  if v_emp is null then
    raise exception 'employer_not_found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.is_active desc, s.name), '[]'::jsonb)
    into v_est
  from (
    select id, employer_id, establishment_code, name, branch_name,
           address_line, subdistrict, district, province, postcode,
           contact_person, contact_phone, note, is_active,
           created_at, created_by_code, updated_at, updated_by_code
    from public.establishments
    where employer_id = p_employer_id
  ) s;

  select coalesce(jsonb_agg(to_jsonb(w) order by w.name), '[]'::jsonb)
    into v_wrk
  from (
    select c.id, c.name, c.nationality, c.work_status,
           c.passport_no, c.alien_id, c.wp_no,
           c.exp_visa, c.exp_wp, c.next_90
    from public.customers c
    where c.employer_id = p_employer_id and c.deleted_at is null
  ) w;

  select count(*) into v_docs
  from public.documents d
  where d.owner_type = 'employer' and d.owner_id = p_employer_id;

  return jsonb_build_object(
    'employer', v_emp,
    'establishments', v_est,
    'workers', v_wrk,
    'documents_summary', jsonb_build_object('employer_documents', v_docs)
  );
end;
$$;

revoke all on function public.app_get_employer_detail(text, text, bigint) from public;
grant execute on function public.app_get_employer_detail(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B3) app_save_employer_phase2 — staff/admin สร้าง/แก้ไขโปรไฟล์นายจ้าง (audited)
--     * สิทธิ์ staff+admin: สอดคล้อง app_save_employer เดิม (พนักงานแก้นายจ้างได้อยู่แล้ว)
--     * ต่างจากเดิม: validate employer_kind + server-stamp updated_by_code + audit log
--     * ส่ง '' = ล้างค่า field นั้น (nullif) — ไม่ส่ง (null) = คงค่าเดิม
-- =============================================================
create or replace function public.app_save_employer_phase2(
  p_user_id                       text,
  p_username                      text,
  p_employer_id                   bigint default null,   -- null = สร้างใหม่
  p_name                          text default null,
  p_business_type                 text default null,
  p_phone                         text default null,
  p_contact_person                text default null,
  p_address                       text default null,
  p_note                          text default null,
  p_employer_kind                 text default null,
  p_registration_no               text default null,
  p_tax_id                        text default null,
  p_contact_email                 text default null,
  p_line_id                       text default null,
  p_subdistrict                   text default null,
  p_district                      text default null,
  p_province                      text default null,
  p_postcode                      text default null,
  p_business_description          text default null,
  p_authorized_signatory          text default null,
  p_authorized_signatory_position text default null,
  p_phase2_note                   text default null
)
returns table (id bigint, name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_kind      text := lower(btrim(coalesce(p_employer_kind, '')));
  v_id        bigint;
  v_action    text;
begin
  -- ── ตัวตน: staff/admin active (สิทธิ์เดียวกับ app_save_employer เดิม) ──
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

  if v_kind <> '' and v_kind not in ('company','individual','other') then
    raise exception 'invalid_employer_kind' using errcode = 'P0003';
  end if;

  if p_employer_id is null then
    -- ── CREATE — ต้องมีชื่อ ──
    if coalesce(btrim(coalesce(p_name,'')), '') = '' then
      raise exception 'name_required' using errcode = 'P0003';
    end if;
    insert into public.employers
      (name, business_type, phone, contact_person, address, note,
       employer_kind, registration_no, tax_id, contact_email, line_id,
       subdistrict, district, province, postcode,
       business_description, authorized_signatory, authorized_signatory_position,
       phase2_note, updated_at, updated_by_code)
    values
      (btrim(p_name),
       nullif(btrim(coalesce(p_business_type,'')),''),
       nullif(btrim(coalesce(p_phone,'')),''),
       nullif(btrim(coalesce(p_contact_person,'')),''),
       nullif(btrim(coalesce(p_address,'')),''),
       nullif(btrim(coalesce(p_note,'')),''),
       case when v_kind = '' then 'company' else v_kind end,
       nullif(btrim(coalesce(p_registration_no,'')),''),
       nullif(btrim(coalesce(p_tax_id,'')),''),
       nullif(btrim(coalesce(p_contact_email,'')),''),
       nullif(btrim(coalesce(p_line_id,'')),''),
       nullif(btrim(coalesce(p_subdistrict,'')),''),
       nullif(btrim(coalesce(p_district,'')),''),
       nullif(btrim(coalesce(p_province,'')),''),
       nullif(btrim(coalesce(p_postcode,'')),''),
       nullif(btrim(coalesce(p_business_description,'')),''),
       nullif(btrim(coalesce(p_authorized_signatory,'')),''),
       nullif(btrim(coalesce(p_authorized_signatory_position,'')),''),
       nullif(btrim(coalesce(p_phase2_note,'')),''),
       now(), p_username)
    returning employers.id into v_id;
    v_action := 'employer.phase2.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา (null = คงเดิม, '' = ล้างค่า) ──
    update public.employers e
    set name           = coalesce(nullif(btrim(coalesce(p_name,'')),''), e.name),
        business_type  = case when p_business_type is null then e.business_type else nullif(btrim(p_business_type),'') end,
        phone          = case when p_phone is null then e.phone else nullif(btrim(p_phone),'') end,
        contact_person = case when p_contact_person is null then e.contact_person else nullif(btrim(p_contact_person),'') end,
        address        = case when p_address is null then e.address else nullif(btrim(p_address),'') end,
        note           = case when p_note is null then e.note else nullif(btrim(p_note),'') end,
        employer_kind  = case when v_kind = '' then e.employer_kind else v_kind end,
        registration_no = case when p_registration_no is null then e.registration_no else nullif(btrim(p_registration_no),'') end,
        tax_id         = case when p_tax_id is null then e.tax_id else nullif(btrim(p_tax_id),'') end,
        contact_email  = case when p_contact_email is null then e.contact_email else nullif(btrim(p_contact_email),'') end,
        line_id        = case when p_line_id is null then e.line_id else nullif(btrim(p_line_id),'') end,
        subdistrict    = case when p_subdistrict is null then e.subdistrict else nullif(btrim(p_subdistrict),'') end,
        district       = case when p_district is null then e.district else nullif(btrim(p_district),'') end,
        province       = case when p_province is null then e.province else nullif(btrim(p_province),'') end,
        postcode       = case when p_postcode is null then e.postcode else nullif(btrim(p_postcode),'') end,
        business_description = case when p_business_description is null then e.business_description else nullif(btrim(p_business_description),'') end,
        authorized_signatory = case when p_authorized_signatory is null then e.authorized_signatory else nullif(btrim(p_authorized_signatory),'') end,
        authorized_signatory_position = case when p_authorized_signatory_position is null then e.authorized_signatory_position else nullif(btrim(p_authorized_signatory_position),'') end,
        phase2_note    = case when p_phase2_note is null then e.phase2_note else nullif(btrim(p_phase2_note),'') end,
        updated_at     = now(),
        updated_by_code = p_username
    where e.id = p_employer_id
    returning e.id into v_id;

    if v_id is null then
      raise exception 'employer_not_found' using errcode = 'P0002';
    end if;
    v_action := 'employer.phase2.save';
  end if;

  -- ── audit log ฝั่ง server (best-effort — pattern 20260728) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'employer', v_id::text,
            jsonb_build_object('internal_only', true));
  exception when others then null;
  end;

  return query
  select e.id, e.name from public.employers e where e.id = v_id;
end;
$$;

revoke all on function public.app_save_employer_phase2(
  text, text, bigint, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text, text, text, text
) from public;
grant execute on function public.app_save_employer_phase2(
  text, text, bigint, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text, text, text, text, text, text
) to anon, authenticated;

-- =============================================================
-- B4) app_save_establishment — staff/admin สร้าง/แก้ไขสถานประกอบการ
-- =============================================================
create or replace function public.app_save_establishment(
  p_user_id            text,
  p_username           text,
  p_establishment_id   bigint default null,   -- null = สร้างใหม่
  p_employer_id        bigint default null,   -- จำเป็นตอนสร้าง
  p_establishment_code text default null,
  p_name               text default null,
  p_branch_name        text default null,
  p_address_line       text default null,
  p_subdistrict        text default null,
  p_district           text default null,
  p_province           text default null,
  p_postcode           text default null,
  p_contact_person     text default null,
  p_contact_phone      text default null,
  p_note               text default null
)
returns table (id bigint, employer_id bigint, name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_id        bigint;
  v_emp       bigint;
  v_action    text;
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

  if p_establishment_id is null then
    -- ── CREATE — ต้องมีนายจ้างจริง + ชื่อ ──
    if p_employer_id is null or coalesce(btrim(coalesce(p_name,'')), '') = '' then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    select e.id into v_emp from public.employers e where e.id = p_employer_id;
    if v_emp is null then
      raise exception 'employer_not_found' using errcode = 'P0002';
    end if;
    insert into public.establishments
      (employer_id, establishment_code, name, branch_name, address_line,
       subdistrict, district, province, postcode,
       contact_person, contact_phone, note, created_by_code, updated_at, updated_by_code)
    values
      (v_emp,
       nullif(btrim(coalesce(p_establishment_code,'')),''),
       btrim(p_name),
       nullif(btrim(coalesce(p_branch_name,'')),''),
       nullif(btrim(coalesce(p_address_line,'')),''),
       nullif(btrim(coalesce(p_subdistrict,'')),''),
       nullif(btrim(coalesce(p_district,'')),''),
       nullif(btrim(coalesce(p_province,'')),''),
       nullif(btrim(coalesce(p_postcode,'')),''),
       nullif(btrim(coalesce(p_contact_person,'')),''),
       nullif(btrim(coalesce(p_contact_phone,'')),''),
       nullif(btrim(coalesce(p_note,'')),''),
       p_username, now(), p_username)
    returning establishments.id, establishments.employer_id into v_id, v_emp;
    v_action := 'establishment.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา (❌ ไม่ย้าย employer_id ของสาขาเดิม) ──
    update public.establishments s
    set establishment_code = case when p_establishment_code is null then s.establishment_code else nullif(btrim(p_establishment_code),'') end,
        name           = coalesce(nullif(btrim(coalesce(p_name,'')),''), s.name),
        branch_name    = case when p_branch_name is null then s.branch_name else nullif(btrim(p_branch_name),'') end,
        address_line   = case when p_address_line is null then s.address_line else nullif(btrim(p_address_line),'') end,
        subdistrict    = case when p_subdistrict is null then s.subdistrict else nullif(btrim(p_subdistrict),'') end,
        district       = case when p_district is null then s.district else nullif(btrim(p_district),'') end,
        province       = case when p_province is null then s.province else nullif(btrim(p_province),'') end,
        postcode       = case when p_postcode is null then s.postcode else nullif(btrim(p_postcode),'') end,
        contact_person = case when p_contact_person is null then s.contact_person else nullif(btrim(p_contact_person),'') end,
        contact_phone  = case when p_contact_phone is null then s.contact_phone else nullif(btrim(p_contact_phone),'') end,
        note           = case when p_note is null then s.note else nullif(btrim(p_note),'') end,
        updated_at     = now(),
        updated_by_code = p_username
    where s.id = p_establishment_id
    returning s.id, s.employer_id into v_id, v_emp;

    if v_id is null then
      raise exception 'establishment_not_found' using errcode = 'P0002';
    end if;
    v_action := 'establishment.update';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'establishment', v_id::text,
            jsonb_build_object('employer_id', v_emp, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select s.id, s.employer_id, s.name
  from public.establishments s where s.id = v_id;
end;
$$;

revoke all on function public.app_save_establishment(
  text, text, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text
) from public;
grant execute on function public.app_save_establishment(
  text, text, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text
) to anon, authenticated;

-- =============================================================
-- B5) app_set_establishment_active — admin เท่านั้น: soft เปิด/ปิดใช้งาน
--     (ตาม pattern เดิมของระบบ: การเปิด/ปิดสถานะ entity เช่น user enable/disable
--      และ delete group เป็น admin-only — ❌ ไม่มี hard delete)
-- =============================================================
create or replace function public.app_set_establishment_active(
  p_user_id          text,
  p_username         text,
  p_establishment_id bigint,
  p_is_active        boolean
)
returns table (id bigint, is_active boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_id        bigint;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  -- เปิด/ปิดสถานะ = admin เท่านั้น (server-side บังคับจริง ไม่ใช่แค่ซ่อนปุ่ม)
  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_establishment_id is null or p_is_active is null then
    raise exception 'invalid_arguments' using errcode = 'P0003';
  end if;

  update public.establishments s
  set is_active = p_is_active, updated_at = now(), updated_by_code = p_username
  where s.id = p_establishment_id
  returning s.id into v_id;

  if v_id is null then
    raise exception 'establishment_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'establishment.set_active', 'establishment', v_id::text,
            jsonb_build_object('is_active', p_is_active, 'soft_toggle', true, 'internal_only', true));
  exception when others then null;
  end;

  return query select v_id, p_is_active;
end;
$$;

revoke all on function public.app_set_establishment_active(text, text, bigint, boolean) from public;
grant execute on function public.app_set_establishment_active(text, text, bigint, boolean) to anon, authenticated;

-- =============================================================
-- หมายเหตุ RPC เอกสารนายจ้าง (ข้อ 6 ใน spec):
--   ❌ ไม่สร้าง app_list_employer_documents ใหม่ — app_list_documents (54A-1B)
--   รองรับ p_owner_type='employer' + p_owner_id อยู่แล้ว (metadata-only)
--   stage นี้แสดงแค่ "จำนวนเอกสารนายจ้าง" ใน app_get_employer_detail
--   ทางอัปโหลดเอกสารนายจ้างจะทำผ่านคลังเอกสารใน stage ถัดไป
-- =============================================================
