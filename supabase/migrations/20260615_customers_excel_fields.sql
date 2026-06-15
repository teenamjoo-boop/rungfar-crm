-- =============================================================
-- 20260615_customers_excel_fields
-- เป้าหมาย:
--   เพิ่มคอลัมน์ตาราง customers ให้ตรงกับ Excel งานจริง (Round F1A)
--   ครอบคลุม: วันที่ยื่น, ใบแพทย์, ประกัน, 100, 900, ตัวแทน,
--             นัดหมาย/เวลา/สถานที่, มีเล่ม/ไม่มีเล่ม, ค่าบัตร, คิวว่าง, วันรับเล่ม
--
-- ปลอดภัย (idempotent):
--   * ใช้ ADD COLUMN IF NOT EXISTS — รันซ้ำได้ ไม่กระทบข้อมูลเดิม
--   * ไม่ DROP / DELETE / UPDATE ข้อมูล
--   * ไม่เปลี่ยนคอลัมน์เดิม / ไม่แตะ policy / RLS / function / trigger
--   * ไม่ CREATE TABLE ใหม่
--
-- หมายเหตุชนิดข้อมูล:
--   * fee_100_paid / fee_900_paid / card_fee_paid = boolean (สถานะจ่าย/ยัง ไม่ใช่ยอดเงิน)
--   * booklet_status = text เก็บค่า has=มีเล่ม, none=ไม่มีเล่ม, null=ยังไม่ระบุ (จาก Excel 2 ช่อง)
--   * appt_time = text (Excel กรอกได้อิสระ เช่น 09:00, เช้า, บ่าย, 10:00-11:00)
--   * queue_date = date (ตีความ "คิวว่าง" เป็นวันที่คิวว่าง)
--   * ยังไม่ใส่ CHECK constraint เพื่อให้ migration เรียบง่าย
-- =============================================================

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS submit_date     date,
  ADD COLUMN IF NOT EXISTS medical_cert    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS insurance       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fee_100_paid    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fee_900_paid    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS agent_name      text,
  ADD COLUMN IF NOT EXISTS appt_date       date,
  ADD COLUMN IF NOT EXISTS appt_time       text,
  ADD COLUMN IF NOT EXISTS appt_place      text,
  ADD COLUMN IF NOT EXISTS booklet_status  text,
  ADD COLUMN IF NOT EXISTS card_fee_paid   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS queue_date      date,
  ADD COLUMN IF NOT EXISTS receive_date    date;

COMMENT ON COLUMN public.customers.submit_date    IS 'วันที่ยื่นตาม Excel';
COMMENT ON COLUMN public.customers.medical_cert   IS 'ใบแพทย์ มี/ไม่มี';
COMMENT ON COLUMN public.customers.insurance      IS 'ประกัน มี/ไม่มี';
COMMENT ON COLUMN public.customers.fee_100_paid   IS 'สถานะจ่าย 100';
COMMENT ON COLUMN public.customers.fee_900_paid   IS 'สถานะจ่าย 900';
COMMENT ON COLUMN public.customers.agent_name     IS 'ตัวแทน';
COMMENT ON COLUMN public.customers.appt_date      IS 'วันที่นัดหมาย';
COMMENT ON COLUMN public.customers.appt_time      IS 'เวลานัดหมายแบบข้อความ';
COMMENT ON COLUMN public.customers.appt_place     IS 'สถานที่นัดหมาย';
COMMENT ON COLUMN public.customers.booklet_status IS 'สถานะเล่ม: has=มีเล่ม, none=ไม่มีเล่ม';
COMMENT ON COLUMN public.customers.card_fee_paid  IS 'สถานะจ่ายค่าบัตร';
COMMENT ON COLUMN public.customers.queue_date     IS 'วันที่คิวว่าง';
COMMENT ON COLUMN public.customers.receive_date   IS 'วันรับเล่ม';
