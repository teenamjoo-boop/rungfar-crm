-- =============================================================
-- SEC-ENRICH STAGE A — public.security_login_logs (additive columns only)
-- เป้าหมาย:
--   * เตรียมคอลัมน์สำหรับ "Stage 17 security login enrichment" โดย
--     เพิ่มเฉพาะคอลัมน์ที่ยังไม่มี แบบ nullable เท่านั้น (additive ล้วน):
--       - ip_address     text     เก็บ IP จริง (จะถูกเขียนฝั่ง server ใน Stage B/C)
--       - is_new_device  boolean  อุปกรณ์ใหม่ (จะถูก "คำนวณ" ใน Stage D)
--       - is_suspicious  boolean  น่าสงสัย (จะถูก "คำนวณ" ใน Stage E)
--   * is_suspicious / is_new_device อาจมีอยู่แล้ว (RPC/UI อ้างถึง) — ใช้
--     ADD COLUMN IF NOT EXISTS เพื่อ idempotent: มีแล้วข้าม, ยังไม่มีค่อยเพิ่ม
--
-- คุณสมบัติสำคัญ (ไม่เปลี่ยน runtime behavior):
--   * ทุกคอลัมน์ "nullable" ไม่มี NOT NULL, ไม่มี default ที่กระทบ insert เดิม
--   * INSERT เดิมจาก logLoginActivity (anon REST) ยังทำงานเหมือนเดิมทุกอย่าง
--     (ไม่ส่ง 3 ฟิลด์นี้ → ได้ค่า NULL ตามปกติ)
--   * RPC app_admin_list_security_logs คืน s.* เหมือนเดิม (มี/ไม่มีค่าก็อ่านได้)
--
-- ไม่แตะ (สำคัญ):
--   * โครงสร้างอื่นของตาราง — ไม่ drop / ไม่ rename / ไม่แก้ type เดิม
--   * RLS / policies / grants ของ security_login_logs — คงเดิมทุกอย่าง
--   * login/auth flow (app_verify_login / app_verify_session) — คงเดิม
--   * RPC, Edge Function, frontend (rungfar_crm_17.html), UI/export — คงเดิม
--   * ไม่เพิ่ม index ใน stage นี้ (ตารางเล็ก, query หลักเรียงตาม login_time + LIMIT
--     500; boolean cardinality ต่ำ; ยังไม่มี query ที่ filter ด้วย ip_address)
--     → ดูคำแนะนำ index ในรายงาน Stage A ก่อนตัดสินใจ stage หลัง
--
-- ⚠️ apply migration นี้ได้ทันทีโดยไม่กระทบของเดิม — เป็นการ "เตรียมคอลัมน์"
--    อย่างเดียว ค่าจริงจะถูกเขียน/คำนวณใน Stage B–E ต่อไป
-- =============================================================

alter table public.security_login_logs
  add column if not exists ip_address    text;

alter table public.security_login_logs
  add column if not exists is_new_device boolean;

alter table public.security_login_logs
  add column if not exists is_suspicious boolean;
