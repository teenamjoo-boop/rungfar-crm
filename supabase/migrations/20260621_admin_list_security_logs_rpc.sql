-- =============================================================
-- AUDIT-LOG-READ — app_admin_list_security_logs (SECURITY DEFINER)
-- เป้าหมาย:
--   * ให้หน้า "ประวัติการใช้งาน" (admin เท่านั้น) อ่าน security_login_logs ได้
--     อย่างปลอดภัย โดย "ไม่" เปิด direct SELECT ให้ anon/authenticated
--     (RLS/รеvoke ของตารางยังปิดการอ่านตรงไว้เหมือนเดิม)
--   * ใช้รูปแบบเดียวกับ RPC แอดมินเดิม (app_admin_list/create/update/delete_user):
--     รับ p_admin_username + p_admin_password แล้วตรวจสิทธิ์ก่อนคืนข้อมูล
--   * ตรวจรหัสผ่านโดย "เรียกใช้ app_verify_login เดิม" → ไม่ทำซ้ำ/ไม่เดา
--     password scheme และได้ผลตรงกับ flow login จริง
--
-- ไม่แตะ (สำคัญ):
--   * การ INSERT log — logLoginActivity (anon INSERT policy) คงเดิมทุกอย่าง
--   * login/auth — app_verify_login / app_verify_session คงเดิม
--   * app_admin_*_user เดิม — คงเดิม
--   * โครงสร้างตาราง security_login_logs — อ่านอย่างเดียว (read-only)
--
-- ⚠️ ต้อง apply migration นี้ใน Supabase ก่อน หน้า frontend จึงจะแสดง log จริง
--    ก่อน apply: ปุ่มค้นหาจะขึ้นข้อความ "ยังไม่ได้ติดตั้งฟังก์ชัน — apply migration ก่อน"
-- =============================================================

create or replace function public.app_admin_list_security_logs(
  p_admin_username   text,
  p_admin_password   text,
  p_start_date       date    default null,
  p_end_date         date    default null,
  p_username         text    default null,
  p_status           text    default null,
  p_device           text    default null,
  p_suspicious_only  boolean default false
)
returns setof public.security_login_logs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    integer := 0;
  v_admin boolean := false;
begin
  -- 1) ตรวจรหัสผ่านด้วย RPC login เดิม (password scheme เดียวกัน)
  --    app_verify_login คืน >=1 แถวเมื่อ credential ถูกต้อง, 0 แถวเมื่อผิด
  --    เรียกแบบ named-arg เพื่อกันลำดับพารามิเตอร์ผิด
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);

  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 2) ยืนยันว่า user นี้เป็น admin จริง
  --    (DEFINER อ่าน app_users ได้แม้ RLS ปิด direct access)
  select (lower(coalesce(u.role, '')) = 'admin')
    into v_admin
  from public.app_users u
  where u.username = p_admin_username
  limit 1;

  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) คืน log แบบอ่านอย่างเดียว — filter → เรียงใหม่ก่อน → จำกัด 500 แถว
  return query
  select s.*
  from public.security_login_logs s
  where
    -- ช่วงวันที่ inclusive: ตั้งแต่ 00:00:00 ของ start ถึงสิ้นวัน (23:59:59.x) ของ end
    (p_start_date is null or s.login_time >=  p_start_date::timestamptz)
    and (p_end_date is null or s.login_time <  ((p_end_date + 1))::timestamptz)
    -- username หรือ full_name contains (case-insensitive)
    and (
      p_username is null or p_username = ''
      or s.username  ilike '%' || p_username || '%'
      or s.full_name ilike '%' || p_username || '%'
    )
    -- status เฉพาะค่าที่ valid (success/failed) เท่านั้น
    and (p_status is null or p_status not in ('success', 'failed') or s.login_status = p_status)
    -- device เฉพาะค่าที่ valid (desktop/mobile/tablet) เท่านั้น
    and (p_device is null or p_device not in ('desktop', 'mobile', 'tablet') or s.device_type = p_device)
    -- เฉพาะรายการน่าสงสัย
    and (not coalesce(p_suspicious_only, false) or s.is_suspicious = true)
  order by s.login_time desc
  limit 500;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC แอดมินเดิม)
-- แต่ฟังก์ชันบังคับตรวจ admin credential ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_admin_list_security_logs(text, text, date, date, text, text, text, boolean) from public;
grant execute on function public.app_admin_list_security_logs(text, text, date, date, text, text, text, boolean) to anon, authenticated;
