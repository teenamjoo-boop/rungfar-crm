# RUNGFA CRM — PROJECT MASTER HANDOFF

**ฉบับส่งต่อครบถ้วนสำหรับ Chat/Work → Claude Code/Codex**  
**Version:** 1.0  
**วันที่จัดทำ:** 13 กรกฎาคม 2026  
**สถานะ:** Source of Truth ระดับภาพรวม — ห้ามใช้แทน Git/DB pre-check

> เอกสารนี้จัดทำเพื่อย้ายการควบคุมโครงการจากแชทเดิมที่มีข้อมูลจำนวนมากไปยังแชทใหม่ โดยไม่สูญเสียทิศทาง ประวัติ ข้อห้าม และสถานะล่าสุด

## สารบัญ
- วิธีใช้เอกสารนี้และลำดับความน่าเชื่อถือของข้อมูล
- คำจำกัดความสถานะในเอกสาร
- Executive Snapshot — สถานะโครงการ ณ วันที่ส่งต่อ
- ข้อมูลธุรกิจและเป้าหมายผลิตภัณฑ์
- รูปแบบการทำงานใหม่หลังย้ายแชท
- Project Technical Context
- สถาปัตยกรรมระบบปัจจุบัน
- ระบบที่ทำแล้ว — Phase 1 / Core CRM
- Phase 2 — Product Concept ที่ยืนยันแล้ว
- Stage History — งานที่ทำจริงและหลักฐานสำคัญ
- สถานะ Git / DB ล่าสุด — CONFIRMED CURRENT
- Known Product Gaps / Residues
- สิ่งที่ยังไม่ทำ / ยังไม่ถือว่าเสร็จ
- ข้อห้ามและ Safety Rules
- Roadmap หลักของโครงการ
- วิธีสั่ง Claude Code / Codex ให้ไม่หลุดทิศ
- Prompt เปิดแชทใหม่
- Checklist สำหรับอัปเดต Handoff หลังจบแต่ละ Stage
- แหล่งข้อมูลที่ใช้ประกอบ Handoff ฉบับนี้
- Final Handoff Verdict

## วิธีใช้เอกสารนี้และลำดับความน่าเชื่อถือของข้อมูล

เอกสารนี้คือ Project Master Handoff สำหรับย้ายการควบคุมโครงการ RUNGFA CRM จากแชทเดิมไปยังแชทใหม่ โดยรวมทั้งสถานะระบบจริง งานที่ทำเสร็จ งานที่ยังไม่เสร็จ ข้อห้าม Known Gaps ประวัติ Stage สถานะ Git/DB ล่าสุด Roadmap และวิธีสั่ง Claude Code/Codex ให้ทำงานต่ออย่างไม่หลุดทิศ

เอกสารนี้เป็น “แผนที่ใหญ่ของโครงการ” ไม่ใช่คำสั่งให้แก้โค้ดทันที และไม่แทน Git, Database หรือไฟล์ CURRENT_STATE_LOCK ที่จะจัดทำในขั้นถัดไป

| ลำดับ | แหล่งข้อมูล | ใช้ตัดสินอะไร | กฎ |
| --- | --- | --- | --- |
| 1 | Git + ไฟล์ใน Repo ปัจจุบัน | โค้ดและไฟล์จริงล่าสุด | ต้องเช็กทุกครั้งก่อนเริ่มงาน |
| 2 | Database ของ Environment ที่ระบุ | ข้อมูลจริงและ schema/function ที่ deploy | ห้ามเดาจากรายงานเก่า |
| 3 | CURRENT_STATE_LOCK.md | ค่าล่าสุดที่ตรวจและล็อกไว้ | ถ้าไม่ตรงให้ HARD STOP |
| 4 | PROJECT_MASTER_HANDOFF.md | ภาพรวม ประวัติ ข้อห้าม Roadmap | ใช้ทำความเข้าใจ ไม่ใช้แทนการ pre-check |
| 5 | ประวัติแชท/ภาพหน้าจอเก่า | หลักฐานอ้างอิงย้อนหลัง | ใช้เมื่อเอกสารหลักไม่พอเท่านั้น |

> **หมายเหตุ:** กฎสำคัญ: ห้ามดึงค่า baseline, หมายเลข Stage หรือ commit จากความจำเมื่อสามารถตรวจจาก Repo/DB ได้

## คำจำกัดความสถานะในเอกสาร

| ป้ายสถานะ | ความหมาย |
| --- | --- |
| CONFIRMED CURRENT | ตรวจยืนยันจากรายงานล่าสุดในแชทนี้ หลัง Stage 58K-C cleanup |
| CONFIRMED HISTORICAL | เคยทำ/เคย commit/push จริง แต่ต้องเช็ก regression ก่อนใช้งานจริง |
| PARTIAL / NEEDS VERIFY | มีฐานหรือเคยทดสอบบางส่วน แต่ยังไม่ผ่าน production readiness |
| PLANNED | วิเคราะห์และกำหนดทิศทางแล้ว แต่ยังไม่ถือว่าพัฒนาเสร็จ |
| DEFERRED / FROZEN | พักไว้หรือห้ามแตะระหว่างทำ Stage อื่น |
| UNKNOWN / RE-CHECK | ข้อมูลในแชทไม่พอ ต้องอ่าน Repo/DB ก่อนสรุป |

## Executive Snapshot — สถานะโครงการ ณ วันที่ส่งต่อ

RUNGFA CRM เป็นเว็บแอพภายในบริษัท รุ่งฟ้า รุ่งฟ้า จำกัด สำหรับบริหารข้อมูลลูกค้า แรงงาน นายจ้าง เอกสาร งานตอกบัตร และงานเอกสารแรงงาน โดยกำลังขยายจากระบบ Master Data/Document/Alerts ไปเป็นศูนย์กลางเตรียมเคสก่อนยื่น e-WorkPermit จริง

โครงปัจจุบันใช้ frontend หลักเป็นไฟล์ HTML ขนาดใหญ่และใช้ Supabase เป็น backend/database/storage/RPC โดยมีการแยก Staging กับ Production และมีแนวทาง SECURITY DEFINER, server-side validation, audit และ owner-aware document linking

Stage ล่าสุดที่ปิดครบคือ **F1 Payment-specific Stage** (ปิดบน Staging 14 กรกฎาคม 2026): ทดสอบเส้นทาง payment/proof จริงผ่าน UI เฉพาะของงานการเงิน แล้ว cleanup fixture ครบ ก่อนหน้านั้นคือ Stage 58K-C Runtime Smoke: owner-aware document link/unlink ครบ T1–T13 ตามขอบเขต พร้อม cleanup เอกสารทดสอบ 5 รายการ ทั้งสอง stage ทำบน Staging เท่านั้น Production ไม่ถูกแตะ

| หัวข้อ | สถานะล่าสุด |
| --- | --- |
| Repo | D:\dev\claude / Git Bash: /d/dev/claude |
| Branch | feature-attendance |
| HEAD | อ่านสดจาก Git ทุก session (`git rev-parse HEAD`) — ไม่ตรึงค่าในเอกสาร; last committed checkpoint = 80dcafe; working tree ปัจจุบันมีงาน F2/58L ที่ยังไม่ commit (frontend toggle guard + migration 20260813 + doc update) |
| Working tree | clean ณ snapshot 2c30070; local = origin/feature-attendance (0/0) — re-verify สดก่อนเขียน |
| Frontend หลัก | rungfar_crm_17.html |
| Local Staging HTML | rungfar_crm_17.STAGING.local.html |
| Staging Project Ref | bzwtknqvhvdmatangzqf |
| Production Project Ref | magwqolbjmwymqxelizl — ห้ามแตะจนกว่าจะอนุมัติ |
| Stage ล่าสุด | F2/58L Establishment PARTIAL — Admin runtime acceptance PASS + toggle fix/no-op PASS + cleanup PASS (Staging, ยังไม่ commit); ก่อนหน้า F1 CLOSED |
| สถานะ Rollout | ยังไม่ rollout 12 คน; ต้องจบ core readiness แล้วทดสอบ 2–3 คนก่อน |

## ข้อมูลธุรกิจและเป้าหมายผลิตภัณฑ์

บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด ให้บริการด้านเอกสารแรงงานต่างด้าวครบวงจร งานหลักครอบคลุม Passport, CI, Visa, Work Permit, MOU, เปลี่ยนนายจ้าง, แจ้งเข้า–แจ้งออก, รายงานตัว 90 วัน, แจ้งที่พัก และงานตามมติ ครม. ต่าง ๆ

ระบบต้องถูกออกแบบให้พนักงานใช้ง่ายกว่า Excel ลดการพิมพ์ซ้ำ ลดเอกสารตกหล่น และทำให้ผู้บริหารเห็นงานค้าง งานพร้อมยื่น งานรอตรวจ และงานเสร็จ โดยไม่ทำให้พนักงานรู้สึกว่าต้องเรียนระบบราชการใหม่ทั้งชุด

- เป้าหมาย Phase 1: ทำระบบ CRM core ให้เสถียร ปลอดภัย ใช้งานจริงได้ ทั้ง customer/master data, document, alerts, permissions, audit, import/export, mobile/desktop และ production readiness
- เป้าหมาย Phase 2: ทำ “ศูนย์กลางเตรียมงานก่อนยื่นจริง” สำหรับเคสเอกสารแรงงานตาม e-WorkPermit โดยใช้ฐานข้อมูลกลางร่วมกับ Phase 1
- เป้าหมาย Phase 3: Customer Upload Portal/PWA, OCR, AI Assist, Document Generator และ automation เพิ่มเติม
- ลำดับใช้งานจริง: ทำระบบที่เหลือให้ครบ → ทดสอบกลุ่มเล็ก 2–3 คน → แก้ปัญหา → rollout 12 ผู้ใช้จริง

## รูปแบบการทำงานใหม่หลังย้ายแชท

| บทบาท | หน้าที่หลัก | สิ่งที่ห้ามทำ |
| --- | --- | --- |
| Chat / Work | วิเคราะห์ระบบ, วาง Roadmap, ตรวจรายงาน, ออกแบบ Stage, เขียน prompt คุมงาน, อัปเดตเอกสาร Source of Truth | ไม่เดา code/DB, ไม่สั่งข้าม pre-check, ไม่ประกาศว่าเสร็จจากคำอธิบายลอย ๆ |
| Claude Code หรือ Codex — เลือกผู้ลงมือหลักทีละช่วง | อ่าน Repo, ตรวจ Git, เขียน/แก้ code, migration, test, ทำ Expected vs Actual report | ห้ามแก้พร้อมกันสอง agent บน branch เดียว, ห้าม commit/push/deploy เอง |
| ผู้ใช้ | กด UI ที่มีผลจริง, ตรวจภาพ/ผลลัพธ์, อนุมัติการ mutation, commit, push, deploy | ไม่ควรรัน SQL/คำสั่งที่ไม่รู้ environment หรือ scope |

> **หมายเหตุ:** หลักการ: หนึ่ง Stage ใช้ผู้ลงมือหลักเพียงตัวเดียวจนปิด Stage เพื่อป้องกัน state และความเข้าใจชนกัน

## Project Technical Context

| รายการ | ค่าที่ต้องใช้ |
| --- | --- |
| Path ที่ถูกต้อง | D:\dev\claude หรือ /d/dev/claude |
| Path ที่ห้ามใช้ | C:\Users\Acer\OneDrive\Desktop\claude |
| Repository | teenamjoo-boop/rungfar-crm.git |
| Branch หลักที่ใช้งาน | feature-attendance |
| Frontend หลัก | rungfar_crm_17.html |
| Staging local copy | rungfar_crm_17.STAGING.local.html |
| Staging ref | bzwtknqvhvdmatangzqf |
| Production ref | magwqolbjmwymqxelizl |
| Current live HEAD | อ่านจาก Git pre-flight เท่านั้น — ไม่ frozen ในเอกสาร |
| Last verified snapshot | 2c30070 (2026-07-23) — local = origin, 0/0, tree clean |
| Stage evidence (historical) | e9d035c = F1 runtime-test HEAD; bf40820 = F1 documentation-closeout commit; 54680ec = Stage 58K-C code baseline |

```text
cd /d/dev/claude
git status --short --branch
git diff --check
git log --oneline --decorate -10
```

## สถาปัตยกรรมระบบปัจจุบัน

Frontend ปัจจุบันเป็นเว็บแอพไฟล์หลักขนาดใหญ่ ซึ่งรวม UI หลายโมดูลไว้ในไฟล์เดียว จึงต้องแก้แบบจำกัดขอบเขตและทำ regression test ทุกครั้ง ไม่ควร refactor ครั้งใหญ่ระหว่างแก้ bug หรือ smoke test

Backend ใช้ Supabase Database, RPC/Functions, Storage และ audit patterns โดยข้อมูลไฟล์จริงควรอยู่ Storage ส่วน Database เก็บ metadata, owner, status, expiry, path/reference และ audit เท่านั้น

- Environment แยก Staging และ Production; Staging local HTML ต้องไม่มี Production ref
- RPC สำคัญใช้ SECURITY DEFINER, revoke direct access และ grant execute เฉพาะบทบาทที่กำหนด
- Frontend ส่ง p_user_id/p_username ผ่าน helper เพื่อให้ backend ตรวจ identity, role และ active status
- ไฟล์ต้องเปิดผ่าน signed URL ชั่วคราวและ ownership/permission check; ห้ามส่ง storage_path, file_data, base64 หรือ permanent URL ออกสู่ report/audit
- Audit ของ link/unlink เป็น strict; checklist status update เป็น best-effort ตาม contract ที่ทดสอบแล้ว

### โมเดลข้อมูลหลักที่ยืนยัน/ใช้งานอยู่

| Entity/Table | หน้าที่ | สถานะ/ข้อสังเกต |
| --- | --- | --- |
| app_users | บัญชีผู้ใช้, role, active/inactive, session/security context | มี RLS/session hardening; ต้อง regression ก่อน rollout |
| customers | ข้อมูลลูกค้า/แรงงานหลัก | เป็น master data และฐานของ case worker |
| employers | นายจ้าง/บริษัท | ใช้ร่วมกับเคสและเอกสารนายจ้าง |
| cases | เคสงานเอกสารแรงงาน | มี original case และ disposable test case ใน Staging |
| case_workers | ผูกแรงงานกับเคส, primary/secondary, active/inactive | ใช้ owner-aware worker attribution |
| case_checklist_items | รายการตรวจเอกสารและสถานะ | รองรับ missing/received/reviewing/approved/needs_fix/waived/not_required |
| documents | metadata เอกสารและ owner | owner_type ที่ใช้งาน: customer/case/employer; establishment/payment มีข้อจำกัดเฉพาะ |
| case_documents | ลิงก์เอกสารกับ checklist item | เก็บ linked_owner_type, linked_owner_id, linked_case_worker_id |
| audit_logs | ประวัติการกระทำ | append-only/retention; ห้ามลบระหว่าง cleanup |
| case_payments | ข้อมูล payment/proof | ทดสอบ runtime ครบใน F1 (2026-07-14); proof ผูกผ่าน `case_payments.proof_document_id` ไม่ผ่าน case_documents |
| establishments (ไฟล์ migration ชื่อ employer_establishments) | สถานประกอบการใต้นายจ้าง | **Canonical table `public.establishments` — deployed บน Staging** (ชื่อไฟล์ migration 20260804 ต่างจากชื่อตาราง; `public.employer_establishments` ไม่ใช่ตารางที่ deploy) + RPC `app_save_establishment`/`app_set_establishment_active`/`app_get_employer_detail`/`app_list_employers_phase2` + modal ใน Employer detail. Establishment **Admin runtime acceptance = PASS** (F2/58L PARTIAL) |
| case_appointments | นัดหมายของเคส | Repo foundation: RPC `app_save_case_appointment`/`app_set_case_appointment_status`/`app_case_appointment_summary` + frontend path; ยังไม่พบหลักฐาน runtime acceptance; DB ไม่ตรวจในรอบนี้ |
| case_tracking_logs | ติดตามราชการ/e-WorkPermit (เลขคำขอ/สถานะยื่น) | Repo foundation: RPC `app_add_case_tracking_log`/`app_list_case_tracking_logs` + frontend; ยังไม่พบ runtime acceptance |
| case_status_logs | ประวัติสถานะเคส | Repo foundation: `app_change_case_status` เขียน log; ยังไม่พบ runtime acceptance |
| contact_logs / work_timeline | บันทึกการติดต่อ / ไทม์ไลน์กิจกรรม | Repo foundation: RPC `app_add_contact_log`/`app_add_work_timeline` (migration 20260717); ยังไม่พบ runtime acceptance; ไม่ยืนยันการใช้งานจริง |

## ระบบที่ทำแล้ว — Phase 1 / Core CRM

### ลูกค้าและข้อมูลแรงงาน

- มีตาราง/รายการลูกค้าและ modal เพิ่ม–แก้ไขลูกค้า
- จัดลำดับคอลัมน์ให้ใกล้ Excel งานจริง; ต้องรักษาการเรียงข้อมูลที่ใช้จริง
- แก้ปัญหาอัปโหลดรูปหลายรูป/รูปใหญ่ทำให้ modal ค้าง และปรับปุ่มเพิ่มภาพ/บันทึก
- แก้ Export Excel ที่เคยแสดงตัวเลขแบบ E+12
- มีการจัดกลุ่มงาน ผู้รับผิดชอบ สัญชาติ และข้อมูลสถานะพื้นฐาน
- ข้อกำหนด UI: เลข 0 ใน user-facing UI ห้ามใช้ฟอนต์ที่มีจุดหรือเส้นเฉียง

> **หมายเหตุ:** สถานะ: CONFIRMED HISTORICAL; ยังต้อง mobile regression, import/export stress test และ production acceptance

### นายจ้าง / บริษัท

- มีเมนูและข้อมูลนายจ้าง/บริษัทเป็น master data
- ใช้เป็นฐานของเคส เอกสารนายจ้าง และแรงงานในสังกัด
- ยังต้องเพิ่ม/ตรวจ profile fields เช่น เอกสารบริษัท ผู้มีอำนาจ สถานประกอบการ/สาขา ประวัติเคส และเอกสารใกล้หมดอายุ
- ห้ามเปลี่ยน schema เดิมเพื่อรองรับ Phase 2 โดยไม่ audit production data และ foreign keys

### Import / Export

- มีเมนูนำเข้าและการส่งออก Excel/CSV
- Export Excel ปัญหา scientific notation ถูกแก้แล้ว
- Meta Ads ใช้ CSV import แยกจาก customer import
- ยังต้อง stress test ไฟล์ใหญ่, duplicate, invalid rows, rollback และ mobile/desktop regression

### Document Center / คลังเอกสาร / Storage Foundation

- มีคลังเอกสารกลางและเอกสารลูกค้า ใช้ต่อกับ customer modal และ LINE document helper
- มี metadata, status/note, action counts และ signed URL flow สำหรับเปิดดูไฟล์
- Phase 2 นำมาต่อยอดเป็น owner-aware document selector และ checklist linking
- ไฟล์จริงต้องเก็บใน Storage; database ห้ามเก็บ base64 เป็นวิธีหลัก
- ต้องคง privacy rule: audit/report ห้ามมี storage path, bucket, file_data, base64, signed/public URL, token หรือ credential

### เอกสารจาก LINE และ PDF+Excel Helper

- ระบบ PDF+Excel helper / LINE batch ทำเสร็จและใช้งานจริงได้แล้ว
- ระบบนี้ถูกกำหนดเป็น FROZEN — ห้ามแตะระหว่างทำงาน Phase 2 หรือ smoke test อื่น
- คำเรียก integration ต้องเป็น LINE Messaging API ไม่ใช่ LINE Notify

### ระบบตอกบัตร / Attendance

- มีหน้าและ flow ตอกบัตร, attendance summary และพนักงานขาดงาน
- เคยทดสอบส่งข้อความเข้า LINE กลุ่มสำเร็จผ่าน LINE Messaging API
- ปัจจุบันพักการแจ้งเตือนกลุ่มไว้ก่อน เพื่อควบคุมโควต้าและทดสอบผู้ใช้กลุ่มเล็ก
- มี bug ที่เคยพบ: notification รวมแสดง 0 จนเข้าไปหน้า “พนักงานขาดงาน” แล้วจึงแสดงจำนวนจริง
- ห้าม refactor attendance ระหว่างทำ Stage เอกสาร เว้นแต่มี bug เฉพาะที่ผู้ใช้อนุมัติ

### Meta Ads Analytics

- มีหน้า “วิเคราะห์โฆษณา Meta” แบบ local/manual CSV
- รองรับ KPI CTR, CPC, CPM, Frequency, Leads และ executive classification Scale/Hold/Stop/Monitor
- มี Executive Report, Copy report, Export .txt/.csv
- ไม่มี Meta API จริง ไม่มี token และยังห้ามตีความว่าเป็น live integration
- ห้าม deploy/push หรือเพิ่ม API จริงโดยไม่มี Stage ออกแบบ security/token/data mapping แยก
- หมายเหตุ inventory (2026-07-24): มีไฟล์ standalone `ai_autopost_system.html` ถูก track ใน repo อยู่ **นอก navigation หลักของ CRM** — Recovery Inventory ระบุว่าเป็นระบบวางแผน/โพสต์เนื้อหา Meta แบบแยกเดี่ยว การใช้งานจริง เจ้าของ สถานะการทดสอบ และขอบเขตอนาคต **ยังไม่ยืนยัน** ตอนนี้ **ยังไม่จัดเป็น Core CRM — การจัดประเภทสุดท้ายรอการตัดสินใจของเจ้าของ** ห้ามอธิบายว่าเสร็จแล้ว, Production-ready หรือ deploy ใช้งานจริงอยู่; Meta Ads ใน CRM ยังเป็น local/manual CSV และ live Meta API ยังไม่อนุมัติ

### Login, User Management, Security, RLS และ Audit

- มี login UI, app_users, role admin/staff, active/inactive user และ session validation
- commit สำคัญ 18b9b85 harden app users RLS and session validation
- มี security logs/device nickname/user management foundation และ RPC patterns สำหรับตรวจ identity
- แนวทาง delete safety เปลี่ยนเป็น Staff ส่งคำขอลบ → Admin อนุมัติ; Staff ไม่ควรลบ customer/document โดยตรง
- ต้องเพิ่ม/ยืนยัน IP/device tracking, new-device/suspicious login detection และลด password sharing ก่อน rollout จริง
- Audit ต้องแยก strict กับ best-effort ตามความเสี่ยง; ห้ามลบ audit_logs ใน cleanup ปกติ

> **หมายเหตุ:** สถานะ: foundation มีจริง แต่ delete approval/security logs/device/IP ยังต้อง end-to-end acceptance และ production readiness

### UI/UX และ Mobile

- Login และ sidebar/navigation เคย refactor หลายรอบ; โทนหลักเป็นฟ้า/ส้มแบบบริษัท
- ระบบควรให้พนักงานรู้สึกง่ายกว่า Excel ไม่ใช้คำเตือนราชการซ้ำทุกจุด
- หน้า Phase 2 ควรใช้ชื่อผู้ใช้เข้าใจ เช่น “งานเอกสารแรงงาน” หรือ “ศูนย์งานเอกสารแรงงาน” ไม่ใช้ชื่อ dev “เคสงาน Phase 2”
- ยังมี mobile regression บางหน้า เช่น scroll/viewport มองไม่เห็นส่วนล่าง ต้องทดสอบจริงหลายขนาดหน้าจอ
- ห้ามเปลี่ยน global font/zero glyph แบบทำให้เลข 0 มีจุดหรือเส้น

## Phase 2 — Product Concept ที่ยืนยันแล้ว

Phase 2 ไม่ใช่ระบบ login เข้า e-WorkPermit แทนพนักงาน ไม่ใช่ bot ยื่นคำขอราชการ และไม่ควรให้ AI กดยื่น ชำระเงิน หรือยืนยัน OTP แทน

Product concept ที่ถูกต้องคือ “CRM รุ่งฟ้า = ศูนย์กลางเตรียมงานก่อนยื่นจริงในระบบราชการ” ระบบช่วยจัดข้อมูล ตรวจเอกสาร สร้าง checklist บันทึกเลขคำขอ ติดตามสถานะ และเก็บหลักฐานหลังพนักงานยื่นจริง

- ฐานข้อมูลกลางเดียว: customer/worker/employer/establishment/document
- โมดูลเคสแยกจาก master list แต่ใช้ข้อมูลกลางร่วมกัน
- Checklist ถูกสร้างตามประเภทงาน มติ มาตรา แบบฟอร์ม และเงื่อนไข
- พนักงานเป็นผู้ตรวจและกดยื่นจริงใน e-WorkPermit
- CRM เก็บเลขคำขอ ชำระเงิน วันนัด เอกสารตอบรับ และประวัติหลังยื่น
- คำเตือน “ไม่ใช่ระบบราชการ” ควรอยู่ใน help/info จุดเดียว ไม่รบกวนทุก modal

### Workflow กลางของเคสเอกสารแรงงาน

```text
เลือกแรงงาน/นายจ้าง/สถานประกอบการ
→ เลือกประเภทเคส
→ ระบบถามข้อมูลสำคัญ
→ สร้าง checklist ตามมติ/มาตรา/แบบฟอร์ม
→ ผูกเอกสารจากคลังหรืออัปโหลดเพิ่ม
→ ตรวจครบ/ขาด/ต้องแก้
→ พร้อมยื่น
→ พนักงานยื่นจริงใน e-WorkPermit
→ บันทึกเลขคำขอ/สถานะ/ชำระเงิน/วันนัด
→ เก็บเอกสารตอบรับ
→ ปิดเคสและเก็บประวัติ
```

### ประเภทเคสที่วิเคราะห์ไว้

- ลงทะเบียนคนต่างด้าวและสถานะบัญชี e-WorkPermit
- MOU มาตรา 41 แบบ นจ.2
- MOU มาตรา 46 แบบ นจ.2
- ส่งมอบ MOU มาตรา 43 แบบ บต.13
- แจ้งคนต่างด้าวเข้าทำงาน
- แจ้งออก แบบ บต.53
- แจ้งไม่รับคนต่างด้าวเข้าทำงาน / คนต่างด้าวไม่ยินยอมทำงาน
- มาตรา 60 วรรคสอง แบบ บต.32
- CI, Passport, Visa, Work Permit และต่ออายุ
- รายงานตัว 90 วัน, แจ้งที่พัก, เปลี่ยนนายจ้าง, ต่ออายุ MOU
- งานตามมติ ครม. เช่น มติ 11, มติ 24, มติ 2 ธ.ค. และมติในอนาคต

> **หมายเหตุ:** PDF บางไฟล์ชื่อกับหัวข้อภายในคลาดเคลื่อน โดยเฉพาะแจ้งเข้า/แจ้งออก ต้องตรวจหน้าจอจริงหรือคู่มือฉบับล่าสุดก่อนลง template ถาวร

### Checklist และสถานะงานที่ออกแบบไว้

| กลุ่ม | ตัวอย่าง |
| --- | --- |
| เอกสารแรงงาน | Passport/CI, Visa, Work Permit, รูปถ่าย, ใบรับรองแพทย์, ประกันสุขภาพ |
| เอกสารนายจ้าง | บัตรประชาชน, ทะเบียนบ้าน, หนังสือมอบอำนาจ, ข้อมูลติดต่อ |
| เอกสารบริษัท | หนังสือรับรองบริษัท, ภ.พ.20, ทะเบียนพาณิชย์, ผู้มีอำนาจลงนาม |
| เอกสารเคส | Demand/นจ.2, แบบฟอร์ม, ใบรับคำขอ, เลขคำขอ, หลักฐานชำระเงิน, ใบนัด, เอกสารตอบรับ |
| สถานะ checklist | missing, received, reviewing, approved, needs_fix, waived, not_required |
| สถานะเคส | ร่าง, รอเอกสาร, รอตรวจ, เอกสารไม่ครบ, พร้อมยื่น, ยื่นแล้ว, รอชำระ, รอนัด, ตีกลับ/ต้องแก้, อนุมัติ, ปิดงาน, ยกเลิก |

### ระบบสร้างเอกสารอัตโนมัติ — ทิศทางอนาคต

แนวคิด “กรอกข้อมูลครั้งเดียว → สร้างเอกสารหลายชุด” ทำได้จริงในฐานะ Single Entry Document Generator แต่ต้องทำหลัง case/checklist/template นิ่งแล้ว

ระบบสามารถสร้างเอกสารภายใน แบบร่าง เอกสารประกอบ สัญญาจ้าง หนังสือมอบอำนาจ ใบปะหน้า checklist และชุดเตรียมยื่นได้ แต่ใบอนุญาต ใบรับคำขอ ใบนัด ใบเสร็จ และผลอนุมัติจริงต้องมาจากระบบราชการ

- ห้ามโฆษณา/ออกแบบว่าระบบสร้างเอกสารราชการจริงหรือยื่นแทนได้ 100%
- คำว่า “ไม่ถึง 5 นาที” ใช้ได้เฉพาะกรณีข้อมูลครบและ template ผ่านการตรวจแล้ว
- ต้องมี versioning ของ template, preview, approval และ audit ก่อนใช้จริง

## Stage History — งานที่ทำจริงและหลักฐานสำคัญ

### Commit/Change History ที่ควรรู้

| Commit | ความหมาย |
| --- | --- |
| bf40820 | Record F1 payment-specific stage closeout in source-of-truth docs — F1 documentation-closeout commit (historical stage evidence) |
| e9d035c | Add CRM project handoff documentation — parent ของ bf40820 และเป็น HEAD ตอนทดสอบ F1 |
| 54680ec | Add staging-only seed script for owner-aware document tests — code baseline ของ Stage 58K-C |
| e9e6028 | Add strict audit logging to case document unlink |
| 850117a | Make payment checklist items guidance-only in document selector |
| 504694f | Add owner-aware checklist document selector |
| 7475efe | Add case document owner link migration draft |
| 18b9b85 | Harden app users RLS and session validation |
| 35bf251 | Refactor CRM login warm theme and language |
| 56d9dbe | Refactor CRM sidebar navigation grouping |
| 6929bb3 | Refactor customer table column order |
| fb542cc | Refactor customer modal and fix document upload save |
| c7de1e9 / d7cc639 / 1e266ec | Meta Ads dashboard / CSV import / executive report builder |

> **หมายเหตุ:** เอกสาร handoff รุ่นเก่าเคยระบุ 13e00ee, 54680ec, e9d035c และ bf40820 เป็น "latest commit" ตามลำดับ — ทั้งหมดเป็น stage evidence/historical เท่านั้น **current live HEAD ต้องอ่านจาก Git ทุกครั้ง** ห้ามตรึงค่า HEAD ปัจจุบันในเอกสาร

### Stage 58K-C Runtime Smoke — Final Matrix

| Test | Scenario | ผลสุดท้าย | หมายเหตุ |
| --- | --- | --- | --- |
| T1 | Primary worker owner-aware link | Runtime full-cycle PASS | worker owner=1, case_worker=1 |
| T2 | Secondary worker / Name List | Runtime full-cycle PASS | worker owner=2, case_worker=3 |
| T3 | Case-owned document | Runtime full-cycle PASS | case owner=1, case_worker=null |
| T4 | Employer-owned document | Runtime full-cycle PASS | ทดสอบบน disposable case id=2 |
| T5 | Internal document | Runtime full-cycle PASS | internal owner=1, item17 |
| T6 | Duplicate / Idempotent link | Runtime PASS | re-link คืน already_linked=true, combo คง 1 |
| T7 | Unrelated document rejection | UI guard runtime-observed + backend static verified | ไม่มี negative live RPC probe |
| T8 | Inactive / non-member worker rejection | Static/UI-protected | negative SQL probe ถูก permission 42501 ก่อน function body; ไม่ใช่ live business-guard PASS |
| T9 | Dedicated unlink + strict audit | Runtime PASS | source document คงอยู่, unlink audit strict |
| T10 | Audit privacy scrub | READ-ONLY PASS | forbidden hits=0 |
| T11 | Row count/original case invariant | READ-ONLY PASS | fixture/invariants ไม่ drift |
| T12 | Payment proof | Code contract verified; UI runtime not testable; fixture not ready | Classification B+C |
| T13 | Establishment rejection | Intentionally unsupported; static verification PASS | Classification D, owner_link_not_supported |

> **หมายเหตุ:** หมายเลขในแผนเก่าเคยวาง T4 Internal / T5 Employer แต่ execution จริงสลับหมายเลขกัน; coverage ครบทั้งสอง owner type แล้ว ไม่ต้องย้อนเทสซ้ำ

### Stage 58K-C Cleanup

- ลบเฉพาะ documents source=TEST_58K_SEED จำนวน 5 รายการตาม allowlist
- ก่อนลบยืนยัน seed_links=0, case_payments refs=0, non-seed documents=0
- Claude Code connector เป็น read-only จึงให้ผู้ใช้รัน transactional SQL ใน Supabase Staging SQL Editor
- ผลหลัง cleanup: seed_docs=0, documents total=0, seed_links=0, total case_documents=0, case_payments=0
- audit_total คง 131 ตาม retention; customer/employer/case/case_worker/checklist ไม่ถูกแตะ
- Production untouched, working tree clean

### F1 Payment-specific Stage — CLOSED 2026-07-14

Stage นี้ปิด runtime gap ที่ Stage 58K-C T12 บันทึกไว้ว่า “fixture not ready / UI runtime not testable” ผลของ T12 ในตารางด้านบนยังคงเป็นหลักฐานประวัติศาสตร์ตามเดิม ไม่ได้ถูกแก้ให้กลายเป็น PASS ย้อนหลัง

Fixture ชั่วคราว (ลบออกแล้ว): disposable case id=2, documents id=11 (same-case proof, customer 3) และ id=12 (wrong-case proof, customer 4), payment id=1 (service_fee, due 100, paid 0, เริ่มต้น `unpaid`)

| หัวข้อ | ผล |
| --- | --- |
| เส้นทางที่ใช้ | Dedicated payment path (`app_save_case_payment`) — ไม่ใช่ checklist document selector |
| สร้าง payment | 1 แถวเท่านั้น; case/type/ยอด/สถานะถูกต้อง; `proof_document_id` null; `paid_at` null |
| ผูก same-case proof | `proof_document_id=11` ผ่าน UI หลักฐานการชำระเงินโดยเฉพาะ; **ไม่มี** case_documents row |
| ป้องกัน wrong-case | เอกสาร id=12 ไม่ปรากฏใน picker (กรองตามลูกค้าเจ้าของเคส) + backend `document_not_allowed` ตรวจแบบ static — **UI runtime-observed + backend static verified; ไม่มีการบังคับเขียนลบเชิงลบ** |
| update-in-place | แก้ไขแถวเดิม id เดียวกัน; ไม่เกิดแถวซ้ำ |
| การคงหลักฐาน | ส่ง proof เป็น null/ไม่ส่ง = คงค่าเดิม; proof ยังเป็น 11 หลัง update และหลัง cancel |
| เปลี่ยนสถานะ | `unpaid → cancelled`; `paid_at` ยังเป็น null; ถือเป็น synthetic status-flow test เท่านั้น ไม่ใช่การชำระเงินจริง |
| audit / privacy | rows 204–207 (create/proof_link/update/cancel) append-only; forbidden hits = 0 |
| invariants | case_documents = 0 ตลอด; payment checklist item ยัง guidance-only; original case id=1 คง 17 items และ 13/4/0 |
| cleanup | ลบเฉพาะ payment id=1 และ documents 11, 12; audit ถูกเก็บไว้; ไม่มี business record ใดถูกลบ |
| code/migration | ไม่ต้องแก้โค้ดและไม่ต้องทำ migration |

ข้อจำกัดที่บันทึกไว้ (ยังไม่แก้ในสเตจนี้): payment create ยังไม่มีการป้องกัน idempotency ที่พิสูจน์ได้ (ผู้ใช้กด Save ครั้งเดียวเท่านั้น), ยังไม่มี proof-detach workflow และยังไม่ได้ทดสอบ, payment audit เป็น best-effort

## สถานะ Git / DB — LAST VERIFIED SNAPSHOT (ต้องตรวจสดก่อนนำไปใช้)

| กลุ่ม | ค่าล่าสุด |
| --- | --- |
| Repo / Branch / HEAD | D:\dev\claude \| feature-attendance \| current HEAD อ่านจาก Git; last committed checkpoint 80dcafe; working tree มีงาน F2/58L ยังไม่ commit |
| Git | working tree clean ณ snapshot; local = origin/feature-attendance (0/0) — re-verify สดก่อนเขียน |
| Staging HTML | rungfar_crm_17.STAGING.local.html; Production ref occurrences=0 |
| Staging ref | bzwtknqvhvdmatangzqf |
| Production | magwqolbjmwymqxelizl — untouched |
| seed_docs / documents total | 0 / 0 |
| seed_links / total case_documents | 0 / 0 |
| case_payments | 0 |
| audit_total | 135, id range 73–207, retained (รวม payment audit 204–207 จาก F1; ค่า 131/73–203 เป็นค่าประวัติศาสตร์ของ 58K-C) |
| Original case | id=1, CASE-20260709-000001, draft, customer_id=1, employer_id=null |
| Case workers | 2 active; primary customer 1, secondary customer 2; มี historical inactive row ของ customer 2 |
| Checklist | 17 items; missing/received/approved=13/4/0 |
| Key items | item5 missing, item6 missing, item13 payment_receipt missing, item17 submit_result_note received with 0 active links |
| Synthetic entities | customers 1–4 active; employer id=2 active; disposable case id=2 cancelled |
| Establishment | ตาราง `public.establishments` deployed บน Staging + RPC + UI; Admin runtime acceptance PASS; toggle duplicate-fix + same-state no-op (migration 20260813) PASS; fixture cleanup PASS (baseline 0); Staff runtime NOT TESTABLE; migration-history UNVERIFIED |

> **หมายเหตุ:** ค่าชุดนี้เป็น Staging fixture snapshot หลัง cleanup ไม่ใช่ข้อมูล Production และต้องยืนยันใหม่ก่อน Stage ถัดไป

## Known Product Gaps / Residues

| รหัส | Gap | ผลกระทบ | แนวทาง |
| --- | --- | --- | --- |
| G1 | Unlink ไม่ auto-revert received→missing | item อาจเป็น received ทั้งที่ไม่มี active link | ตัดสิน product rule แล้วทำ migration/UI ให้สอดคล้องใน Stage แยก |
| G2 | Reset เป็น missing เก็บ checked_by_code / checked_at เดิม | เกิด stale attribution marker | ตัดสินว่าจะล้างเมื่อ reset หรือแสดงเป็น historical marker |
| G3 | UI chip: ผ่าน=approved, ขาด=missing, ลิงก์=linked docs; received ไม่มี chip บนสรุป | ผู้ใช้สับสน received กับ passed | ปรับ wording/summary หลัง product decision |
| G4 | checklist.update audit best-effort แต่ link/unlink strict | ความสม่ำเสมอของ audit ต่างกัน | review risk แล้วกำหนด contract ชัดเจน |
| R1 | item17 คง checked_by/checked_at หลัง full-cycle reset | instance ของ G2 | บันทึกเป็น residue ห้ามลืม |
| F1 | ~~Payment-specific fixture/UI stage~~ **CLOSED 2026-07-14** | runtime gap ของ T12 ถูกปิดแล้ว | ปิดแล้ว — ดูหัวข้อ F1 Payment-specific Stage |
| F1a | payment create ยังไม่มี idempotency protection ที่พิสูจน์ได้ | กดซ้ำอาจสร้างรายการซ้ำ | ตัดสิน product/technical แล้วทำ Stage แยก |
| F1b | ยังไม่มี proof-detach workflow และยังไม่ได้ทดสอบ | ถอดหลักฐานออกไม่ได้ผ่าน UI ปัจจุบัน | ตัดสินว่าจำเป็นหรือไม่ก่อนออกแบบ |
| F1c | payment audit เป็น best-effort | audit อาจขาดได้โดยไม่ทำให้ธุรกรรมล้ม | review ร่วมกับ G4 |
| F2 / 58L | PARTIAL; `public.establishments` deployed + Admin runtime acceptance PASS + toggle fix/no-op PASS + cleanup PASS; ยังเหลือ Staff runtime (ไม่มี active staff), Employer full CRUD, est.↔case, est.-owned document, migration-history registration | สมมติผิดว่าเสร็จทั้งหมดจะข้าม gap ที่ยังค้าง | ทำ F2/58L-CLOSE-2 (diff/commit prep) แล้วเปิด stage ย่อยที่เหลือแยกอนุมัติ |
| N1 | Attendance notification summary เคยแสดง 0 จนเข้า subpage | ข้อมูลแจ้งเตือนอาจ stale | regression test notification aggregation |
| M1 | Mobile viewport/scroll บางหน้า | ผู้ใช้มือถือมองไม่เห็นส่วนล่าง | ทดสอบหลายขนาดและแก้เฉพาะจุด |
| S1 | Security/device/IP/delete approval ยังไม่ผ่าน rollout acceptance | เสี่ยง password sharing/ลบข้อมูลผิด | จบ production-readiness gate ก่อนผู้ใช้ 12 คน |

## สิ่งที่ยังไม่ทำ / ยังไม่ถือว่าเสร็จ

- Stage 58L Establishment Schema Reconciliation: apply/reconcile employer_establishments และ RPC ที่เกี่ยวข้องบน Staging ก่อน Production
- ตัดสิน F1 follow-ups ที่ยังค้าง: payment create idempotency และความจำเป็นของ proof-detach workflow
- Product decision + code สำหรับ G1–G4 โดยห้ามแอบแก้ระหว่าง smoke test
- Delete request/approval end-to-end acceptance: Staff ขออนุมัติ, Admin อนุมัติ, audit/restore/error states
- Security log, IP/device, suspicious/new device detection และการลด password sharing
- Dashboard งานต้องทำและ notification aggregation regression
- Expiry drilldown/alerts เช่น Passport, Visa, Work Permit, 90 วัน และสถานะใกล้หมดอายุ
- Import/export stress test และ data validation/rollback
- Mobile/desktop regression ทั้งระบบ
- คู่มือผู้ใช้ฉบับสั้นและ training flow
- Pilot 2–3 ผู้ใช้ และ rollout 12 ผู้ใช้
- Checklist templates จาก PDF จริงครบทุกประเภท พร้อม versioning และ validation
- e-WorkPermit tracking, reports, document generator, portal/PWA, OCR/AI
- Production Smoke — ยังไม่เริ่ม และต้องมีแผน subset แยกหลัง Staging ผ่านพร้อมอนุมัติใหม่

## ข้อห้ามและ Safety Rules

- ห้ามใช้ path เก่า OneDrive ไม่ว่าเครื่องใด
- ห้ามแตะ Production หาก prompt ไม่ระบุอนุมัติชัดเจนและไม่มี environment fingerprint
- ห้าม commit, push หรือ deploy ก่อนผู้ใช้ทดสอบและอนุมัติ
- ห้าม run SQL จากการเดา; ต้องอ่าน migration/function/signature จริงก่อน
- ห้าม drop/rollback/raw-delete production tables หรือข้อมูลจริง
- Staff ห้ามลบ customer/document โดยตรง; ใช้ delete request → Admin approval
- ห้ามแก้ระบบ PDF+Excel helper/LINE batch ที่ freeze
- ห้ามแก้ Product Gap ระหว่าง smoke test ที่มี scope อื่น
- ห้ามใช้ Claude Code และ Codex แก้ branch เดียวกันพร้อมกัน
- ห้ามส่ง storage_path, file_data, base64, bucket, permanent signed/public URL, token, key หรือ credential ใน audit/report/UI
- ห้ามเรียก LINE integration ว่า LINE Notify; ใช้ LINE Messaging API
- ห้ามให้ AI login/กดยื่น/จ่ายเงิน/OTP ใน e-WorkPermit แทนพนักงาน
- ห้ามสร้างเอกสารราชการปลอมหรือแสดงว่า CRM คือระบบราชการ
- ห้ามใช้เลข Stage/T-number จากความจำ; ต้องอ่าน TEST_PLAN/plan file
- ถ้า CURRENT_STATE_LOCK หรือ Git/DB ไม่ตรง expected ให้ HARD STOP ไม่ด้นต่อ

## Roadmap หลักของโครงการ

Roadmap ต้องแยก “Business Phase” ออกจาก “Technical Stage” เพื่อไม่ให้สับสนกับเลข Stage ทดสอบ เช่น 58K-C หรือ T1–T13

### Business Phase

| Phase | เป้าหมาย | Exit Criteria |
| --- | --- | --- |
| Phase 1 — Core CRM / Production Readiness | Master data, customer/employer, documents, alerts, security, permissions, delete approval, audit, import/export, mobile/desktop, manual | ระบบครบและเสถียร → pilot 2–3 คน → rollout 12 คน |
| Phase 2 — Labor Document Case Hub | Case management, checklist rules, document linking, payments, appointments, e-WorkPermit tracking, PDF-based templates | พนักงานเตรียม/ตรวจ/ติดตามเคสได้ครบ โดยยื่นจริงเองในระบบราชการ |
| Phase 3 — Portal & Automation | Customer upload portal/PWA, document generator, OCR/AI Assist, automation | ลดงานพิมพ์ซ้ำและรับเอกสารได้สะดวก โดยยังมี human approval |

### Technical Product Stages

| Stage | ขอบเขต | สถานะ |
| --- | --- | --- |
| Stage 0 | ทำ Phase 1 ให้เสถียรและ production-ready | ยังมี backlog |
| Stage 1 | Document Vault / Storage Foundation | ฐานมีแล้ว; ต้อง harden/scale |
| Stage 2 | Worker/Employer Profile Upgrade | ยังต้องเติม fields/UX |
| Stage 3 | Basic Case Management | foundation ทำไปบางส่วน |
| Stage 4 | Checklist Templates ตาม PDF | foundation + smoke ทำแล้วบางส่วน; content ยังไม่ครบ |
| Stage 5 | e-WorkPermit Tracking | planned |
| Stage 6 | Reports / Dashboard | planned/บาง dashboard มีอยู่ |
| Stage 7 | Document Generator | planned หลัง template นิ่ง |
| Stage 8 | Customer Upload Portal / PWA | deferred |
| Stage 9 | OCR / AI Assist | deferred หลัง data model/permissions นิ่ง |

### ลำดับงานแนะนำหลัง Handoff

- Step A: ✅ เสร็จแล้ว — สร้างเอกสาร Source of Truth ครบชุดและ commit/push แล้ว (ล่าสุด bf40820 บันทึกผลปิด F1)
- Step B: F2/58L Establishment = **PARTIAL** — Admin runtime acceptance + duplicate-toggle fix + same-state no-op + fixture cleanup ผ่านบน Staging (ยังไม่ commit) ถัดไปคือ **F2/58L-CLOSE-2** (final exact diff/evidence review + commit prep) แล้วเปิด stage ย่อยที่เหลือ (Staff runtime, Employer full CRUD, est.↔case, est.-owned document, migration-history) แยกอนุมัติ; IDENT-1 identity/session เป็น **parked design backlog**
- Step C: กลับมาปิด Phase 1 production-readiness backlog: delete/security/audit/alerts/mobile/import-export/manual
- Step D: pilot 2–3 คน แล้วเก็บ bug/feedback
- Step E: แก้และ rollout 12 คน
- Step F: เดิน Phase 2 checklist content/workflow จาก PDF และงานจริงแบบ Stage ต่อ Stage
- Step G: Production Smoke ทำหลัง Staging ทุก gate ผ่านและมีแผน subset แยกเท่านั้น

## วิธีสั่ง Claude Code / Codex ให้ไม่หลุดทิศ

### กฎก่อนเริ่มทุกคำสั่ง

```text
1. อ่าน AGENTS.md
2. อ่าน PROJECT_MASTER_HANDOFF.md
3. อ่าน CURRENT_STATE_LOCK.md
4. อ่าน ROADMAP.md และ TEST_PLAN.md เฉพาะส่วนที่เกี่ยวข้อง
5. รัน Git pre-flight
6. ตรวจ environment/project ref
7. ตรวจ DB baseline แบบ READ-ONLY
8. ถ้าค่าไม่ตรงให้ HARD STOP
```

### รูปแบบ Prompt มาตรฐาน

```text
ชื่อ Stage: <ชื่อเดียวที่ชัดเจน>
Objective: <ผลที่ต้องพิสูจน์/แก้>
Environment: STAGING ONLY หรือ LOCAL ONLY
Mode: READ-ONLY / OPERATOR-ASSISTED / WRITE+VERIFY
Scope files/tables/functions: <ระบุ allowlist>
Out of scope: <สิ่งที่ห้ามแตะ>
Current STATE LOCK: <ค่าที่ต้องตรง>
Steps:
  1) Git/environment pre-check
  2) Code/DB contract inspection
  3) PRE-ACTION READY REPORT
  4) หยุดรอผู้ใช้กด UI หรืออนุมัติ mutation
  5) SELECT-only post-action verification
  6) Audit/privacy/invariant verification
  7) Cleanup/restore เมื่ออยู่ในแผน
  8) Final report + stop
Hard Stops: <รายการ error/state mismatch>
Commit/Push: PROHIBITED until user approval
```

### Operator-Assisted Protocol

- Claude Code ตรวจและ monitor; ผู้ใช้กด UI ที่เปลี่ยนข้อมูลเอง
- ก่อนคลิกต้องมี PRE-ACTION READY REPORT พร้อม exact path, payload และ expected result
- หลังผู้ใช้แจ้งว่าคลิกสำเร็จ ให้ Claude Codeทำ SELECT-only verification ก่อนเริ่ม step ถัดไป
- ห้าม Claude เรียก RPC แทนเมื่อ Stage กำหนด operator-assisted
- หนึ่ง action ต่อหนึ่ง verification; ห้ามกดรวดเดียวหลายครั้ง
- ถ้า toast/error/สถานะไม่ตรง ให้หยุดและรายงานข้อความเต็ม

### Write/Mutation Protocol

- ต้องระบุ environment, allowlist และ rollback/transaction strategy ก่อน write
- Migration/SQL ต้อง audit signature, grants, RLS, ownership, FK และ production impact
- หลัง write ต้องตรวจ Expected vs Actual, row count, audit, privacy, non-target rows และ working tree
- ห้ามแก้ไฟล์เพิ่มเพื่อ “ให้ test ผ่าน” ระหว่าง smoke test; บันทึก gap แล้วแยก Stage

### Commit/Push Protocol

```text
cd /d/dev/claude
git status --short --branch
git diff --check
git diff -- <files in scope>

# หลังผู้ใช้ตรวจผ่านและอนุมัติเท่านั้น
git add <allowlisted files>
git commit -m "<clear stage message>"
git status --short --branch
git log --oneline --decorate -5
git push origin feature-attendance
git status
```

> **หมายเหตุ:** ก่อน commit ต้องสรุปไฟล์ที่จะ add, สิ่งที่เปลี่ยน, test ที่ผ่าน และสิ่งที่ยังไม่ผ่านให้ผู้ใช้เห็นก่อน

### รูปแบบรายงานที่ต้องการจาก Claude Code

- Environment / Git — pwd, branch, HEAD, tree, refs
- Baseline Expected vs Actual
- Code/DB contract พร้อม file/function/line refs
- Exact UI path หรือ exact SQL scope
- Mutation result และจำนวนแถว
- Post-action SELECT-only verification
- Audit + privacy scan
- Guard invariants / non-target rows
- Known gaps ที่พบ แต่ไม่แก้แทรก
- Final STATE LOCK
- Verdict: PASS / PARTIAL / HARD STOP
- หยุดรอคำสั่ง ไม่เริ่ม Stage ถัดไปเอง

### วิธีเริ่มทำงานบนคอมเครื่องใหม่

- ตรวจว่า local staging HTML มีอยู่และเป็นไฟล์ล่าสุด
- ตรวจ checksum/size/modified time เมื่อคัดลอกไฟล์นอก Git
- ตรวจ Staging ref ในไฟล์และ Production ref count=0
- ห้ามเริ่มจาก backup folder แล้วแก้ต่อโดยไม่ sync กับ repo หลัก

```text
cd /d/dev/claude
git fetch origin
git switch feature-attendance
git pull --ff-only origin feature-attendance
git status --short --branch
git diff --check
git log --oneline --decorate -10
```

## Prompt เปิดแชทใหม่

```text
นี่คือแชทควบคุมโครงการ RUNGFA CRM ใหม่

ก่อนตอบหรือวางแผนงานใด ๆ ให้:
1. อ่าน PROJECT_MASTER_HANDOFF.md
2. อ่าน CURRENT_STATE_LOCK.md
3. อ่าน ROADMAP.md
4. อ่าน TEST_PLAN.md
5. อ่าน DECISIONS_LOG.md
6. สรุปสถานะปัจจุบัน สิ่งที่เสร็จ สิ่งที่ค้าง และข้อห้าม
7. ห้ามเสนอแก้ code หรือเริ่ม Stage ใหม่จนกว่าฉันจะยืนยันว่าความเข้าใจตรงกัน

รูปแบบการทำงาน:
- Chat/Work ใช้วิเคราะห์ วางแผน และคุมงาน
- Claude Code/Codex ใช้ลงมือเขียนและทดสอบ
- เอกสารใน Project/Repo เป็น Source of Truth
- ห้ามอาศัยความจำหรือเดาหมายเลข Stage
- ตอบภาษาไทยแบบตรงไปตรงมาและทำ prompt ให้คัดลอกได้
```

## Checklist สำหรับอัปเดต Handoff หลังจบแต่ละ Stage

- อัปเดต CURRENT_STATE_LOCK ทุกครั้งที่ HEAD/DB baseline เปลี่ยน
- อัปเดต TEST_PLAN ด้วยผลจริง Expected vs Actual
- อัปเดต DECISIONS_LOG เมื่อมี product/security decision
- อัปเดต ROADMAP เมื่อ Stage ปิดหรือเปลี่ยนลำดับ
- อัปเดต PROJECT_MASTER_HANDOFF เฉพาะเมื่อสถาปัตยกรรม/ขอบเขตใหญ่เปลี่ยน ไม่แก้ทุก action
- commit เอกสารพร้อม code หรือเป็น documentation checkpoint หลังผู้ใช้อนุมัติ
- อย่าเก็บ secret, token, service role key, PII หรือ URL signed ในเอกสาร

## แหล่งข้อมูลที่ใช้ประกอบ Handoff ฉบับนี้

- ประวัติแชทควบคุมโครงการและรายงาน Stage 58K-C T1–T13
- CRM_Phase1_Technical_Security_Handoff.md/.txt
- Phase 2 Product Workflow Handoff
- Phase 2 Handoff Summary และการวิเคราะห์คู่มือ e-WorkPermit
- รายงาน Git/DB/cleanup ล่าสุด ณ 13 กรกฎาคม 2026

> **หมายเหตุ:** เมื่อข้อมูลเก่าขัดกับค่าล่าสุด ให้ใช้ CURRENT Git/DB และ STATE LOCK ล่าสุดเป็นหลัก

## Final Handoff Verdict

โครงการพร้อมย้ายไปแชทใหม่ในเชิงบริบทแล้ว เมื่อแชทใหม่ได้รับไฟล์นี้และไฟล์ Source of Truth ที่จะสร้างในขั้นถัดไป

Stage 58K-C ปิดครบและ cleanup สำเร็จแล้ว ไม่ต้องย้อน T1–T13 ซ้ำ ไฟล์ Source of Truth ทั้งชุดถูกสร้างและ commit/push เรียบร้อยแล้ว (ล่าสุด bf40820) รวมถึงผลปิด F1 การทำงานถัดไปคือให้ผู้ใช้เลือกและอนุมัติ Stage ใหม่

| หัวข้อ | Verdict |
| --- | --- |
| Master Handoff | READY |
| Stage 58K-C | COMPLETE (historical) |
| F1 Payment-specific Stage | COMPLETE — closed on Staging 2026-07-14 |
| F1 documentation closeout | COMPLETE — commit bf40820, pushed 2026-07-22 |
| Staging cleanup | COMPLETE (58K-C และ F1) |
| F2 / Stage 58L | **PARTIAL** — Establishment Admin runtime acceptance PASS + duplicate-toggle fix PASS + same-state no-op PASS + fixture cleanup PASS บน Staging; Staff runtime NOT TESTABLE (ไม่มี active staff); Employer full CRUD pending; est.↔case + est.-owned document ยังไม่ทำ/unsupported; migration-history UNVERIFIED (ดู section "สถานะ F2/58L") |
| IDENT-1 identity/session | DESIGN COMPLETE — implementation PARKED (ไม่ใช่ Stage ถัดไป) |
| Production Smoke | NOT STARTED |
| Next execution stage | F2/58L-CLOSE-2 — final exact diff/evidence review + commit preparation (working tree ปัจจุบันยังไม่ commit) |
| New chat migration | READY AFTER FILE UPLOAD / PROJECT SETUP |
