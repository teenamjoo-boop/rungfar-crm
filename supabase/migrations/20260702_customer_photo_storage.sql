-- =============================================================
-- STAGE 36A — customer-photos Storage bucket + additive columns
-- เป้าหมาย:
--   * รองรับการเก็บ "รูปโปรไฟล์ลูกค้า" ใน Supabase Storage (dual-mode)
--   * เพิ่มคอลัมน์ใหม่ใน public.customers เพื่อรองรับ Storage path
--   * ❌ ไม่ลบ / ไม่แตะ customers.photo เดิม (additive only)
--   * รูป base64 เดิมใน customers.photo ยังคงแสดงได้ตามปกติ (fallback)
--
-- dual-mode (อ่านรูปลูกค้า):
--   photo_storage_path IS NOT NULL → เปิดจาก Storage (ผ่าน Edge Function customer-photo-sign)
--   photo_storage_path IS NULL     → fallback ไป customers.photo (base64 เดิม)
--
-- ⚠️ Additive only — ไม่ ALTER ชนิดข้อมูลเดิม, ไม่ DROP คอลัมน์, ไม่ DROP ตาราง
-- ⚠️ ทุกคอลัมน์ใหม่เป็น nullable — ลูกค้าเดิมไม่ต้องเปลี่ยนแปลง
-- ⚠️ ไม่ migrate / ไม่ลบรูป base64 เดิมใน stage นี้
-- =============================================================

-- 1) Storage bucket: customer-photos (PRIVATE) -------------------------------
--    ถ้า environment นี้ไม่อนุญาต insert storage.buckets ให้สร้างใน Dashboard:
--      Storage → New bucket → name: customer-photos → Public = OFF (private)
insert into storage.buckets (id, name, public)
values ('customer-photos', 'customer-photos', false)
on conflict (id) do nothing;

-- 2) เพิ่มคอลัมน์ใหม่ใน public.customers (additive) -------------------------
alter table public.customers
  add column if not exists photo_storage_bucket text,    -- ชื่อ bucket ('customer-photos')
  add column if not exists photo_storage_path   text,    -- relative path ใน bucket
  add column if not exists photo_file_size      bigint,  -- ขนาดไฟล์จริง (bytes) ไม่รวม base64 overhead
  add column if not exists photo_mime_type      text;    -- MIME type ('image/jpeg' | 'image/png')

-- 3) Index --------------------------------------------------------------------
-- ช่วยค้นหา / audit ลูกค้าที่รูปย้ายไป Storage แล้ว (partial — เฉพาะที่มี path)
create index if not exists idx_customers_photo_storage_path
  on public.customers (photo_storage_path)
  where photo_storage_path is not null;
