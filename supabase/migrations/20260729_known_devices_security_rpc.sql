-- =============================================================
-- STAGE 53A-1 — Known Device Summary RPC (read-only awareness)
-- เป้าหมาย:
--   * เพิ่ม RPC ใหม่ 1 ตัว: app_admin_list_known_devices
--     สรุป "อุปกรณ์ที่เคยเข้า" ของแต่ละ user จากข้อมูลเดิมใน
--     public.security_login_logs (จัดกลุ่มตาม username + device_fingerprint)
--   * เป็น Facebook-style awareness สำหรับแอดมินดูเท่านั้น:
--       ✅ อ่านอย่างเดียว (SELECT จาก security_login_logs เท่านั้น)
--       ❌ ไม่บล็อก login ด้วย IP/อุปกรณ์/fingerprint ใด ๆ
--       ❌ ไม่ INSERT/UPDATE/DELETE  ❌ ไม่แก้ตาราง/RLS/grant เดิม
--       ❌ ไม่แตะ app_verify_login / app_verify_session / app_log_login_event
--       ❌ ไม่มี GPS / IP geolocation / LINE alert
--
--   รูปแบบสิทธิ์: เหมือน app_admin_list_security_logs (20260621) ทุกอย่าง —
--     ตรวจรหัสผ่าน admin ผ่าน app_verify_login เดิม + ยืนยัน role='admin'
--     รหัสผิด → raise 'unauthorized' (P0001) แบบเดียวกับ RPC แอดมินเดิม
--     (frontend map ข้อความนี้เป็น "รหัส ADMIN ไม่ถูกต้อง" อยู่แล้ว)
--
--   การจัดกลุ่ม fingerprint ว่าง/null:
--     * "ข้าม" แถวที่ไม่มี device_fingerprint (null/ว่าง) — ไม่จัดกลุ่มเป็น '-'
--       เหตุผล: แถวเก่าก่อนเริ่มเก็บ fingerprint + แถวที่ client ส่งไม่ครบ
--       จะกองรวมเป็นก้อนเดียวที่ไม่มีความหมาย ("อุปกรณ์" ที่ไม่รู้ว่าเครื่องไหน)
--       และอาจทำให้แอดมินเข้าใจผิด — ตัดออกปลอดภัยกว่า (log ดิบยังดูได้
--       ครบทุกแถวในหน้า security log เดิม)
--     * ข้ามแถวที่ไม่มี username ด้วย (เช่น failed แบบไม่รู้ user) — สรุป
--       รายอุปกรณ์ "ต่อ user" ต้องมี user; ยอด failed รวมดูได้จากหน้า log เดิม
--
--   ฟิลด์ที่คืน: เฉพาะที่จำเป็นต่อการแสดงผล — ❗ ไม่คืน user_agent เต็ม
--   (ยาว/ระบุตัวเครื่องเกินจำเป็น; browser_name + device_type พอสำหรับ awareness)
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS/grant ของตารางใด ๆ (DDL มีแค่ create or replace function + grant ของ function นี้)
--   * ข้อมูลทุกแถว (อ่านอย่างเดียว)
--   * customer/document/delete_requests, storage, Edge Functions, LINE, Attendance, Meta Ads
-- ⚠️ Idempotent — create or replace + revoke/grant รันซ้ำได้
-- =============================================================

create or replace function public.app_admin_list_known_devices(
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
  suspicious_count   bigint
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

  -- 3) สรุปอุปกรณ์ต่อ user (อ่านอย่างเดียว) — จัดกลุ่ม username + fingerprint
  --    ค่า "ล่าสุด" (device_type/browser/ip/full_name/role) เอาจากแถวใหม่สุดที่มีค่า
  --    เรียงอุปกรณ์ที่ใช้ล่าสุดขึ้นก่อน จำกัด 300 กลุ่ม (กันตารางบวมใน UI)
  return query
  select
    s.username,
    (array_agg(s.full_name    order by s.login_time desc) filter (where s.full_name    is not null))[1],
    (array_agg(s.role         order by s.login_time desc) filter (where s.role         is not null))[1],
    s.device_fingerprint,
    (array_agg(s.device_type  order by s.login_time desc) filter (where s.device_type  is not null))[1],
    (array_agg(s.browser_name order by s.login_time desc) filter (where s.browser_name is not null))[1],
    min(s.login_time),
    max(s.login_time),
    count(*),
    count(*) filter (where s.login_status = 'success'),
    count(*) filter (where s.login_status = 'failed'),
    count(*) filter (where s.login_status = 'logout'),
    (array_agg(s.ip_address   order by s.login_time desc) filter (where s.ip_address   is not null))[1],
    bool_or(coalesce(s.is_new_device, false)),
    count(*) filter (where s.is_suspicious = true)
  from public.security_login_logs s
  where s.username is not null
    and nullif(btrim(coalesce(s.device_fingerprint, '')), '') is not null
    -- filter username/full_name contains (case-insensitive) — เหมือนหน้า log เดิม
    and (
      p_username is null or p_username = ''
      or s.username  ilike '%' || p_username || '%'
      or s.full_name ilike '%' || p_username || '%'
    )
  group by s.username, s.device_fingerprint
  order by max(s.login_time) desc
  limit 300;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (เหมือน RPC แอดมินเดิม)
-- แต่ฟังก์ชันบังคับตรวจ admin credential ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_admin_list_known_devices(text, text, text) from public;
grant execute on function public.app_admin_list_known_devices(text, text, text) to anon, authenticated;
