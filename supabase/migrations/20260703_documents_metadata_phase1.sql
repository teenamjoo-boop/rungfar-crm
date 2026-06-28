-- =============================================================
-- STAGE 40B — documents metadata Phase 1 (additive only)
-- เป้าหมาย:
--   * เพิ่ม optional metadata columns ใน public.documents
--     สำหรับ Document Center filtering และ Phase 2 readiness
--   * เพิ่ม indexes ที่มีประโยชน์สำหรับการ query
--
-- Columns ใหม่:
--   source    text   (nullable) — แหล่งที่มาของเอกสาร e.g. 'line_inbox', 'excel_import', 'manual'
--   doc_expiry date  (nullable) — วันหมดอายุของเอกสาร e.g. สัญญา, ใบอนุญาต
--
-- ⚠️ Additive only — ไม่ DROP, ไม่ ALTER ชนิดข้อมูล, ไม่แตะแถวเดิม
-- ⚠️ ทุกคอลัมน์ใหม่เป็น nullable — ไม่กระทบเอกสารเดิม
-- ⚠️ ไม่ backfill source ในไฟล์นี้
-- ⚠️ ไม่เพิ่ม case_id ในไฟล์นี้
-- ⚠️ ไม่ enforce CHECK constraint ในไฟล์นี้
-- =============================================================

-- 1) เพิ่มคอลัมน์ source (nullable) -------------------------------------------
--    แหล่งที่มาของเอกสาร เพื่อ filtering ใน Document Center
alter table public.documents
  add column if not exists source text;

-- 2) เพิ่มคอลัมน์ doc_expiry (nullable) ----------------------------------------
--    วันหมดอายุของเอกสาร เพื่อแจ้งเตือน / กรองใน Document Center
alter table public.documents
  add column if not exists doc_expiry date;

-- 3) Indexes -------------------------------------------------------------------

-- 3a) created_at desc — ช่วย list เอกสารเรียงตามเวลาล่าสุด
create index if not exists idx_documents_created_at
  on public.documents (created_at desc);

-- 3b) customer_id + created_at desc — ช่วย openDetail/openEdit query
--     (already created in 20260630_customer_doc_storage.sql — no-op if exists)
create index if not exists idx_documents_cust_created
  on public.documents (customer_id, created_at desc);

-- 3c) doc_type — ช่วยกรองตามประเภทเอกสาร
create index if not exists idx_documents_doc_type
  on public.documents (doc_type);

-- 3d) source — ช่วยกรองตามแหล่งที่มา (Phase 2 Document Center filter)
create index if not exists idx_documents_source
  on public.documents (source);

-- 3e) doc_expiry — ช่วยกรองเอกสารหมดอายุ / ใกล้หมดอายุ
create index if not exists idx_documents_doc_expiry
  on public.documents (doc_expiry);

-- 3f) storage_path partial index — ช่วย audit / query Storage documents
--     (already created in 20260630_customer_doc_storage.sql — no-op if exists)
create index if not exists idx_documents_storage_path
  on public.documents (storage_path)
  where storage_path is not null;
