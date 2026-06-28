-- =============================================================
-- STAGE 33B-Fix — allow Storage-based documents (file_data nullable)
--
-- ปัญหา: documents.file_data มี NOT NULL constraint
--   → การ insert เอกสารใหม่ผ่าน Storage (file_data = null) ล้มเหลว
--   → error 23502 (not_null_violation)
--
-- แนวทาง: DROP NOT NULL เท่านั้น
--   * ไม่ลบ column
--   * ไม่แก้ไข/ลบค่าเดิมที่มีอยู่
--   * เอกสารเก่า (base64) คงสมบูรณ์ตามเดิม
--   * เอกสารใหม่ (Storage path) เก็บ file_data = null
--
-- ⚠️ Additive only — ไม่ DROP คอลัมน์, ไม่ DROP ตาราง
-- =============================================================

alter table public.documents
  alter column file_data drop not null;
