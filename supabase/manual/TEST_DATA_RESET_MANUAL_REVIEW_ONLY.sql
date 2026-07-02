-- =====================================================================
-- DANGER: TEST-DATA RESET ONLY. DO NOT RUN IF REAL DATA EXISTS.
-- ⛔⛔ DO NOT RUN COMMIT UNTIL FINAL ADMIN LOGIN IS VERIFIED ⛔⛔
--     (ห้ามเปลี่ยน ROLLBACK เป็น COMMIT จนกว่าจะสร้างบัญชี admin ตัวจริง
--      และ "ทดสอบ login สำเร็จแล้ว" — ดูเช็กลิสต์ [A]–[G] ใน SECTION 8)
-- =====================================================================
-- STAGE 52A-12 — Controlled Test Data Reset (MANUAL REVIEW REQUIRED)
--
--   ⛔ ห้ามรันทั้งไฟล์รวดเดียวโดยไม่อ่าน — รันทีละส่วน (Section) เท่านั้น
--   ⛔ DO NOT RUN BLINDLY — this file deletes OPERATIONAL TEST DATA.
--   ⛔ ไฟล์นี้อยู่นอก supabase/migrations โดยตั้งใจ — ห้ามย้ายเข้า migrations
--
--   บริบท: เจ้าของระบบยืนยันว่าข้อมูลปัจจุบันเป็น "ข้อมูลทดลอง" ทั้งหมด
--   (ยังไม่มีข้อมูลลูกค้าจริง) — ต้องการล้างเพื่อเริ่มเทส Phase 1 ฐานสะอาด
--
--   วิธีใช้ (ใน Supabase SQL Editor — รันด้วย role postgres ซึ่ง bypass
--   safety-lock revoke ได้ ตามที่ตั้งใจให้เฉพาะเจ้าของโปรเจกต์ทำ):
--     1) Export/backup ก่อนเสมอ (CSV/Excel จาก CRM + Supabase backup)
--     2) รัน SECTION 0 (นับแถว preview) — อ่านตัวเลขให้ครบก่อนตัดสินใจ
--     3) รัน SECTION 1 โดย "คงไว้เป็น ROLLBACK" ก่อน 1 รอบ (dry run)
--        → ดูตัวเลข verification ท้าย transaction ว่าถูกต้อง
--     4) พอมั่นใจแล้ว แก้ ROLLBACK; เป็น COMMIT; แล้วรันจริง
--     5) SECTION 2–6 เป็น "ตัวเลือก" — ปิดคอมเมนต์เฉพาะที่ต้องการเท่านั้น
--     6) SECTION 8 (บัญชีผู้ใช้/พนักงาน — OPTION A) ทำ "ท้ายสุดเสมอ"
--        หลัง login บัญชีตัวจริงผ่านแล้วเท่านั้น — มี LOCKOUT WARNING
--
--   ❗ ไม่ลบโดยอัตโนมัติ: app_users (บัญชีผู้ใช้), branches (สาขา),
--     attendance_settings (ตั้งค่าตอกบัตร), schema / RPC / migrations /
--     RLS / grants — ไฟล์นี้ไม่มี DDL ใด ๆ
--
--   ★ OPTION A — กลยุทธ์บัญชีผู้ใช้ (ยืนยันโดยเจ้าของระบบ):
--     * คงกติกาเดิม: username ของ Staff ต้องตรงกับ
--       attendance_employees.employee_code (ระบบเทียบเป็นข้อความธรรมดา)
--     * employee_code ตัวจริง "ไม่ต้อง" เป็นแบบ EMP001 — ใช้ชื่อ login ง่าย ๆ
--       ได้เลย เช่น leejunki / rungfa / fon / namfon (ตรวจโค้ดแล้ว: รับได้)
--     * ลำดับที่ปลอดภัย: สร้างพนักงานตัวจริง (employee_code = username ที่เลือก)
--       → สร้าง Staff user จากพนักงานนั้น → ทดสอบ login สำเร็จ →
--       "ค่อย" ปิด/ลบบัญชีทดสอบเก่าและพนักงาน EMP/RF เก่า (ดู SECTION 8)
--     * app_users / attendance_employees เป็นข้อมูลทดสอบก็จริง แต่ห้ามล้าง
--       จนกว่าจะมี admin ตัวจริงอย่างน้อย 1 บัญชีที่ "ทดสอบ login ผ่านแล้ว"
--       — ไม่งั้นล็อกตัวเองออกจากระบบถาวร (LOCKOUT)
--   ❗ ไม่ใช้ TRUNCATE ... CASCADE — ใช้ DELETE เรียงลำดับ ลูก → แม่
--     (ปลอดภัยไม่ว่าจะมี foreign key จริงหรือไม่ และอยู่ใน transaction ได้)
--   ❗ Storage หมายเหตุ: การลบแถว documents ไม่ได้ลบ "ไฟล์จริง" ในบักเก็ต
--     customer-documents / customer-photos — ถ้าต้องการล้างไฟล์ ให้ลบผ่าน
--     Supabase Dashboard → Storage ด้วยมือ (อย่าเขียนสคริปต์ลบ bucket)
-- =====================================================================


-- ============================================================
-- SECTION 0 — PREVIEW COUNTS (อ่านอย่างเดียว — รันก่อนเสมอ)
-- ============================================================
select 'customers'            as tbl, count(*) from public.customers
union all select 'documents',            count(*) from public.documents
union all select 'contact_logs',         count(*) from public.contact_logs
union all select 'work_timeline',        count(*) from public.work_timeline
union all select 'delete_requests',      count(*) from public.delete_requests
union all select 'line_file_inbox',      count(*) from public.line_file_inbox
union all select 'employers',            count(*) from public.employers
union all select 'groups',               count(*) from public.groups
union all select 'audit_logs',           count(*) from public.audit_logs
union all select 'security_login_logs',  count(*) from public.security_login_logs
union all select 'attendance_logs',      count(*) from public.attendance_logs
union all select 'app_users (KEEP until final admin verified — SECTION 8)', count(*) from public.app_users
union all select 'branches (KEEP!)',     count(*) from public.branches
union all select 'attendance_employees (KEEP until final accounts ready — SECTION 8)', count(*) from public.attendance_employees
order by 1;
-- หมายเหตุ: customers count รวมแถวที่ถูก soft delete (deleted_at — Stage 52A-13) ด้วย
-- ดูแยก: select count(*) filter (where deleted_at is null) as visible,
--             count(*) filter (where deleted_at is not null) as soft_deleted
--        from public.customers;

-- 0.1 PREVIEW — นายจ้าง/กลุ่ม พร้อมจำนวนลูกค้าที่ผูกอยู่ (ช่วยตัดสินใจ SECTION 2)
select e.id, e.name,
       (select count(*) from public.customers c where c.employer_id = e.id) as customer_count
from public.employers e
order by customer_count desc, e.name;

select g.id, g.name,
       (select count(*) from public.customers c where c.group_id = g.id) as customer_count
from public.groups g
order by customer_count desc, g.name;


-- ============================================================
-- SECTION 1 — CORE OPERATIONAL RESET (ลูก → แม่)
--   MANUAL REVIEW REQUIRED — dry run ด้วย ROLLBACK ก่อนเสมอ
-- ============================================================
begin;

  -- 1) ตารางลูกที่อ้างถึง customers ก่อน
  delete from public.documents;        -- เอกสารลูกค้า (metadata; ไฟล์จริงใน Storage ไม่ถูกลบ — ดูหมายเหตุหัวไฟล์)
  delete from public.contact_logs;     -- ประวัติการติดต่อ
  delete from public.work_timeline;    -- ไทม์ไลน์สถานะงาน
  delete from public.delete_requests;  -- คำขอลบ (ทดสอบ workflow)

  -- 2) กล่องรับเอกสาร LINE (ข้อมูลทดสอบ intake)
  delete from public.line_file_inbox;

  -- 3) ตารางแม่
  delete from public.customers;

  -- ── VERIFICATION (ต้องเป็น 0 ทุกแถวด้านบน / KEEP ต้อง "ไม่เป็น 0") ──
  select 'customers'           as tbl, count(*) from public.customers
  union all select 'documents',           count(*) from public.documents
  union all select 'contact_logs',        count(*) from public.contact_logs
  union all select 'work_timeline',       count(*) from public.work_timeline
  union all select 'delete_requests',     count(*) from public.delete_requests
  union all select 'line_file_inbox',     count(*) from public.line_file_inbox
  union all select 'app_users (KEEP — must NOT be 0)', count(*) from public.app_users
  order by 1;

rollback;  -- ← DRY RUN ค่าเริ่มต้น: ไม่มีอะไรถูกลบจริง
-- commit;  -- ← เมื่อตรวจ verification แล้วถูกต้อง: คอมเมนต์ rollback; แล้วเปิดใช้ commit; แทน


-- ============================================================
-- SECTION 2 — OPTIONAL: employers / groups
--   ค่าเริ่มต้น = เก็บไว้ (นายจ้าง/กลุ่มจริงอาจถูกใช้ต่อหลังเริ่มงานจริง)
--   เปิดใช้เฉพาะเมื่อยืนยันว่าทั้งหมดเป็นข้อมูลทดลอง
--   ต้องรัน "หลัง" SECTION 1 (customers ถูกลบแล้ว → ไม่มีแถวอ้างถึง)
-- ============================================================
-- begin;
--   delete from public.employers;
--   delete from public.groups;
--   select 'employers' as tbl, count(*) from public.employers
--   union all select 'groups', count(*) from public.groups;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อมั่นใจ


-- ============================================================
-- SECTION 3 — OPTIONAL: audit_logs / security_login_logs
--   ค่าเริ่มต้น = เก็บไว้ (เป็นหลักฐานการใช้งาน/ความปลอดภัย)
--   ลบเฉพาะเมื่อเจ้าของระบบตัดสินใจว่า log ช่วงทดลองไม่ต้องเก็บ
--   ⚠️ ลบแล้วประวัติการทดสอบทั้งหมดหายถาวร — คิดให้ดีก่อน
-- ============================================================
-- begin;
--   delete from public.audit_logs;
--   delete from public.security_login_logs;
--   select 'audit_logs' as tbl, count(*) from public.audit_logs
--   union all select 'security_login_logs', count(*) from public.security_login_logs;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อมั่นใจ


-- ============================================================
-- SECTION 4 — OPTIONAL: attendance_logs (ประวัติตอกบัตรทดสอบ)
--   ค่าเริ่มต้น = เก็บไว้ (ระบบตอกบัตรถูกพักไว้ — Stage 52A-11)
--   ❗ ไม่แตะ attendance_employees / attendance_settings เด็ดขาด
-- ============================================================
-- begin;
--   delete from public.attendance_logs;
--   select count(*) from public.attendance_logs;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อมั่นใจ


-- ============================================================
-- SECTION 5 — OPTIONAL: LINE AI Excel intake cache
--   (line_ai_excel_batches / _files / _results — ข้อมูล staging ของ
--   ตัวช่วยแปลงรูปเป็น Excel; _files/_results มี FK on delete cascade
--   ไปที่ _batches แต่ลบแบบชัดเจน ลูก → แม่ เพื่อความโปร่งใส)
-- ============================================================
-- begin;
--   delete from public.line_ai_excel_results;
--   delete from public.line_ai_excel_files;
--   delete from public.line_ai_excel_batches;
--   select 'batches' as tbl, count(*) from public.line_ai_excel_batches
--   union all select 'files',   count(*) from public.line_ai_excel_files
--   union all select 'results', count(*) from public.line_ai_excel_results;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อมั่นใจ


-- ============================================================
-- SECTION 6 — OPTIONAL: reset id sequences (ให้ลูกค้าคนแรกเริ่มที่ id=1)
--   ไม่จำเป็นต่อการทำงานของระบบ — ทำเพื่อความสวยงามเท่านั้น
--   รันได้เฉพาะ "หลัง commit" SECTION 1 (และ 2 ถ้าใช้) แล้วเท่านั้น
-- ============================================================
-- select setval(pg_get_serial_sequence('public.customers','id'),       1, false);
-- select setval(pg_get_serial_sequence('public.documents','id'),       1, false);
-- select setval(pg_get_serial_sequence('public.contact_logs','id'),    1, false);
-- select setval(pg_get_serial_sequence('public.work_timeline','id'),   1, false);
-- select setval(pg_get_serial_sequence('public.delete_requests','id'), 1, false);
-- select setval(pg_get_serial_sequence('public.line_file_inbox','id'), 1, false);
-- -- employers / groups เฉพาะถ้าใช้ SECTION 2:
-- -- select setval(pg_get_serial_sequence('public.employers','id'), 1, false);
-- -- select setval(pg_get_serial_sequence('public.groups','id'),    1, false);


-- ============================================================
-- SECTION 7 — POST-RESET VERIFICATION (อ่านอย่างเดียว — รันหลัง commit)
-- ============================================================
-- คาดหวัง: แถวบน = 0 (หรือค่าที่ตั้งใจเก็บ), แถว KEEP ต้องมีข้อมูลครบ
select 'customers'            as tbl, count(*) from public.customers
union all select 'documents',            count(*) from public.documents
union all select 'contact_logs',         count(*) from public.contact_logs
union all select 'work_timeline',        count(*) from public.work_timeline
union all select 'delete_requests',      count(*) from public.delete_requests
union all select 'line_file_inbox',      count(*) from public.line_file_inbox
union all select 'employers',            count(*) from public.employers
union all select 'groups',               count(*) from public.groups
union all select 'audit_logs',           count(*) from public.audit_logs
union all select 'security_login_logs',  count(*) from public.security_login_logs
union all select 'app_users (KEEP — must NOT be 0)',            count(*) from public.app_users
union all select 'branches (KEEP)',                             count(*) from public.branches
union all select 'attendance_employees (KEEP)',                 count(*) from public.attendance_employees
order by 1;

-- ระบบยังพร้อมใช้: ฟังก์ชัน/ล็อกสิทธิ์ครบ (ตรวจซ้ำด้วย readiness checker ใน CRM)
select p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('app_verify_login','app_verify_session','app_save_customer',
                    'app_bulk_create_customers','app_save_employer','app_save_group',
                    'app_delete_group','app_admin_phase1_readiness_check')
order by 1;


-- ============================================================
-- SECTION 8 — OPTIONAL: ACCOUNT RESET — OPTION A (ทำท้ายสุดเสมอ)
--   ⚠️⚠️ LOCKOUT WARNING ⚠️⚠️
--   ลบ app_users ผิดจังหวะ = ล็อกตัวเองออกจากระบบถาวร (ไม่มีหน้า reset รหัส)
--   ห้ามเปิดใช้ส่วนนี้จนกว่าจะทำ workflow A–G ครบและ "ทดสอบ login ผ่านแล้ว":
--
--   [A] คงบัญชี admin ปัจจุบันไว้ก่อน (ใช้เป็นทางกลับเข้าระบบระหว่างเปลี่ยนผ่าน)
--   [B] สร้างบัญชี admin ตัวจริง (ถ้าต้องการแยกจากบัญชีทดสอบ) ผ่านหน้า
--       จัดการผู้ใช้ใน CRM — admin ไม่ต้องผูก employee_code
--   [C] ออกจากระบบ → login ด้วย admin ตัวจริง → ต้องเข้าได้จริง
--   [D] สร้างพนักงานตัวจริงในเมนู "จัดการพนักงาน" โดยตั้ง employee_code
--       เป็น username ที่พนักงานจะใช้ login เช่น leejunki / rungfa / fon / namfon
--       (แนะนำตัวพิมพ์เล็กล้วน — การกรอง log ตอกบัตรเทียบ username แบบตรงตัว)
--   [E] สร้าง Staff user จาก dropdown พนักงานในหน้าจัดการผู้ใช้
--       (ระบบเติม username = employee_code ให้อัตโนมัติ)
--   [F] ทดสอบ login ด้วย Staff ตัวจริงอย่างน้อย 1 คน + ลองตอกบัตร/ดูประวัติ
--   [G] เมื่อ [C] และ [F] ผ่านแล้วเท่านั้น → ปิดใช้งาน (แนะนำ) หรือลบ
--       บัญชีทดสอบเก่า และลบพนักงานทดสอบ EMP/RF เก่า
--
--   ทางที่แนะนำกว่า SQL: ใช้หน้า CRM — จัดการผู้ใช้ → ปิดใช้งาน (is_active=false)
--   บัญชีทดสอบทีละคน (ย้อนกลับได้) แทนการ DELETE ถาวร
-- ============================================================

-- 8.0 PREVIEW — ดูบัญชี/พนักงานทั้งหมดก่อนตัดสินใจ (อ่านอย่างเดียว)
-- select id, username, full_name, role, is_active from public.app_users order by role, username;
-- select id, employee_code, full_name, nickname, status from public.attendance_employees order by employee_code;

-- 8.1 OPTIONAL — ปิดใช้งานบัญชีทดสอบ (ย้อนกลับได้ — ดีกว่าลบ)
--   MANUAL REVIEW REQUIRED: แก้รายชื่อ username ทดสอบใน in (...) ให้ตรงของจริงก่อน
--   และห้ามใส่ username ของ admin/staff ตัวจริงเด็ดขาด
-- begin;
--   -- HARD GUARD: จะ error ทันทีถ้ายังไม่ได้แทนที่ <FINAL_ADMIN_USERNAME> ด้วยชื่อจริง
--   do $g$ begin
--     if '<FINAL_ADMIN_USERNAME>' = '<FINAL_ADMIN' || '_USERNAME>' then
--       raise exception 'REPLACE <FINAL_ADMIN_USERNAME> with the real final admin username first';
--     end if;
--   end $g$;
--   update public.app_users set is_active = false
--   where username in ('test1','test2')          -- ← แก้เป็นบัญชีทดสอบจริงเท่านั้น
--     and username <> '<FINAL_ADMIN_USERNAME>';  -- ← กันพลาด: ใส่ชื่อ admin ตัวจริง
--   select username, role, is_active from public.app_users order by role, username;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อตรวจรายชื่อแล้วถูกต้อง

-- 8.2 OPTIONAL — ลบบัญชีทดสอบถาวร (ทำหลัง [C]+[F] ผ่านแล้วเท่านั้น)
--   ⚠️ LOCKOUT WARNING: ต้องเหลือ admin ที่ login ได้จริงอย่างน้อย 1 บัญชีเสมอ
-- begin;
--   -- HARD GUARD: จะ error ทันทีถ้ายังไม่ได้แทนที่ <FINAL_ADMIN_USERNAME> ด้วยชื่อจริง
--   do $g$ begin
--     if '<FINAL_ADMIN_USERNAME>' = '<FINAL_ADMIN' || '_USERNAME>' then
--       raise exception 'REPLACE <FINAL_ADMIN_USERNAME> with the real final admin username first';
--     end if;
--   end $g$;
--   delete from public.app_users
--   where is_active = false                       -- ลบเฉพาะที่ปิดใช้งานแล้ว (ผ่าน 8.1)
--     and username <> '<FINAL_ADMIN_USERNAME>';
--   -- ตรวจว่ายังเหลือ admin ใช้งานได้ ≥ 1 — ถ้าแถวนี้ = 0 ให้ ROLLBACK ทันที!
--   select count(*) as active_admin_must_be_at_least_1
--   from public.app_users where lower(role)='admin' and coalesce(is_active,true)=true;
-- rollback;  -- เปลี่ยนเป็น commit; เฉพาะเมื่อ active_admin ≥ 1

-- 8.3 OPTIONAL — ลบพนักงานตอกบัตรทดสอบเก่า (EMP001/RF... ฯลฯ)
--   ทำหลังสร้างพนักงานตัวจริง [D] และ Staff login ผ่าน [F] แล้วเท่านั้น
--   ❗ ไม่แตะ attendance_settings / branches — ลบเฉพาะแถวพนักงานทดสอบ
-- begin;
--   delete from public.attendance_employees
--   where employee_code in ('EMP001','EMP002','EMP003')  -- ← แก้เป็นรหัสทดสอบจริงเท่านั้น
--     and employee_code not in ('leejunki','rungfa','fon','namfon'); -- ← กันพลาด: รหัสตัวจริง
--   select employee_code, full_name, status from public.attendance_employees order by employee_code;
-- rollback;  -- เปลี่ยนเป็น commit; เมื่อตรวจรายชื่อแล้วถูกต้อง
