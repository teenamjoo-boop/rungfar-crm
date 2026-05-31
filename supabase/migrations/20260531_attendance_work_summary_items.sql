-- =============================================================
-- ATTENDANCE — Work Summary Items (JSONB array)
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- เพิ่ม field work_summary_items (jsonb) เพื่อรองรับสรุปงานหลายหัวข้อ
-- ปลอดภัย: ADD COLUMN IF NOT EXISTS — รันซ้ำได้
--
-- รูปแบบ:
-- [
--   { "type": "90 วัน",        "detail": "รายงานตัว 5 ราย" },
--   { "type": "MOU",            "detail": "ทำ MOU ลาว 2 เคส" }
-- ]
--
-- Backward compatible:
--   work_summary_type    = 'multi'   (log ใหม่)
--   work_summary_detail  = ข้อความรวม (fallback อ่านง่าย)
--   work_summary_items   = array จริง (อ่าน/แสดงผลหลัก)
-- =============================================================

ALTER TABLE public.attendance_logs
  ADD COLUMN IF NOT EXISTS work_summary_items jsonb;
