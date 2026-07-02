-- =============================================================
-- STAGE 53A-2 — Device Nickname for Known Devices (display-only)
-- เป้าหมาย:
--   * ให้แอดมินตั้ง "ชื่อเครื่อง" (nickname) ให้ device fingerprint ได้
--     เช่น "คอมออฟฟิศ", "มือถือคุณฝน", "โน้ตบุ๊กบ้าน" — เพื่อให้หน้า
--     "อุปกรณ์ที่เคยเข้า" อ่านง่ายขึ้นเท่านั้น
--   * display-only awareness:
--       ❌ ไม่มีผลต่อ login/session/security decision ใด ๆ
--       ❌ ไม่บล็อก login ด้วย IP/อุปกรณ์/fingerprint
--       ❌ ไม่แตะ app_verify_login / app_verify_session / app_log_login_event
--       ❌ ไม่แตะ/ไม่แก้แถวใด ๆ ใน security_login_logs (left join อ่านอย่างเดียว)
--       ❌ ไม่มี GPS / IP geolocation / LINE alert / trust device
--
--   สิ่งที่ migration นี้ทำ:
--     A) ตารางใหม่เล็ก ๆ public.device_nicknames (fingerprint → nickname)
--        ปิด direct access จาก browser ทั้งหมด — เข้าออกผ่าน RPC DEFINER เท่านั้น
--        (pattern เดียวกับ security_login_logs หลัง 20260725)
--     B) RPC ใหม่ app_admin_set_device_nickname — ตั้ง/แก้/ล้างชื่อเครื่อง
--        (admin-password gate แบบเดียวกับ app_admin_list_security_logs)
--     C) อัปเดต app_admin_list_known_devices ให้คืน nickname + note ด้วย
--        (left join — ตัว query ยังอ่านอย่างเดียวเหมือนเดิม)
--
--   นโยบาย "ล้างชื่อ": ส่ง nickname ว่าง → "ลบแถว" ของ fingerprint นั้นทิ้ง
--     เหตุผล: คอลัมน์ nickname เป็น not null (แถวไม่มีชื่อ = แถวขยะ)
--     การลบแถวทำให้ตารางสะอาด ไม่มี state ครึ่ง ๆ กลาง ๆ และผลลัพธ์ต่อ UI
--     เหมือนกัน (left join ไม่เจอ → ไม่มีชื่อ) — ตารางนี้เป็น label ของแอดมิน
--     ล้วน ๆ ไม่ใช่ log จึงลบได้อย่างปลอดภัย (ไม่กระทบ security_login_logs)
--
-- ไม่แตะ:
--   * security_login_logs (โครงสร้าง/ข้อมูล/สิทธิ์) — อ่านผ่าน join เท่านั้น
--   * login/auth RPC เดิมทุกตัว, RLS/grant ของตารางเดิมอื่น ๆ
--   * customer/document/delete_requests, storage, Edge Functions, LINE, Attendance, Meta Ads
-- ⚠️ Idempotent — create table if not exists / drop+create function / revoke+grant รันซ้ำได้
-- =============================================================

-- =============================================================
-- A) ตาราง device_nicknames — label ของแอดมินเท่านั้น (ไม่ใช่ log)
-- =============================================================
create table if not exists public.device_nicknames (
  id                 bigserial primary key,
  device_fingerprint text not null unique,
  nickname           text not null,
  note               text,
  created_by         text,
  updated_by         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ปิด direct access จาก browser ทั้งหมด — เข้าออกผ่าน RPC SECURITY DEFINER เท่านั้น
alter table public.device_nicknames enable row level security;
revoke all on table public.device_nicknames from anon, authenticated;
revoke all on sequence public.device_nicknames_id_seq from anon, authenticated;

-- =============================================================
-- B) app_admin_set_device_nickname — ตั้ง/แก้/ล้างชื่อเครื่อง (admin เท่านั้น)
-- =============================================================
create or replace function public.app_admin_set_device_nickname(
  p_admin_username     text,
  p_admin_password     text,
  p_device_fingerprint text,
  p_nickname           text,
  p_note               text default null
)
returns table (
  ok                 boolean,
  status             text,
  device_fingerprint text,
  nickname           text,
  note               text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    integer := 0;
  v_admin boolean := false;
  v_fp    text := nullif(left(btrim(coalesce(p_device_fingerprint, '')), 80), '');
  v_nick  text := nullif(left(btrim(coalesce(p_nickname, '')), 60), '');   -- จำกัด 60 ตัวอักษร
  v_note  text := nullif(left(btrim(coalesce(p_note, '')), 200), '');      -- จำกัด 200 ตัวอักษร
begin
  -- 1) ตรวจรหัสผ่านด้วย RPC login เดิม (pattern เดียวกับ app_admin_list_security_logs)
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);

  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 2) ยืนยันว่าเป็น admin จริง
  select (lower(coalesce(u.role, '')) = 'admin')
    into v_admin
  from public.app_users u
  where u.username = p_admin_username
  limit 1;

  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) fingerprint ว่าง → ตั้งชื่อไม่ได้ (แถว log ที่ไม่มี fingerprint ไม่ถูกสรุปอยู่แล้ว)
  if v_fp is null then
    return query select false, 'invalid_fingerprint'::text, null::text, null::text, null::text;
    return;
  end if;

  -- 4) nickname ว่าง → ล้างชื่อ = ลบแถว (ดูเหตุผลใน header)
  if v_nick is null then
    delete from public.device_nicknames d where d.device_fingerprint = v_fp;
    return query select true, 'cleared'::text, v_fp, null::text, null::text;
    return;
  end if;

  -- 5) upsert — ตั้งชื่อใหม่หรือแก้ชื่อเดิม (server stamp ผู้แก้ + เวลา)
  --    ⚠️ STAGE 53A-2B fix: ห้ามใช้ on conflict (device_fingerprint) ในฟังก์ชันนี้
  --    เพราะชื่อคอลัมน์ conflict target ชนกับ output column "device_fingerprint"
  --    ของ returns table → PL/pgSQL แจ้ง "column reference is ambiguous" ตอนรัน
  --    → ใช้ update-ก่อน-แล้วค่อย-insert แทน (ทุก reference qualified ชัดเจน)
  update public.device_nicknames d
     set nickname   = v_nick,
         note       = v_note,
         updated_by = p_admin_username,
         updated_at = now()
   where d.device_fingerprint = v_fp;

  if not found then
    insert into public.device_nicknames
      (device_fingerprint, nickname, note, created_by, updated_by)
    values
      (v_fp, v_nick, v_note, p_admin_username, p_admin_username);
  end if;

  return query select true, 'saved'::text, v_fp, v_nick, v_note;
end;
$$;

revoke all on function public.app_admin_set_device_nickname(text, text, text, text, text) from public;
grant execute on function public.app_admin_set_device_nickname(text, text, text, text, text) to anon, authenticated;

-- =============================================================
-- C) app_admin_list_known_devices — เพิ่ม nickname/note (left join, อ่านอย่างเดียว)
--    return columns เปลี่ยน (เพิ่ม 2 คอลัมน์) → ต้อง drop ก่อน create
--    (drop เฉพาะ function — ไม่กระทบตาราง/ข้อมูลใด ๆ; pattern เดียวกับ 20260712)
-- =============================================================
drop function if exists public.app_admin_list_known_devices(text, text, text);

create function public.app_admin_list_known_devices(
  p_admin_username text,
  p_admin_password text,
  p_username       text default null
)
returns table (
  username           text,
  full_name          text,
  role               text,
  device_fingerprint text,
  device_type        text,
  browser_name       text,
  first_seen         timestamptz,
  last_seen          timestamptz,
  login_count        bigint,
  success_count      bigint,
  failed_count       bigint,
  logout_count       bigint,
  last_ip_address    text,
  is_new_device_seen boolean,
  suspicious_count   bigint,
  nickname           text,
  note               text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    integer := 0;
  v_admin boolean := false;
begin
  -- 1) ตรวจรหัสผ่านด้วย RPC login เดิม (password scheme เดียวกัน — ไม่ทำซ้ำ/ไม่เดา)
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);

  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 2) ยืนยันว่า user นี้เป็น admin จริง (DEFINER อ่าน app_users ได้แม้ RLS ปิด)
  select (lower(coalesce(u.role, '')) = 'admin')
    into v_admin
  from public.app_users u
  where u.username = p_admin_username
  limit 1;

  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) สรุปอุปกรณ์ต่อ user (อ่านอย่างเดียว) — เหมือน 20260729 ทุกอย่าง
  --    + left join device_nicknames เพื่อคืนชื่อเครื่อง (ไม่มีชื่อ → null)
  return query
  select
    g.username, g.full_name, g.role, g.device_fingerprint, g.device_type,
    g.browser_name, g.first_seen, g.last_seen, g.login_count, g.success_count,
    g.failed_count, g.logout_count, g.last_ip_address, g.is_new_device_seen,
    g.suspicious_count,
    n.nickname, n.note
  from (
    select
      s.username,
      (array_agg(s.full_name    order by s.login_time desc) filter (where s.full_name    is not null))[1] as full_name,
      (array_agg(s.role         order by s.login_time desc) filter (where s.role         is not null))[1] as role,
      s.device_fingerprint,
      (array_agg(s.device_type  order by s.login_time desc) filter (where s.device_type  is not null))[1] as device_type,
      (array_agg(s.browser_name order by s.login_time desc) filter (where s.browser_name is not null))[1] as browser_name,
      min(s.login_time) as first_seen,
      max(s.login_time) as last_seen,
      count(*) as login_count,
      count(*) filter (where s.login_status = 'success') as success_count,
      count(*) filter (where s.login_status = 'failed')  as failed_count,
      count(*) filter (where s.login_status = 'logout')  as logout_count,
      (array_agg(s.ip_address   order by s.login_time desc) filter (where s.ip_address   is not null))[1] as last_ip_address,
      bool_or(coalesce(s.is_new_device, false)) as is_new_device_seen,
      count(*) filter (where s.is_suspicious = true) as suspicious_count
    from public.security_login_logs s
    where s.username is not null
      and nullif(btrim(coalesce(s.device_fingerprint, '')), '') is not null
      and (
        p_username is null or p_username = ''
        or s.username  ilike '%' || p_username || '%'
        or s.full_name ilike '%' || p_username || '%'
      )
    group by s.username, s.device_fingerprint
    order by max(s.login_time) desc
    limit 300
  ) g
  left join public.device_nicknames n on n.device_fingerprint = g.device_fingerprint
  order by g.last_seen desc;
end;
$$;

revoke all on function public.app_admin_list_known_devices(text, text, text) from public;
grant execute on function public.app_admin_list_known_devices(text, text, text) to anon, authenticated;
