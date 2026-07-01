-- =============================================================
-- STAGE 50A-10 — Revoke Direct UPDATE on public.customers (safety lock, phase 2 of 2)
-- เป้าหมาย:
--   * ปิดทาง "แก้ไขลูกค้าแบบ browser-direct" (anon key) บน public.customers
--   * การแก้ไขลูกค้าทั้งหมดตอนนี้ไปผ่าน SECURITY DEFINER RPC แล้ว:
--       - app_save_customer               (แก้ไข/สร้างทีละราย — Stage 50A-1 / 20260716)
--       - app_bulk_update_customers       (bulk group / assign / status — Stage 50A-5 / 20260718)
--       - app_bulk_create_customers       (นำเข้า Excel/CSV — Stage 50A-7 / 20260719)
--       - app_set_customer_photo_fallback (รูปสำรอง base64 — Stage 50A-9 / 20260720)
--     RPC ทุกตัวตรวจตัวตน + server-stamp actor + whitelist คอลัมน์ก่อนเขียนเสมอ
--
-- plain-language:
--   revoke UPDATE = ปิดประตูเก่าที่ browser แก้แถวลูกค้าเองได้ตรง ๆ
--   CRM ยังทำงานได้ เพราะการแก้ไขปกติวิ่งผ่าน RPC หมดแล้ว (path ตรงเหลือเป็น fallback
--   เฉพาะตอน RPC "ยังไม่ติดตั้ง" ซึ่งจะไม่เกิดหลัง apply migration ครบ)
--
--   หลักการ: PostgreSQL อนุญาต UPDATE ก็ต่อเมื่อมี privilege ระดับตาราง →
--   เพิกถอน privilege อย่างเดียวก็บล็อก client UPDATE ได้แน่นอน โดยไม่แตะ policy เดิม
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ UPDATE ตรงไม่ได้อีกต่อไป (customers)
--                           ❌ INSERT ถูกบล็อกไปแล้ว (20260721)
--                           ❌ DELETE ถูกบล็อกไปแล้ว (20260710)
--                           ✅ SELECT ยังทำงานเหมือนเดิม (ไม่แตะ)
--   * service_role (server / Edge Functions / SECURITY DEFINER RPC): ไม่กระทบ
--     (RPC รันด้วยสิทธิ์ owner → update customers ได้ตามปกติ)
--
-- ⚠️ ไม่ revoke SELECT / ไม่ทำ INSERT ซ้ำ (20260721) / ไม่ทำ DELETE ซ้ำ (20260710)
-- ⚠️ ไม่ DROP policy / ไม่ ALTER โครงสร้างตาราง / ไม่ DELETE row / ไม่แตะ storage
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าไม่มีสิทธิ์อยู่แล้ว)
-- =============================================================

do $$
begin
  if to_regclass('public.customers') is not null then
    revoke update on table public.customers from anon;
    revoke update on table public.customers from authenticated;
    raise notice 'safety-lock: revoked UPDATE on public.customers from anon, authenticated (edits now go via app_save_customer / app_bulk_update_customers / app_set_customer_photo_fallback)';
  else
    raise notice 'safety-lock: public.customers not found — skipped';
  end if;
end$$;
