-- Migration: line_ai_excel_files — auto-rotate (OCR/AI) cache + manual lock
--
-- auto_rotation_deg/confidence/checked_at : cache ผล OCR orientation ต่อไฟล์ (ประหยัดค่า OCR)
-- rotation_locked : true เมื่อ user สั่ง "หมุน N ..." → manual ชนะเสมอ ห้าม OCR override
--
-- effective rotation ตอนสร้าง PDF:
--   rotation_locked = true  → ใช้ rotation_deg (manual)
--   rotation_locked = false → ใช้ auto_rotation_deg ?? 0

ALTER TABLE line_ai_excel_files
  ADD COLUMN IF NOT EXISTS auto_rotation_deg        INT,
  ADD COLUMN IF NOT EXISTS auto_rotation_confidence NUMERIC,
  ADD COLUMN IF NOT EXISTS auto_rotation_checked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rotation_locked          BOOLEAN NOT NULL DEFAULT false;
