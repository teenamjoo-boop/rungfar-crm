-- =============================================================
-- PRODUCTION ROLLOUT — หน้าลิงก์นายจ้าง/กลุ่ม + ตารางชีส + เอกสารนายจ้าง (2026-10-12)
--   รันบน: PRODUCTION เท่านั้น (rungfar-crm / magwqolbjmwymqxelizl) — ตรวจชื่อโปรเจกต์มุมซ้ายบนก่อนกด Run
--   รวม 5 ไฟล์ที่ผ่าน Staging แล้ว (เรียงตามลำดับ) ทั้งหมดเป็นแบบเพิ่มอย่างเดียว ไม่ลบข้อมูล รันซ้ำได้
--     1) 20261009_app_alert_settings.sql
--     2) 20261009_employer_share_links.sql
--     3) 20261010_sheet_view_employer_docs.sql
--     4) 20261012_group_share_links.sql
--     5) 20261013_group_share_banner.sql
--   ห่อด้วย BEGIN/COMMIT — ถ้าผิดพลาดจุดไหน จะย้อนกลับทั้งหมด (ไม่ค้างครึ่ง ๆ)
--   ผลที่ควรได้ (แถวสุดท้าย): tables_ok=3 · cols_ok=3 · rpc_ok=9 · owner_check=1 · group_owner_ok=1 · grants_ok=true
-- =============================================================
begin;

-- ##### 20261009_app_alert_settings.sql #####
-- =============================================================
-- STAGE ALERT-SETTINGS-DB — ค่าแจ้งเตือนล่วงหน้า (วัน) เก็บในฐานข้อมูลที่เดียว — additive
-- ปัญหาเดิม:
--   หน้า "ตั้งค่าแจ้งเตือน" เก็บค่าใน localStorage ของเบราว์เซอร์แต่ละเครื่อง
--   → คอมแต่ละเครื่องเตือนไม่เท่ากัน และหน้าลิงก์ลูกค้า (employer-share-view) อ่านค่าไม่ได้
-- ทำ:
--   A) ตาราง public.app_alert_settings (1 แถวเท่านั้น id=1) — RLS เปิด 0 policy, anon/authenticated ไม่มีสิทธิ์ตรง
--      service_role อ่านได้ (Edge Function ส่งค่าให้หน้าลิงก์ลูกค้า)
--   B) app_get_alert_settings  — ผู้ใช้ที่ active ทุกคนอ่านได้
--   C) app_save_alert_settings — admin เท่านั้น (หน้า ตั้งค่าแจ้งเตือน อยู่ในส่วนผู้ดูแลระบบ) + audit
--   ค่าเริ่มต้น = ค่าที่เจ้าของตั้งไว้ในหน้า ตั้งค่าแจ้งเตือน ณ 2026-10-09: พาสปอร์ต 30, VISA 30, WP 60, 90 วัน 7, MOU 60
-- ❗ ไม่แตะตารางธุรกิจเดิม / ไม่มี DELETE / DROP
-- ⚠️ Idempotent — รันซ้ำได้ (แถวค่าเริ่มต้นใส่ครั้งแรกเท่านั้น ไม่ทับค่าที่แก้แล้ว)
-- =============================================================

create table if not exists public.app_alert_settings (
  id              smallint    primary key default 1 check (id = 1),
  passport        integer     not null default 30 check (passport between 1 and 3650),
  visa            integer     not null default 30 check (visa     between 1 and 3650),
  wp              integer     not null default 60 check (wp       between 1 and 3650),
  next90          integer     not null default 7  check (next90   between 1 and 3650),
  mou             integer     not null default 60 check (mou      between 1 and 3650),
  updated_at      timestamptz not null default now(),
  updated_by_code text
);

alter table public.app_alert_settings enable row level security;
revoke all on table public.app_alert_settings from public, anon, authenticated;
-- Edge Function employer-share-view อ่านค่านี้ด้วย service role (โปรเจกต์นี้ต้อง grant ระบุชัด)
grant select on table public.app_alert_settings to service_role;

insert into public.app_alert_settings (id, passport, visa, wp, next90, mou)
values (1, 30, 30, 60, 7, 60)
on conflict (id) do nothing;

-- =============================================================
-- B) app_get_alert_settings
-- =============================================================
create or replace function public.app_get_alert_settings(
  p_user_id  text,
  p_username text
)
returns table (
  passport integer, visa integer, wp integer, next90 integer, mou integer,
  updated_at timestamptz, updated_by_code text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
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
  select s.passport, s.visa, s.wp, s.next90, s.mou, s.updated_at, s.updated_by_code
  from public.app_alert_settings s
  where s.id = 1;
end;
$$;

revoke all on function public.app_get_alert_settings(text, text) from public;
grant execute on function public.app_get_alert_settings(text, text) to anon, authenticated;

-- =============================================================
-- C) app_save_alert_settings — admin เท่านั้น
-- =============================================================
create or replace function public.app_save_alert_settings(
  p_user_id  text,
  p_username text,
  p_passport integer,
  p_visa     integer,
  p_wp       integer,
  p_next90   integer,
  p_mou      integer
)
returns table (
  passport integer, visa integer, wp integer, next90 integer, mou integer,
  updated_at timestamptz, updated_by_code text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) or v_role <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_passport is null or p_visa is null or p_wp is null or p_next90 is null or p_mou is null
     or least(p_passport, p_visa, p_wp, p_next90, p_mou) < 1
     or greatest(p_passport, p_visa, p_wp, p_next90, p_mou) > 3650 then
    raise exception 'invalid_value' using errcode = 'P0003';
  end if;

  insert into public.app_alert_settings as s (id, passport, visa, wp, next90, mou, updated_at, updated_by_code)
  values (1, p_passport, p_visa, p_wp, p_next90, p_mou, now(), p_username)
  on conflict (id) do update
     set passport = excluded.passport, visa = excluded.visa, wp = excluded.wp,
         next90 = excluded.next90, mou = excluded.mou,
         updated_at = excluded.updated_at, updated_by_code = excluded.updated_by_code;

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'settings.alert.save', 'settings', '1',
            jsonb_build_object('passport', p_passport, 'visa', p_visa, 'wp', p_wp,
                               'next90', p_next90, 'mou', p_mou, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select s.passport, s.visa, s.wp, s.next90, s.mou, s.updated_at, s.updated_by_code
  from public.app_alert_settings s
  where s.id = 1;
end;
$$;

revoke all on function public.app_save_alert_settings(text, text, integer, integer, integer, integer, integer) from public;
grant execute on function public.app_save_alert_settings(text, text, integer, integer, integer, integer, integer) to anon, authenticated;

-- ##### 20261009_employer_share_links.sql #####
-- =============================================================
-- STAGE SHARE-001 — Employer share link (ลิงก์ให้นายจ้างดูข้อมูลแรงงาน) — additive
-- เป้าหมาย:
--   * นายจ้าง 1 ราย มีลิงก์ที่ใช้งานได้ "ครั้งละ 1 ลิงก์" สำหรับส่งทาง LINE
--   * คนถือลิงก์เปิดดูได้อย่างเดียว (read-only) ผ่าน Edge Function employer-share-view
--     ❗ หน้าเว็บสาธารณะไม่อ่านตารางนี้ตรง — Edge Function ใช้ service role ฝั่ง server เท่านั้น
--   * staff/admin สร้าง / ดู / สร้างใหม่ (หมุน token) / ยกเลิก ผ่าน RPC ที่ตรวจตัวตนฝั่ง server
--
-- โครงสร้าง:
--   A) ตาราง public.employer_share_links (RLS เปิด, 0 policy, revoke anon/authenticated ทั้งหมด)
--   B) app_get_employer_share_link     — อ่านลิงก์ที่ active ของนายจ้าง
--   C) app_create_employer_share_link  — สร้าง (ถ้ามีอยู่แล้วคืนอันเดิม) / p_rotate=true = ยกเลิกอันเดิมแล้วสร้างใหม่
--   D) app_revoke_employer_share_link  — ยกเลิกลิงก์ที่ active
--
-- token: hex 64 ตัว (สุ่มจาก gen_random_uuid() 2 ครั้ง ≈ 244 bit) — เดาไม่ได้
--   เก็บ token ตรง ๆ เพื่อให้ staff "คัดลอกลิงก์เดิม" ได้อีกครั้ง; ตารางนี้ไม่มีสิทธิ์อ่านจาก anon/authenticated
--
-- audit: best-effort (pattern 20260728/20260804) — ❌ ไม่บันทึก token / URL ลงใน audit detail
--
-- ❗ ไม่แตะตาราง customers / employers / documents / Storage / RLS เดิม
-- ❗ ไม่มี DELETE / UPDATE ข้อมูลธุรกิจ / DROP
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A) ตาราง
-- =============================================================
create table if not exists public.employer_share_links (
  id               bigint generated always as identity primary key,
  employer_id      bigint      not null references public.employers(id),
  token            text        not null unique,
  created_at       timestamptz not null default now(),
  created_by_code  text,
  revoked_at       timestamptz,
  revoked_by_code  text,
  expires_at       timestamptz,          -- null = ไม่หมดอายุ (ยกเลิกเองได้)
  last_viewed_at   timestamptz,
  view_count       integer     not null default 0,
  constraint employer_share_links_token_format check (token ~ '^[0-9a-f]{64}$')
);

-- ลิงก์ที่ใช้งานได้ ต่อนายจ้าง ได้แค่ 1 อัน
create unique index if not exists uq_employer_share_links_active
  on public.employer_share_links (employer_id)
  where revoked_at is null;

alter table public.employer_share_links enable row level security;
-- ❗ ไม่สร้าง policy ใด ๆ — anon/authenticated อ่าน/เขียนตรงไม่ได้
revoke all on table public.employer_share_links from public, anon, authenticated;
revoke all on sequence public.employer_share_links_id_seq from public, anon, authenticated;
-- Edge Function employer-share-view ใช้ service role: อ่านลิงก์ + อัปเดต last_viewed_at/view_count เท่านั้น
-- (โปรเจกต์นี้ไม่ได้ให้สิทธิ์ service_role กับตารางใหม่อัตโนมัติ — ต้อง grant ระบุชัด, pattern เดียวกับ integration_request_logs)
grant select, update on table public.employer_share_links to service_role;

-- =============================================================
-- B) app_get_employer_share_link
-- =============================================================
create or replace function public.app_get_employer_share_link(
  p_user_id     text,
  p_username    text,
  p_employer_id bigint
)
returns table (
  token          text,
  created_at     timestamptz,
  created_by_code text,
  expires_at     timestamptz,
  last_viewed_at timestamptz,
  view_count     integer
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_active boolean := false;
begin
  select true into v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
  from public.employer_share_links l
  where l.employer_id = p_employer_id
    and l.revoked_at is null
  limit 1;
end;
$$;

revoke all on function public.app_get_employer_share_link(text, text, bigint) from public;
grant execute on function public.app_get_employer_share_link(text, text, bigint) to anon, authenticated;

-- =============================================================
-- C) app_create_employer_share_link
--    p_rotate = false → มีลิงก์ active อยู่แล้วคืนอันเดิม (กดซ้ำไม่สร้างซ้ำ)
--    p_rotate = true  → ยกเลิกอันเดิม แล้วสร้างอันใหม่ (ลิงก์เก่าที่ส่งไปแล้วจะเปิดไม่ได้)
-- =============================================================
create or replace function public.app_create_employer_share_link(
  p_user_id     text,
  p_username    text,
  p_employer_id bigint,
  p_rotate      boolean default false
)
returns table (
  token          text,
  created_at     timestamptz,
  created_by_code text,
  expires_at     timestamptz,
  last_viewed_at timestamptz,
  view_count     integer
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
  v_token     text;
  v_action    text := 'employer.share_link.create';
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_employer_id is null or not exists (select 1 from public.employers e where e.id = p_employer_id) then
    raise exception 'employer_not_found' using errcode = 'P0002';
  end if;

  -- กันกดพร้อมกัน 2 ครั้ง (lock ต่อนายจ้าง ภายใน transaction นี้)
  perform pg_advisory_xact_lock(hashtext('employer_share_link'), (p_employer_id % 2147483647)::int);

  if coalesce(p_rotate, false) then
    update public.employer_share_links l
       set revoked_at = now(), revoked_by_code = p_username
     where l.employer_id = p_employer_id and l.revoked_at is null;
    v_action := 'employer.share_link.rotate';
  elsif exists (select 1 from public.employer_share_links l
                where l.employer_id = p_employer_id and l.revoked_at is null) then
    return query
    select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
    from public.employer_share_links l
    where l.employer_id = p_employer_id and l.revoked_at is null
    limit 1;
    return;
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  insert into public.employer_share_links (employer_id, token, created_by_code)
  values (p_employer_id, v_token, p_username);

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'employer', p_employer_id::text,
            jsonb_build_object('internal_only', true));   -- ❌ ไม่ใส่ token/URL
  exception when others then null;
  end;

  return query
  select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
  from public.employer_share_links l
  where l.employer_id = p_employer_id and l.revoked_at is null
  limit 1;
end;
$$;

revoke all on function public.app_create_employer_share_link(text, text, bigint, boolean) from public;
grant execute on function public.app_create_employer_share_link(text, text, bigint, boolean) to anon, authenticated;

-- =============================================================
-- D) app_revoke_employer_share_link — คืนจำนวนลิงก์ที่ถูกยกเลิก (0 หรือ 1)
-- =============================================================
create or replace function public.app_revoke_employer_share_link(
  p_user_id     text,
  p_username    text,
  p_employer_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
  v_count     integer := 0;
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  update public.employer_share_links l
     set revoked_at = now(), revoked_by_code = p_username
   where l.employer_id = p_employer_id and l.revoked_at is null;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (p_username,
              coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
              v_role, 'employer.share_link.revoke', 'employer', p_employer_id::text,
              jsonb_build_object('internal_only', true));
    exception when others then null;
    end;
  end if;

  return v_count;
end;
$$;

revoke all on function public.app_revoke_employer_share_link(text, text, bigint) from public;
grant execute on function public.app_revoke_employer_share_link(text, text, bigint) to anon, authenticated;

-- ##### 20261010_sheet_view_employer_docs.sql #####
-- =============================================================
-- Stage SHEET-VIEW + EMP-DOCS (additive, ปลอดภัย, รันซ้ำได้)
--   1) customers: 3 ช่องใหม่ตามชีสงานจริง (ว่างได้ทั้งหมด — แถวเดิมไม่เปลี่ยน)
--        worker_category  = ประเภท (MOU / มติ.ครม. / อื่น ๆ — พิมพ์เองได้)
--        status_note      = สถานะ (ข้อความอิสระที่เจ้าหน้าที่เขียน เช่น "ถ่ายบัตรแล้ว")
--        work_items       = รายการ (ข้อความอิสระ — ยังไม่ fix รูปแบบ ปรับทีหลังได้)
--      * RPC app_save_customer / app_bulk_create_customers / app_bulk_update_customers
--        whitelist คอลัมน์จากสคีมาจริงอยู่แล้ว → รับ 3 ช่องนี้อัตโนมัติ ไม่ต้องแก้ RPC
--   2) documents: ให้เก็บ "เอกสารนายจ้าง" ได้ (owner_type='employer', ไม่มี customer_id)
--        - customer_id เลิกบังคับ NOT NULL
--        - constraint ใหม่: เอกสารลูกค้าต้องมี customer_id; เอกสารประเภทอื่นต้องมี owner_id
--      * ไม่มีการลบ/แก้แถวเดิม (แถวเดิมเป็น customer ทั้งหมด มี customer_id ครบ)
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf) — Production รอยืนยันแยก
-- =============================================================

alter table public.customers add column if not exists worker_category text;
alter table public.customers add column if not exists status_note     text;
alter table public.customers add column if not exists work_items      text;

alter table public.documents alter column customer_id drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'documents_owner_ref_check'
                   and conrelid = 'public.documents'::regclass) then
    alter table public.documents
      add constraint documents_owner_ref_check
      check (
        (owner_type = 'customer' and customer_id is not null)
        or (owner_type <> 'customer' and owner_id is not null)
      );
  end if;
end $$;

-- ตรวจผล (ควรได้: new_cols=3, customer_id_nullable=YES, owner_check=1)
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='customers'
      and column_name in ('worker_category','status_note','work_items'))          as new_cols,
  (select is_nullable from information_schema.columns
    where table_schema='public' and table_name='documents' and column_name='customer_id') as customer_id_nullable,
  (select count(*) from pg_constraint where conname='documents_owner_ref_check') as owner_check;

-- ##### 20261012_group_share_links.sql #####
-- =============================================================
-- STAGE SHARE-GROUP — ลิงก์รวมของ "กลุ่ม" (เช่น สวนยาง ที่มีหลายนายจ้าง) — additive
--   * กลุ่ม 1 กลุ่ม มีลิงก์ที่ใช้งานได้ครั้งละ 1 ลิงก์ → หน้าเว็บแสดงแรงงานทุกคนที่อยู่ในกลุ่มนี้ (customers.group_id)
--   * โครงสร้างเหมือน employer_share_links ทุกอย่าง (token hex 64, RLS เปิด 0 policy, service_role อ่าน/อัปเดตเท่านั้น)
--   * RPC: app_get / app_create / app_revoke _group_share_link (ตรวจตัวตนฝั่ง server, audit ไม่เก็บ token)
-- ❗ ไม่แตะตารางเดิมใด ๆ · ไม่มี DELETE / DROP · รันซ้ำได้
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf)
-- =============================================================

-- =============================================================
-- A) ตาราง
-- =============================================================
create table if not exists public.group_share_links (
  id               bigint generated always as identity primary key,
  group_id         bigint      not null references public.groups(id),
  token            text        not null unique,
  created_at       timestamptz not null default now(),
  created_by_code  text,
  revoked_at       timestamptz,
  revoked_by_code  text,
  expires_at       timestamptz,          -- null = ไม่หมดอายุ (ยกเลิกเองได้)
  last_viewed_at   timestamptz,
  view_count       integer     not null default 0,
  constraint group_share_links_token_format check (token ~ '^[0-9a-f]{64}$')
);

-- ลิงก์ที่ใช้งานได้ ต่อกลุ่ม ได้แค่ 1 อัน
create unique index if not exists uq_group_share_links_active
  on public.group_share_links (group_id)
  where revoked_at is null;

alter table public.group_share_links enable row level security;
-- ❗ ไม่สร้าง policy ใด ๆ — anon/authenticated อ่าน/เขียนตรงไม่ได้
revoke all on table public.group_share_links from public, anon, authenticated;
revoke all on sequence public.group_share_links_id_seq from public, anon, authenticated;
-- Edge Function employer-share-view ใช้ service role: อ่านลิงก์ + อัปเดต last_viewed_at/view_count เท่านั้น
-- (โปรเจกต์นี้ไม่ได้ให้สิทธิ์ service_role กับตารางใหม่อัตโนมัติ — ต้อง grant ระบุชัด, pattern เดียวกับ integration_request_logs)
grant select, update on table public.group_share_links to service_role;

-- =============================================================
-- B) app_get_group_share_link
-- =============================================================
create or replace function public.app_get_group_share_link(
  p_user_id     text,
  p_username    text,
  p_group_id bigint
)
returns table (
  token          text,
  created_at     timestamptz,
  created_by_code text,
  expires_at     timestamptz,
  last_viewed_at timestamptz,
  view_count     integer
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_active boolean := false;
begin
  select true into v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
  from public.group_share_links l
  where l.group_id = p_group_id
    and l.revoked_at is null
  limit 1;
end;
$$;

revoke all on function public.app_get_group_share_link(text, text, bigint) from public;
grant execute on function public.app_get_group_share_link(text, text, bigint) to anon, authenticated;

-- =============================================================
-- C) app_create_group_share_link
--    p_rotate = false → มีลิงก์ active อยู่แล้วคืนอันเดิม (กดซ้ำไม่สร้างซ้ำ)
--    p_rotate = true  → ยกเลิกอันเดิม แล้วสร้างอันใหม่ (ลิงก์เก่าที่ส่งไปแล้วจะเปิดไม่ได้)
-- =============================================================
create or replace function public.app_create_group_share_link(
  p_user_id     text,
  p_username    text,
  p_group_id bigint,
  p_rotate      boolean default false
)
returns table (
  token          text,
  created_at     timestamptz,
  created_by_code text,
  expires_at     timestamptz,
  last_viewed_at timestamptz,
  view_count     integer
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
  v_token     text;
  v_action    text := 'group.share_link.create';
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_group_id is null or not exists (select 1 from public.groups g where g.id = p_group_id) then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  -- กันกดพร้อมกัน 2 ครั้ง (lock ต่อกลุ่ม ภายใน transaction นี้)
  perform pg_advisory_xact_lock(hashtext('group_share_link'), (p_group_id % 2147483647)::int);

  if coalesce(p_rotate, false) then
    update public.group_share_links l
       set revoked_at = now(), revoked_by_code = p_username
     where l.group_id = p_group_id and l.revoked_at is null;
    v_action := 'group.share_link.rotate';
  elsif exists (select 1 from public.group_share_links l
                where l.group_id = p_group_id and l.revoked_at is null) then
    return query
    select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
    from public.group_share_links l
    where l.group_id = p_group_id and l.revoked_at is null
    limit 1;
    return;
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  insert into public.group_share_links (group_id, token, created_by_code)
  values (p_group_id, v_token, p_username);

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'group', p_group_id::text,
            jsonb_build_object('internal_only', true));   -- ❌ ไม่ใส่ token/URL
  exception when others then null;
  end;

  return query
  select l.token, l.created_at, l.created_by_code, l.expires_at, l.last_viewed_at, l.view_count
  from public.group_share_links l
  where l.group_id = p_group_id and l.revoked_at is null
  limit 1;
end;
$$;

revoke all on function public.app_create_group_share_link(text, text, bigint, boolean) from public;
grant execute on function public.app_create_group_share_link(text, text, bigint, boolean) to anon, authenticated;

-- =============================================================
-- D) app_revoke_group_share_link — คืนจำนวนลิงก์ที่ถูกยกเลิก (0 หรือ 1)
-- =============================================================
create or replace function public.app_revoke_group_share_link(
  p_user_id     text,
  p_username    text,
  p_group_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
  v_count     integer := 0;
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  update public.group_share_links l
     set revoked_at = now(), revoked_by_code = p_username
   where l.group_id = p_group_id and l.revoked_at is null;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (p_username,
              coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
              v_role, 'group.share_link.revoke', 'group', p_group_id::text,
              jsonb_build_object('internal_only', true));
    exception when others then null;
    end;
  end if;

  return v_count;
end;
$$;

revoke all on function public.app_revoke_group_share_link(text, text, bigint) from public;
grant execute on function public.app_revoke_group_share_link(text, text, bigint) to anon, authenticated;

-- ตรวจผล (ควรได้: table_ok=1, rpc_count=3)
select
  (select count(*) from information_schema.tables where table_schema='public' and table_name='group_share_links') as table_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('app_get_group_share_link','app_create_group_share_link','app_revoke_group_share_link')) as rpc_count;

-- ##### 20261013_group_share_banner.sql #####
-- =============================================================
-- STAGE SHARE-GROUP-BANNER — รูปพื้นหลังหน้าลิงก์ของ "กลุ่ม" (เช่น สวนยาง) — additive
--   * เก็บเป็นเอกสาร documents.owner_type = 'group', owner_id = groups.id, doc_type = 'share_banner'
--     (อัปโหลดผ่าน Edge Function customer-doc-upload เวอร์ชัน cdu5 ขึ้นไป — path groups/<id>/...)
--   * "ใช้พื้นหลังส้มเดิม" = เปลี่ยน doc_type เป็น share_banner_off ด้วย app_update_document_metadata เดิม (ไม่ลบไฟล์)
--   * RPC ใหม่: app_get_group_banner — CRM ใช้ดูว่ากลุ่มมีรูปพื้นหลังอยู่หรือไม่ (คืน metadata เท่านั้น ❌ ไม่คืน path)
-- ❗ ไม่ลบข้อมูล · ไม่มี DROP TABLE · รันซ้ำได้
--   (เปลี่ยน check constraint documents_owner_type_check ให้รับ 'group' เพิ่ม — ค่าเดิมทั้งหมดยังใช้ได้เหมือนเดิม)
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf)
-- =============================================================

-- =============================================================
-- A) ให้ documents.owner_type รับค่า 'group'
-- =============================================================
alter table public.documents drop constraint if exists documents_owner_type_check;
alter table public.documents add constraint documents_owner_type_check
  check (owner_type = any (array['customer'::text, 'employer'::text, 'establishment'::text, 'case'::text, 'group'::text]));

-- =============================================================
-- B) app_get_group_banner — รูปพื้นหลังล่าสุดของกลุ่ม (ถ้ามี)
-- =============================================================
create or replace function public.app_get_group_banner(
  p_user_id  text,
  p_username text,
  p_group_id bigint
)
returns table (
  id          text,
  doc_name    text,
  doc_type    text,
  source      text,
  has_storage boolean,
  created_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_active boolean := false;
begin
  select true into v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select d.id::text, d.doc_name, d.doc_type, d.source, (d.storage_path is not null), d.created_at
  from public.documents d
  where d.owner_type = 'group'
    and d.owner_id = p_group_id
    and d.doc_type = 'share_banner'
  order by d.created_at desc nulls last
  limit 1;
end;
$$;

revoke all on function public.app_get_group_banner(text, text, bigint) from public;
grant execute on function public.app_get_group_banner(text, text, bigint) to anon, authenticated;

-- =============================================================
-- C) ตรวจผล — ควรได้ group_ok = 1, rpc_ok = 1
-- =============================================================
select
  (select count(*) from pg_constraint
    where conrelid = 'public.documents'::regclass
      and conname = 'documents_owner_type_check'
      and pg_get_constraintdef(oid) like '%group%')                       as group_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_get_group_banner')    as rpc_ok;

commit;

-- ##### ตรวจผลรวม #####
select
  (select count(*) from information_schema.tables where table_schema='public'
     and table_name in ('app_alert_settings','employer_share_links','group_share_links'))              as tables_ok,
  (select count(*) from information_schema.columns where table_schema='public' and table_name='customers'
     and column_name in ('worker_category','status_note','work_items'))                                 as cols_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
     and p.proname in ('app_get_alert_settings','app_save_alert_settings','app_get_employer_share_link',
                       'app_create_employer_share_link','app_revoke_employer_share_link','app_get_group_share_link',
                       'app_create_group_share_link','app_revoke_group_share_link','app_get_group_banner'))  as rpc_ok,
  (select count(*) from pg_constraint where conname='documents_owner_ref_check')                         as owner_check,
  (select count(*) from pg_constraint where conname='documents_owner_type_check'
     and pg_get_constraintdef(oid) like '%group%')                                                       as group_owner_ok,
  (has_table_privilege('service_role','public.employer_share_links','UPDATE')
   and has_table_privilege('service_role','public.group_share_links','UPDATE')
   and has_table_privilege('service_role','public.app_alert_settings','SELECT'))                         as grants_ok;
