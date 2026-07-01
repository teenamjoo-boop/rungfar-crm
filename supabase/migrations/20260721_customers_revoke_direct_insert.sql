-- =============================================================
-- STAGE 50A-9 — Revoke Direct INSERT on public.customers (safety lock, phase 1 of 2)
-- เป้าหมาย:
--   * ปิดทาง "สร้างลูกค้าใหม่แบบ browser-direct" (anon key) บน public.customers
--   * การสร้างลูกค้าทั้งหมดตอนนี้ไปผ่าน SECURITY DEFINER RPC แล้ว:
--       - app_save_customer         (เพิ่ม/แก้ไขทีละราย — Stage 50A-1)
--       - app_bulk_create_customers (นำเข้า Excel/CSV หลายราย — Stage 50A-7)
--     RPC ตรวจตัวตน + server-stamp actor + whitelist คอลัมน์ก่อนเขียนเสมอ
--
-- plain-language:
--   revoke INSERT = ปิดประตูเก่าที่ browser สร้างแถวลูกค้าเองได้ตรง ๆ
--   (ยังไม่ revoke UPDATE — path สำรองบางอย่าง เช่น รูป fallback เพิ่งย้ายมาผ่าน RPC
--    20260720; UPDATE จะ revoke ใน stage ถัดไปหลังทดสอบครบ)
--
--   หลักการ: PostgreSQL อนุญาต INSERT ก็ต่อเมื่อมี privilege ระดับตาราง →
--   เพิกถอน privilege อย่างเดียวก็บล็อก client INSERT ได้แน่นอน โดยไม่แตะ policy เดิม
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ INSERT ตรงไม่ได้อีกต่อไป (customers)
--                           ✅ SELECT ยังทำงานเหมือนเดิม
--                           ✅ UPDATE ยังทำงานเหมือนเดิม (ยังไม่ revoke ในสเตจนี้)
--                           ❌ DELETE ถูกบล็อกไปแล้วตั้งแต่ 20260710 (ไม่ทำซ้ำที่นี่)
--   * service_role (server / Edge Functions / SECURITY DEFINER RPC): ไม่กระทบ
--     (RPC รันด้วยสิทธิ์ owner → insert เข้า customers ได้ตามปกติ)
--
-- ⚠️ ไม่ revoke UPDATE / ไม่ revoke SELECT / ไม่ทำ DELETE ซ้ำ (จัดการที่ 20260710 แล้ว)
-- ⚠️ ไม่ DROP policy / ไม่ ALTER โครงสร้างตาราง / ไม่ DELETE row / ไม่แตะ storage
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าไม่มีสิทธิ์อยู่แล้ว)
-- =============================================================

do $$
begin
  if to_regclass('public.customers') is not null then
    revoke insert on table public.customers from anon;
    revoke insert on table public.customers from authenticated;
    raise notice 'safety-lock: revoked INSERT on public.customers from anon, authenticated (creates now go via app_save_customer / app_bulk_create_customers)';
  else
    raise notice 'safety-lock: public.customers not found — skipped';
  end if;
end$$;
