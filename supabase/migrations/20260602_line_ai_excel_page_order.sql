-- =============================================================
-- LINE AI Excel Helper — เพิ่ม page_no สำหรับลำดับหน้า PDF ที่แน่นอน
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- page_no = ลำดับหน้า (1-based) ที่ตรงกันใน รายการ / หมุน / สลับ / ย้าย / PDF / OCR
-- nullable เพราะ record เก่าไม่มีค่า → query ใช้ nullslast fallback ด้วย created_at
-- rotation_deg ถ้ายังไม่มีให้เพิ่มด้วย (migration นี้ safe รันซ้ำได้)
-- =============================================================

ALTER TABLE public.line_ai_excel_files
  ADD COLUMN IF NOT EXISTS page_no int;

ALTER TABLE public.line_ai_excel_files
  ADD COLUMN IF NOT EXISTS rotation_deg int not null default 0;

-- index เพื่อ query หน้าเจาะจง: page_no=eq.N
CREATE INDEX IF NOT EXISTS idx_line_ai_excel_files_batch_pageno
  ON public.line_ai_excel_files (batch_id, page_no);
