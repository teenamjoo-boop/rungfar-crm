-- =============================================================
-- 20260621_add_customer_assignee_code
-- เป้าหมาย:
--   เพิ่มคอลัมน์ assignee_code บนตาราง customers
--   = "ผู้รับผิดชอบ" (responsible staff) หนึ่งคนต่อลูกค้า
--   เก็บค่าเป็น employee_code (ตรงกับ attendance_employees.employee_code
--   และ app_users.username ของ staff) — ยังไม่ผูก FK
--
-- ปลอดภัย (idempotent):
--   * ADD COLUMN IF NOT EXISTS — รันซ้ำได้ ไม่กระทบข้อมูลเดิม
--   * CREATE INDEX IF NOT EXISTS — กันชนกรณีมี index อยู่แล้ว
--   * ไม่ DROP / DELETE / UPDATE ข้อมูล
--   * ไม่แตะ group_id, staff_receiver, staff_document, staff_closer,
--     updated_by_code, policy / RLS / function / trigger
--   * ไม่ CREATE TABLE ใหม่ / ไม่เพิ่ม foreign key
--
-- หมายเหตุ:
--   * แยกแนวคิดจาก group_id (กลุ่มงาน) โดยสิ้นเชิง
--   * null = ยังไม่ระบุผู้รับผิดชอบ
-- =============================================================

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS assignee_code text;

CREATE INDEX IF NOT EXISTS idx_customers_assignee_code
  ON public.customers(assignee_code);

COMMENT ON COLUMN public.customers.assignee_code
  IS 'ผู้รับผิดชอบลูกค้า = employee_code (ตรงกับ attendance_employees.employee_code / app_users.username); null=ยังไม่ระบุ';
