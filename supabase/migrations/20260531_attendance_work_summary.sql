-- =============================================================
-- ATTENDANCE — Work Summary (สรุปการทำงานตอนออกงาน)
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- เพิ่ม 3 คอลัมน์ใน attendance_logs สำหรับเก็บสรุปงานตอน checkout:
--   work_summary_type       — ประเภทงาน (แจ้งเข้า-แจ้งออก / 90 วัน / MOU / ...)
--   work_summary_detail     — รายละเอียดที่พนักงานกรอก
--   work_summary_created_at  — เวลาที่บันทึกสรุป
--
-- ปลอดภัย: ADD COLUMN IF NOT EXISTS — รันซ้ำได้ ไม่กระทบข้อมูลเดิม
-- log เก่าที่ไม่มีสรุป → ค่าเป็น NULL (LINE card จะแสดง "-")
-- =============================================================

ALTER TABLE public.attendance_logs
  ADD COLUMN IF NOT EXISTS work_summary_type       text;

ALTER TABLE public.attendance_logs
  ADD COLUMN IF NOT EXISTS work_summary_detail     text;

ALTER TABLE public.attendance_logs
  ADD COLUMN IF NOT EXISTS work_summary_created_at timestamptz;

-- หมายเหตุค่าที่ work_summary_type รองรับ (ฝั่ง frontend เป็นผู้ส่ง — ไม่ใช้ CHECK
-- constraint เพื่อความยืดหยุ่น เผื่อเพิ่มประเภทในอนาคต):
--   แจ้งเข้า-แจ้งออก | 90 วัน | MOU | เปลี่ยนนายจ้าง | นัดถ่ายบัตร | อื่นๆ
