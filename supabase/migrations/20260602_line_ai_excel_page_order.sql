-- =============================================================
-- LINE AI Excel Helper — เพิ่ม page_no สำหรับลำดับหน้า PDF ที่แน่นอน
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- page_no = ลำดับหน้า (1-based) ที่ตรงกันใน รายการ / หมุน / สลับ / ย้าย / PDF / OCR
-- record เก่าจะถูก backfill ให้มี page_no ตามลำดับ created_at, id เดิม
-- rotation_deg ถ้ายังไม่มีให้เพิ่มด้วย (migration นี้ safe รันซ้ำได้)
-- =============================================================

ALTER TABLE public.line_ai_excel_files
  ADD COLUMN IF NOT EXISTS page_no int;

ALTER TABLE public.line_ai_excel_files
  ADD COLUMN IF NOT EXISTS rotation_deg int not null default 0;

-- backfill record เก่าให้มีลำดับหน้า 1..N ต่อ batch ตามลำดับเดิม
WITH numbered AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY batch_id
      ORDER BY created_at ASC, id ASC
    )::int AS rn
  FROM public.line_ai_excel_files
  WHERE page_no IS NULL
)
UPDATE public.line_ai_excel_files f
SET page_no = numbered.rn
FROM numbered
WHERE f.id = numbered.id;

-- index สำหรับลำดับเดียวกันทุกคำสั่ง:
-- ORDER BY page_no ASC, created_at ASC, id ASC
CREATE INDEX IF NOT EXISTS idx_line_ai_excel_files_batch_page_order
  ON public.line_ai_excel_files (batch_id, page_no, created_at, id);
