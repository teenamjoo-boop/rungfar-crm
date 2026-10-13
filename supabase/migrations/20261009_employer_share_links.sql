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
