-- =============================================================
-- STAGE 33A — customer-documents Storage bucket + additive columns
-- เป้าหมาย:
--   * รองรับการเก็บเอกสารลูกค้าใน Supabase Storage (dual-mode)
--   * เพิ่มคอลัมน์ใหม่ใน public.documents เพื่อรองรับ Storage path
--   * ไม่ลบ/ไม่แตะ file_data เดิม (additive only)
--   * Legacy documents ที่ใช้ file_data ยังคงทำงานได้ตามปกติ
--
-- dual-mode:
--   storage_path IS NOT NULL → เปิดจาก Storage (ผ่าน Edge Function customer-doc-sign)
--   storage_path IS NULL     → fallback ไป file_data (base64 เดิม)
--
-- ⚠️ Additive only — ไม่ ALTER ชนิดข้อมูล, ไม่ DROP คอลัมน์, ไม่ DROP ตาราง
-- ⚠️ ทุกคอลัมน์ใหม่เป็น nullable — document เดิมไม่ต้องเปลี่ยนแปลง
-- =============================================================

-- 1) Storage bucket: customer-documents (PRIVATE) ----------------------------
--    ถ้า environment นี้ไม่อนุญาต insert storage.buckets ให้สร้างใน Dashboard:
--      Storage → New bucket → name: customer-documents → Public = OFF (private)
insert into storage.buckets (id, name, public)
values ('customer-documents', 'customer-documents', false)
on conflict (id) do nothing;

-- 2) เพิ่มคอลัมน์ใหม่ใน public.documents (additive) -------------------------
alter table public.documents
  add column if not exists storage_bucket  text,    -- ชื่อ bucket ('customer-documents')
  add column if not exists storage_path    text,    -- relative path ใน bucket
  add column if not exists file_size       bigint,  -- ขนาดไฟล์จริง (bytes) ไม่รวม base64 overhead
  add column if not exists mime_type       text,    -- MIME type (อาจซ้ำกับ file_type — ไม่ conflict)
  add column if not exists thumbnail_path  text;    -- path ของ thumbnail ใน Storage (อนาคต)

-- 3) Indexes ------------------------------------------------------------------
-- ช่วย openDetail/openEdit query ที่กรองด้วย customer_id + เรียง created_at
create index if not exists idx_documents_cust_created
  on public.documents (customer_id, created_at desc);

-- ช่วยค้นหา / audit documents ที่ migrate ไป Storage แล้ว
create index if not exists idx_documents_storage_path
  on public.documents (storage_path)
  where storage_path is not null;
