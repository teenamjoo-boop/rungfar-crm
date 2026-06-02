-- =============================================================
-- LINE AI Excel Helper — เพิ่ม rotation_deg ใน line_ai_excel_files
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- rotation_deg = องศา CW ที่ผู้ใช้สั่งหมุน (0/90/180/270)
--   ขวา      = 90
--   ซ้าย     = 270
--   กลับหัว  = 180
--   ตรง/reset = 0
-- ปลอดภัย: ADD COLUMN IF NOT EXISTS — รันซ้ำได้ ไม่กระทบข้อมูลเดิม
-- =============================================================

ALTER TABLE public.line_ai_excel_files
  ADD COLUMN IF NOT EXISTS rotation_deg int not null default 0;
