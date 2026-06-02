-- Migration: line_ai_excel_batches — เพิ่ม columns สำหรับ finalize flow
-- ใช้ ADD COLUMN IF NOT EXISTS เพื่อ idempotent

ALTER TABLE line_ai_excel_batches
  ADD COLUMN IF NOT EXISTS finalized_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pdf_path      TEXT,
  ADD COLUMN IF NOT EXISTS pdf_url       TEXT;

-- Index สำหรับ cron query (status=collecting, last_image_at ต่ำ)
CREATE INDEX IF NOT EXISTS idx_line_ai_excel_batches_stale
  ON line_ai_excel_batches (status, last_image_at)
  WHERE status = 'collecting';
