-- Migration: line_ai_excel_files — เพิ่ม columns สำหรับ deterministic page order
-- Source of truth สำหรับเรียงหน้า PDF คือ LINE event timestamp + event index ใน payload
-- ไม่ใช้ created_at หรือ page_no ที่ insert ไปก่อนเพราะ async upload/insert race ได้

ALTER TABLE line_ai_excel_files
  ADD COLUMN IF NOT EXISTS line_event_ts    BIGINT,   -- LINE event.timestamp (ms) จาก LINE server
  ADD COLUMN IF NOT EXISTS line_event_index INT;      -- index ใน events[] array ของ webhook payload

-- Index ช่วย ORDER BY ตอน query ต่อ batch
CREATE INDEX IF NOT EXISTS idx_line_ai_excel_files_order
  ON line_ai_excel_files (batch_id, line_event_ts ASC NULLS LAST, line_event_index ASC NULLS LAST, id ASC);
