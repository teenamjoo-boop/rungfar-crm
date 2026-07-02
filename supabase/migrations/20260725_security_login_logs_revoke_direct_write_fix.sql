-- =============================================================
-- STAGE 52A-4 — Revoke Direct UPDATE/DELETE on public.security_login_logs (safety-lock fix)
-- เป้าหมาย:
--   * ปิดช่องที่เหลือจาก 20260712: ตอนนั้น revoke เฉพาะ INSERT →
--     UPDATE / DELETE ระดับตารางยังเปิดค้างให้ anon / authenticated อยู่
--     (readiness checker Stage 52A-3 ตรวจพบ: anon:DELETE, anon:UPDATE,
--      authenticated:DELETE, authenticated:UPDATE)
--   * ทางเข้าออกของ log ต้องเป็นฝั่ง server เท่านั้น:
--       - เขียน  → app_log_login_event        (SECURITY DEFINER — 20260712/20260713)
--       - อ่าน   → app_admin_list_security_logs (SECURITY DEFINER, ตรวจรหัส admin — 20260621)
--     ตารางประวัติ login เป็น append-only โดยธรรมชาติ — ไม่มี flow ใดในแอป
--     ที่ต้องแก้/ลบแถว log จาก browser
--
-- plain-language:
--   security_login_logs = ตารางประวัติการ login
--   revoke UPDATE/DELETE = ปิดสิทธิ์เก่าที่เปิดค้าง ไม่ให้ browser (public key)
--   แก้หรือลบประวัติ login ได้ตรง ๆ — กันการลบร่องรอย (log tampering)
--
--   ทำไมไม่แตะ SELECT:
--   * 20260712 ตัดสินใจไว้แล้วว่าไม่ revoke SELECT (การอ่านถูกกันด้วย RLS +
--     frontend อ่านผ่าน admin RPC เท่านั้น — ดูคอมเมนต์ 20260621 บรรทัด 5-6)
--   * readiness checker ตรวจเฉพาะ INSERT/UPDATE/DELETE — ไม่คาดหวังให้ปิด SELECT
--   * คงขอบเขต stage นี้ให้เล็กที่สุด ไม่เสี่ยงกระทบพฤติกรรมเดิม
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ INSERT (ย้ำซ้ำจาก 20260712 — idempotent)
--                           ❌ UPDATE / DELETE ตรงไม่ได้อีกต่อไป (ใหม่ใน stage นี้)
--                           SELECT — ไม่แตะ (RLS ปิดการอ่านตรงอยู่แล้ว)
--   * login ปกติ: ไม่กระทบ — app_log_login_event เป็น SECURITY DEFINER
--     (รันด้วยสิทธิ์ owner จึงเขียน log ได้เหมือนเดิม)
--   * หน้า security log ของ admin: ไม่กระทบ — อ่านผ่าน DEFINER RPC
--
-- ไม่แตะ:
--   * RLS policy / โครงสร้างตาราง / ข้อมูล log (ไม่ DELETE/TRUNCATE แถวใด ๆ)
--   * customers, documents, import, LINE, attendance, Meta Ads, Edge Functions
--   * IP: ไม่ export / ไม่เพิ่ม IP location
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าสิทธิ์ถูกถอนไปแล้ว)
-- =============================================================

do $$
begin
  if to_regclass('public.security_login_logs') is not null then
    -- เขียน log ต้องผ่าน app_log_login_event เท่านั้น (SECURITY DEFINER)
    revoke insert on table public.security_login_logs from anon, authenticated;
    -- log เป็น append-only: browser ห้ามแก้/ลบประวัติ login โดยเด็ดขาด
    -- (อ่านสำหรับ admin ผ่าน app_admin_list_security_logs เท่านั้น)
    revoke update on table public.security_login_logs from anon, authenticated;
    revoke delete on table public.security_login_logs from anon, authenticated;
    raise notice 'safety-lock: revoked INSERT, UPDATE, DELETE on public.security_login_logs from anon, authenticated (writes via app_log_login_event; admin reads via app_admin_list_security_logs)';
  else
    raise notice 'safety-lock: public.security_login_logs not found — skipped';
  end if;
end$$;
