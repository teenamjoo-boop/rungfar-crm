-- =====================================================================
-- ⛔⛔ DO NOT RUN UNTIL FINAL ADMIN LOGIN IS VERIFIED ⛔⛔
-- =====================================================================
-- STAGE 52A-15 — Final Account / Test User Cleanup (MANUAL REVIEW ONLY)
--
--   ⛔ ห้ามรันทั้งไฟล์รวดเดียว — รันทีละส่วน อ่านผลก่อนทุกครั้ง
--   ⛔ ไฟล์นี้อยู่นอก supabase/migrations โดยตั้งใจ — ห้ามย้ายเข้า migrations
--   ⛔ ทุกส่วนที่แก้ข้อมูลเป็น BEGIN; ... ROLLBACK; (dry run) — COMMIT ถูก
--     คอมเมนต์ไว้ ต้องตั้งใจเปิดเองหลังตรวจผลแล้วเท่านั้น
--
--   บริบท: EMP001–EMP005 / RF001 / RF002 คือบัญชี/พนักงานทดสอบ (จนกว่าจะ
--   พิสูจน์ว่าไม่ใช่) — บัญชีตัวจริงใช้ username แบบตัวพิมพ์เล็ก เช่น
--   leejunki / rungfa / fon / namfon (Option A — Staff username = employee_code)
--
--   ลำดับปลอดภัย (ทำใน CRM ก่อนมารันไฟล์นี้):
--     [A] คง admin ที่ใช้งานได้ปัจจุบันไว้ก่อน
--     [B] สร้าง admin ตัวจริง (ถ้าต้องการ) ในหน้า จัดการผู้ใช้
--     [C] ทดสอบ login admin ตัวจริง → ต้องผ่าน
--     [D] สร้างพนักงานตัวจริง (จัดการพนักงาน) employee_code = username ตัวพิมพ์เล็ก
--     [E] สร้าง Staff user จากพนักงานเหล่านั้น (ระบบเติม username ให้อัตโนมัติ)
--     [F] ทดสอบ login Staff ตัวจริง + ดูประวัติตอกบัตร → ต้องผ่าน
--     [G] ค่อยกลับมารันไฟล์นี้: ปิดใช้งานบัญชีทดสอบก่อน (SECTION 1)
--     [H] ปิด/ลบพนักงานทดสอบหลัง Staff ตัวจริงใช้งานได้ (SECTION 2/4)
--     [I] รัน readiness checker ใน CRM ซ้ำ
--     [J] การลบถาวร (SECTION 3/4) เป็นทางเลือกท้ายสุดเท่านั้น
--
--   สิ่งที่ไฟล์นี้ "ไม่แตะ" เด็ดขาด:
--     line_file_inbox (ต้องเก็บ), branches, attendance_settings,
--     customers/documents (ล้างไปแล้ว), audit_logs / security_login_logs,
--     attendance_logs (เว้นแต่ผลข้างเคียง FK — ดูคำเตือน SECTION 4),
--     schema / migrations / RPC / grants / storage
--
--   ข้อเท็จจริงจากโค้ด (ตรวจแล้ว):
--     * ผู้ใช้ is_active=false → login ไม่ได้ (app_verify_login/app_verify_session
--       เช็ค is_active) และ RPC ทุกตัวปฏิเสธ → "ปิดใช้งาน" ปลอดภัยและย้อนกลับได้
--     * พนักงาน status='inactive' → หายจากรายชื่อ active ทุกหน้า (dashboard/ตอกบัตร)
--     * ⚠️ attendance_logs มี FK ON DELETE CASCADE → ลบพนักงานถาวร =
--       ประวัติตอกบัตรของคนนั้นถูกลบตามทันที! → แนะนำ "ปิดใช้งาน" เท่านั้น
-- =====================================================================


-- ============================================================
-- SECTION 0 — PREVIEW (อ่านอย่างเดียว — รันก่อนเสมอ)
-- ============================================================

-- 0.1 ผู้ใช้ทั้งหมด (ดูว่าใครคือ admin/staff, ใคร active)
select id, username, full_name, role, coalesce(is_active, true) as is_active
from public.app_users
order by role, username;

-- 0.2 พนักงานตอกบัตรทั้งหมด
select id, employee_code, full_name, nickname, branch_name, status
from public.attendance_employees
order by status, employee_code;

-- 0.3 จับคู่ Staff ↔ พนักงาน (Option A: username = employee_code)
--     แถวที่ emp_code เป็น null = Staff ที่ "ไม่มี" พนักงานคู่กัน (ตอกบัตรไม่ได้)
select u.username, u.role, coalesce(u.is_active,true) as user_active,
       e.employee_code as emp_code, e.status as emp_status
from public.app_users u
left join public.attendance_employees e
  on lower(e.employee_code) = lower(u.username)
where lower(coalesce(u.role,'')) <> 'admin'
order by u.username;

-- 0.4 พนักงานที่ "ไม่มี" Staff user (มีในตอกบัตรแต่ login ไม่ได้ — ปกติสำหรับพนักงานที่ยังไม่ให้ใช้ CRM)
select e.employee_code, e.full_name, e.status
from public.attendance_employees e
left join public.app_users u on lower(u.username) = lower(e.employee_code)
where u.id is null
order by e.employee_code;

-- 0.5 นับ admin ที่ยังใช้งานได้ — ต้อง ≥ 1 เสมอ ก่อนและหลังทุกขั้นตอน
select count(*) as active_admin_count
from public.app_users
where lower(coalesce(role,'')) = 'admin' and coalesce(is_active, true) = true;

-- 0.6 พนักงานทดสอบมีประวัติตอกบัตรหรือไม่ (ถ้ามี → ห้ามลบถาวร ใช้ปิดใช้งานแทน)
select e.employee_code, e.full_name,
       (select count(*) from public.attendance_logs l where l.employee_id = e.id) as attendance_log_count
from public.attendance_employees e
where e.employee_code in ('EMP001','EMP002','EMP003','EMP004','EMP005','RF001','RF002')
order by e.employee_code;


-- ============================================================
-- SECTION 1 — ปิดใช้งานบัญชีทดสอบ (is_active=false — ย้อนกลับได้)
--   ทำหลัง [C] (admin ตัวจริง login ผ่าน) เท่านั้น
--   หมายเหตุ: ทางที่ง่ายกว่า = หน้า CRM จัดการผู้ใช้ → ปุ่มปิดใช้งานทีละคน
-- ============================================================
-- begin;
--   -- HARD GUARD: error ทันทีถ้ายังไม่แทนที่ <FINAL_ADMIN_USERNAME> ด้วยชื่อจริง
--   do $g$ begin
--     if '<FINAL_ADMIN_USERNAME>' = '<FINAL_ADMIN' || '_USERNAME>' then
--       raise exception 'REPLACE <FINAL_ADMIN_USERNAME> with the real final admin username first';
--     end if;
--   end $g$;
--   update public.app_users set is_active = false
--   where username in ('EMP001','EMP002','EMP003','EMP004','EMP005','RF001','RF002')  -- ← แก้ให้ตรงบัญชีทดสอบจริงจาก 0.1
--     and username <> '<FINAL_ADMIN_USERNAME>'
--     and username not in ('leejunki','rungfa','fon','namfon');  -- ← กันพลาด: username ตัวจริง (แก้ให้ตรง)
--   -- ตรวจ: admin ที่ใช้งานได้ต้องเหลือ ≥ 1 — ถ้า 0 ให้ ROLLBACK ทันที!
--   select count(*) as active_admin_must_be_at_least_1
--   from public.app_users where lower(coalesce(role,''))='admin' and coalesce(is_active,true)=true;
--   select username, role, is_active from public.app_users order by role, username;
-- rollback;  -- ← dry run ค่าเริ่มต้น
-- -- commit;  -- ← เปิดใช้เฉพาะเมื่อ active_admin ≥ 1 และรายชื่อถูกต้อง


-- ============================================================
-- SECTION 2 — ปิดใช้งานพนักงานทดสอบ (status='inactive' — ย้อนกลับได้)
--   ทำหลัง [F] (Staff ตัวจริง login+ตอกบัตรผ่าน) เท่านั้น
--   ปิดแล้ว: หายจากรายชื่อ active/dashboard — ประวัติตอกบัตรเดิมยังอยู่ครบ
-- ============================================================
-- begin;
--   update public.attendance_employees set status = 'inactive'
--   where employee_code in ('EMP001','EMP002','EMP003','EMP004','EMP005','RF001','RF002')  -- ← แก้ให้ตรงจาก 0.2
--     and employee_code not in ('leejunki','rungfa','fon','namfon');  -- ← กันพลาด: รหัสตัวจริง (แก้ให้ตรง)
--   select employee_code, full_name, status from public.attendance_employees order by status, employee_code;
-- rollback;  -- ← dry run ค่าเริ่มต้น
-- -- commit;


-- ============================================================
-- SECTION 3 — OPTIONAL: ลบบัญชีทดสอบถาวร (ทางเลือกท้ายสุด [J])
--   ⚠️ LOCKOUT WARNING: ต้องเหลือ admin ที่ login ได้จริงอย่างน้อย 1 เสมอ
--   ลบเฉพาะแถวที่ "ปิดใช้งานแล้ว" ผ่าน SECTION 1 เท่านั้น
-- ============================================================
-- begin;
--   do $g$ begin
--     if '<FINAL_ADMIN_USERNAME>' = '<FINAL_ADMIN' || '_USERNAME>' then
--       raise exception 'REPLACE <FINAL_ADMIN_USERNAME> with the real final admin username first';
--     end if;
--   end $g$;
--   delete from public.app_users
--   where coalesce(is_active, true) = false
--     and username <> '<FINAL_ADMIN_USERNAME>'
--     and username not in ('leejunki','rungfa','fon','namfon');
--   select count(*) as active_admin_must_be_at_least_1
--   from public.app_users where lower(coalesce(role,''))='admin' and coalesce(is_active,true)=true;
--   select username, role, is_active from public.app_users order by role, username;
-- rollback;  -- ← dry run ค่าเริ่มต้น
-- -- commit;  -- ← เปิดใช้เฉพาะเมื่อ active_admin ≥ 1


-- ============================================================
-- SECTION 4 — OPTIONAL: ลบพนักงานทดสอบถาวร (ทางเลือกท้ายสุด [J])
--   ⚠️⚠️ CASCADE WARNING: attendance_logs มี FK ON DELETE CASCADE →
--   ลบพนักงาน = ประวัติตอกบัตรของคนนั้น "ถูกลบตามทั้งหมดทันที"
--   → รัน 0.6 ก่อน; ถ้า attendance_log_count > 0 และยังอยากเก็บประวัติ
--     ให้ใช้ SECTION 2 (ปิดใช้งาน) แทน — อย่าลบ
-- ============================================================
-- begin;
--   delete from public.attendance_employees
--   where employee_code in ('EMP001','EMP002','EMP003','EMP004','EMP005','RF001','RF002')  -- ← แก้ให้ตรงจาก 0.2/0.6
--     and employee_code not in ('leejunki','rungfa','fon','namfon');  -- ← กันพลาด: รหัสตัวจริง
--   select employee_code, full_name, status from public.attendance_employees order by employee_code;
--   -- ผลข้างเคียง: ดูจำนวน log ที่หายไปเทียบก่อน/หลังด้วย
--   select count(*) as attendance_logs_remaining from public.attendance_logs;
-- rollback;  -- ← dry run ค่าเริ่มต้น
-- -- commit;


-- ============================================================
-- SECTION 5 — POST-CLEANUP VERIFICATION (อ่านอย่างเดียว)
-- ============================================================
select 'active admin (must be >= 1)' as chk,
       count(*)::text as value
from public.app_users
where lower(coalesce(role,''))='admin' and coalesce(is_active,true)=true
union all
select 'active staff users',
       count(*)::text
from public.app_users
where lower(coalesce(role,''))<>'admin' and coalesce(is_active,true)=true
union all
select 'active attendance employees',
       count(*)::text
from public.attendance_employees where status = 'active'
union all
select 'staff without matching employee (should be 0)',
       count(*)::text
from public.app_users u
where lower(coalesce(u.role,''))<>'admin' and coalesce(u.is_active,true)=true
  and not exists (select 1 from public.attendance_employees e
                  where lower(e.employee_code)=lower(u.username) and e.status='active')
union all
select 'line_file_inbox (untouched)',
       count(*)::text
from public.line_file_inbox;
