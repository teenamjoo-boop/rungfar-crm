# PHASE 2 BACKEND — Backup + Staging Verification Runbook (Stage 58G-RESET-2)

**Type:** NO-CODE / DOCUMENTATION ONLY — ไม่รัน SQL, ไม่แตะ DB, ไม่แก้ migration, ไม่เปลี่ยน runtime
**Generated:** 2026-07-08
**Branch:** `feature-attendance`
**Baseline HEAD:** `564da28` — "Draft phase 2 backend contract"
**Companion docs:**
- `manual/PHASE2_BACKEND_CONTRACT_58F.md` (สัญญา/แผน backend — A–J)
- `manual/DRAFT_PHASE2_BACKEND_SQL_58F_DO_NOT_APPLY.sql` (ร่าง SQL 7 ส่วน — comment ล้วน)

> ⚠️ เอกสารนี้คือ **runbook** (คู่มือลงมือ) สำหรับ backup + ทดสอบ staging + rollback + gate ก่อน apply backend Phase 2
> **Stage 58G ไม่เปลี่ยนสภาพแวดล้อมใด ๆ** — เป็นเอกสารเตรียมความพร้อมเท่านั้น
> ทุกขั้นตอน "apply" ในเอกสารนี้เป็น **แผนเชิงแนวคิด** ห้ามรันอัตโนมัติ — ต้องมีคนตรวจ + เจ้าของอนุมัติทุกครั้ง

---

## 1. Purpose / Safety Principle (วัตถุประสงค์ + หลักความปลอดภัย)

Phase 2 backend (ตาราง `case_workers`, field ใหม่ `cases.mou_side` / `establishment_id`, การขยาย RPC ลิงก์เอกสารหลายเจ้าของ, เนื้อหา checklist จริง) **ต้อง apply หลังจากครบเงื่อนไขนี้เท่านั้น**:

1. **Backup** ตารางที่เกี่ยวข้องครบก่อนแตะ schema/ข้อมูลใด ๆ
2. **Staging test** — apply บน staging เท่านั้น แล้วทดสอบตาม §6
3. **Rollback check** — พิสูจน์ว่าถอนกลับได้จริงบน staging (§7)
4. **Explicit approval** — เจ้าของอนุมัติเป็นลายลักษณ์ก่อนเลื่อนไป production (§8)

หลักการแกน (ยกจาก 58F contract — ต้องรักษาไว้):
- **RPC-only** — ตารางใหม่ `revoke all ... from public, anon, authenticated` (รวม sequence)
- **Metadata-only** — ไม่คืน `file_data` / `base64` / `storage_path` / signed URL; เปิดไฟล์ผ่าน `dcOpenDoc` / document_id flow เดิม; คืน `has_storage boolean` แทน
- **Additive + Idempotent** — `create ... if not exists`, guarded constraint, `create or replace`, `on conflict do nothing`
- **No hard delete** — soft `is_active=false` / เปลี่ยนสถานะ / unlink ลบเฉพาะแถวลิงก์
- **ไม่ automate ราชการ** — ไม่เชื่อม/scrape/ยื่นแทน e-WorkPermit; เลขราชการพิมพ์เอง (optional)

> กติกาทอง: **ถ้ายังไม่ได้ backup + ยังไม่ทดสอบ rollback บน staging → ห้าม apply production เด็ดขาด**

---

## 2. Environment Rules (กติกาสภาพแวดล้อม)

แยก 3 สภาพแวดล้อมชัดเจน — ห้ามสับสน:

| สภาพแวดล้อม | คือ | 58G ทำอะไร | ใครแตะได้ / เมื่อไหร่ |
|---|---|---|---|
| **local frontend** | `rungfar_crm_17.html` + assets บนเครื่อง dev | อ่านอย่างเดียว | 58G ไม่แก้ · แก้ frontend เป็นคนละสเตจ |
| **staging database** | Supabase project แยกสำหรับทดสอบ (ไม่ใช่ของจริง) | ไม่แตะ | **58H+ แตะได้เฉพาะหลังอนุมัติ** |
| **production database** | Supabase project จริงที่มีข้อมูลลูกค้า | ไม่แตะ | **หลังผ่าน verification เต็ม + อนุมัติ (§8) เท่านั้น** |

ข้อความบังคับ:
- ✅ **58G ไม่แก้สภาพแวดล้อมใด ๆ** — สร้างเอกสาร runbook ไฟล์เดียว
- ✅ **58H เป็นต้นไป แตะได้เฉพาะ staging** และเฉพาะหลังเจ้าของอนุมัติ
- ✅ **production เปลี่ยนได้หลัง verification ครบ** (§8 production gate) เท่านั้น
- ❌ ห้าม apply ตรงบน production โดยข้าม staging
- ❌ ห้ามใช้ credential/URL ของ production ในขั้นทดสอบ

> ⚠️ ถ้ายังไม่มี staging project แยกจริง → **สร้าง/ยืนยัน staging ก่อน** เป็นเงื่อนไขเปิดของ 58H (อย่าใช้ production เป็น "staging ชั่วคราว")

---

## 3. Backup Checklist — ก่อน apply backend ใด ๆ

**เป้าหมาย backup (12 ตาราง)** — ต้อง backup ครบทุกตัวก่อนแตะ schema/ข้อมูล:

- [ ] `customers`
- [ ] `employers`
- [ ] `establishments`
- [ ] `cases`
- [ ] `case_templates`
- [ ] `case_template_checklist_items`
- [ ] `case_checklist_items`
- [ ] `case_documents`
- [ ] `documents`
- [ ] `case_payments`
- [ ] `case_appointments`
- [ ] `case_tracking_logs`

**เพิ่มเติม (แนะนำ):** `case_status_logs`, `audit_logs` (เพื่อสอบย้อนหลัง), และ Supabase **PITR / snapshot** ของทั้ง project

**Backup naming convention:**
```
phase2_backup_YYYYMMDD_HHMM_<table>.csv        (export ต่อ table)
phase2_backup_YYYYMMDD_HHMM_<table>.sql        (SQL dump ต่อ table)
phase2_backup_YYYYMMDD_HHMM_full.dump          (full project dump / snapshot ref)
```
ตัวอย่าง: `phase2_backup_20260708_1430_case_templates.csv`

**กติกา backup:**
- [ ] เก็บ **จำนวนแถว (row count)** ของทุกตารางไว้ในไฟล์ runbook log เพื่อเทียบหลัง apply/rollback (ดู `DRAFT_...SQL_58F` SECTION 1)
- [ ] เก็บ backup ใน storage ที่ **immutable / read-only** (ห้ามเขียนทับ) — ตั้งชื่อมี timestamp เสมอ
- [ ] backup ของ **staging** และ **production** แยกโฟลเดอร์/ป้ายชัดเจน — ห้ามปน
- [ ] ยืนยัน backup เปิด/อ่านได้จริง (สุ่มตรวจ 1–2 ไฟล์) ก่อนถือว่า "backup สำเร็จ"

---

## 4. Pre-apply Inspection Checklist — ก่อนกด apply บน staging

ยืนยันครบทุกข้อก่อนเริ่ม §5:

- [ ] **git commit ปัจจุบัน** ตรงกับที่ตั้งใจ apply (บันทึก hash ลง runbook log)
- [ ] **branch** = `feature-attendance` (หรือ branch ที่ตกลง)
- [ ] **working tree สะอาด** (`git status --short` ว่าง)
- [ ] **migration file ถูกรีวิวแล้ว** — additive/idempotent, ไม่มี DROP/RENAME/UPDATE แถวเดิม
- [ ] **มี rollback section** ในไฟล์ apply/migration (อ้าง `DRAFT_...SQL_58F` SECTION 6)
- [ ] **เลือก staging DB แล้ว ไม่ใช่ production** — ยืนยันซ้ำสองครั้ง
- [ ] **Supabase project URL / project-ref ตรวจแล้ว** — ตรงกับ staging (ไม่ใช่ ref ของ production)
- [ ] **ไม่มี raw storage path หลุด** — RPC ทุกตัวคืนเฉพาะ `has_storage` (code review)
- [ ] **ไม่มีการเปลี่ยน RLS / Storage / Edge Function** เว้นแต่ได้รับอนุมัติแยกต่างหาก
- [ ] **backup (§3) เสร็จและตรวจแล้ว** สำหรับ staging ก่อน apply

> ถ้าข้อใดข้อหนึ่งไม่ผ่าน → **หยุด** ไม่ต้อง apply · แก้ให้ครบก่อน

---

## 5. Staging Apply Plan (แผนลำดับปลอดภัย — เชิงแนวคิด)

> ⚠️ ลำดับนี้เป็น **แผน** — ไม่มีคำสั่งที่รัน SQL อัตโนมัติในเอกสารนี้
> คำสั่งจริงอยู่ในสคริปต์ dry-run/ROLLBACK ที่ทำในสเตจถัดไป (58H+) และต้องมีคนกดเอง

**A. Backup staging tables** — ทำ §3 ครบบน staging + เก็บ row count baseline
**B. Apply draft backend migration บน staging เท่านั้น**
   - schema additive (`case_workers`, `cases.mou_side`, `cases.establishment_id`, `case_template_checklist_items.mou_side`)
   - `create or replace` RPC (`app_link_case_document` ขยาย ownership; `app_create_case` +`p_mou_side`; `app_init_case_checklist` filter side)
   - ⚠️ รันในหน้าต่างทดสอบ · ห้ามแตะ production ref
**C. Verify schema** — column/constraint/index ใหม่มีจริง; แถวเดิมไม่ถูกแก้ (§6-C, §6-D)
**D. Verify RPC signatures** — signature เดิมคงลำดับ arg (frontend ไม่ต้องแก้); grant ครบ anon/authenticated; revoke public
**E. Verify create case** — `app_create_case` ยังสร้างเคสได้ (มี/ไม่มี `mou_side`)
**F. Verify checklist generation** — `app_init_case_checklist` คัดลอก item ถูก, idempotent (รันซ้ำไม่ duplicate), filter MOU side ถูก
**G. Verify document linking** — customer/case/worker ลิงก์ได้; employer/establishment ตามกฎ §6-E; เอกสารไม่เกี่ยวถูกปฏิเสธ
**H. Verify rollback plan** — ทดสอบ ROLLBACK / ถอน schema บน staging แล้วเทียบ baseline (§7)
**I. Production gate** — พิจารณาเลื่อน production **เฉพาะเมื่อ A–H ผ่านครบ + เจ้าของอนุมัติ** (§8)

> ทุก apply เนื้อหา (checklist content) ทำผ่าน RPC `app_admin_save_case_template_item` ในสคริปต์ **dry-run เริ่มด้วย `rollback;`** — เปลี่ยนเป็น `commit;` เฉพาะหลังตรวจผ่าน (อ้าง `DRAFT_...SQL_58F` SECTION 5)

---

## 6. Verification Test Cases (ทดสอบบน staging + local frontend ชี้ staging)

### A) Existing Phase 1 Safety (ของเดิมต้องไม่พัง)
- [ ] login ทำงาน (`app_verify_login` / session)
- [ ] รายชื่อลูกค้าเปิดได้
- [ ] เปิดรายละเอียดลูกค้าได้
- [ ] import / export ยังทำงาน
- [ ] delete approval flow ไม่ถูกแตะ
- [ ] LINE inbox / attendance ไม่ถูกแตะ
- [ ] หน้า Meta Ads ไม่ถูกแตะ
- [ ] Document Center เปิดเอกสารเดิมได้ปลอดภัย (metadata + open flow เดิม)

### B) Phase 2 Case Safety
- [ ] รายการเคสเปิดได้ (`app_list_cases`)
- [ ] dropdown สร้างเคส (pilot) แสดง **เฉพาะ 5 แม่แบบ pilot** เท่านั้น
- [ ] เคส frozen / non-pilot ยังขึ้น **"ต้องตรวจสอบ"**
- [ ] เปิดรายละเอียดเคสได้ (`app_get_case_detail`)
- [ ] panel checklist ทำงาน (`app_list_case_checklist`)
- [ ] panel payment / appointment / tracking ยังทำงาน
- [ ] readiness panel **ไม่ auto-submit / ไม่ auto-เปลี่ยนสถานะ** เคส

### C) Template / Checklist Content
- [ ] checklist count ของ MOU พม่า/ลาว/กัมพูชา ถูกต้อง (เทียบ 58F §B.1)
- [ ] checklist IN / OUT notification ถูกต้อง (58F §B.2–B.3)
- [ ] ถ้อยคำ staff-facing อ่านเข้าใจง่าย
- [ ] item ที่เป็น **NEED_REVIEW** ยังถูกทำเครื่องหมายชัด (เช่น `notify_in_form`, ค่าธรรมเนียม)
- [ ] ไม่มีถ้อยคำ automate ราชการ / ทำให้เข้าใจว่า CRM เป็นระบบราชการ

### D) case_workers / Name List
- [ ] เคสเดี่ยวเดิม (ไม่มีแถว `case_workers`) ยังทำงาน — fallback ใช้ `cases.customer_id`
- [ ] เคสหลายแรงงานแทนได้หลังสเตจ backend (58J)
- [ ] readiness **ต้องไม่ผ่านหลอก ๆ** เมื่อ Name List ยังไม่ครบ (นับ required docs ต่อคน)
- [ ] fallback ไป `cases.customer_id` ยังทำงานเมื่อไม่มี Name List

### E) Multi-owner Document Linking
- [ ] เอกสาร worker / customer ลิงก์ได้
- [ ] เอกสาร case (owner_type='case') ลิงก์ได้
- [ ] เอกสาร employer **ถูกปฏิเสธก่อน** backend รองรับ (`document_not_allowed`)
- [ ] เอกสาร employer **ผ่านเฉพาะหลัง** RPC update ที่อนุมัติ และเป็น employer เจ้าของเคส
- [ ] เอกสาร establishment ต้องมีความสัมพันธ์ถูกต้อง (ใต้ employer ของเคส / = `cases.establishment_id`)
- [ ] เอกสาร employer/establishment **ที่ไม่เกี่ยวถูกปฏิเสธ**
- [ ] ไม่มี `storage_path` / signed URL / base64 โผล่ (มีแค่ `has_storage`)

### F) Security Checks
- [ ] staff/admin active check คงอยู่ทุก RPC (identity predicate เดิม)
- [ ] arbitrary `owner_id` link ถูกปฏิเสธ (ต้องพิสูจน์ความเชื่อมโยงกับเคส)
- [ ] signed URL เปิดผ่าน document_id open flow เดิมเท่านั้น
- [ ] ไม่มี public URL หลุด
- [ ] ไม่มี direct storage path ใน UI

---

## 7. Rollback Runbook

**เมื่อไหร่ต้อง rollback:**
- verify §6 ข้อใดข้อหนึ่ง fail อย่างมีนัย (ของเดิมพัง / เอกสารหลุด / readiness ผิด)
- row count เพี้ยนจาก baseline โดยไม่ตั้งใจ
- พบพฤติกรรมที่ไม่ได้อยู่ในสัญญา (auto-submit, path หลุด ฯลฯ)

**ถอนอะไรก่อน (ลำดับ):**
1. **เนื้อหา/DML (checklist content):** สคริปต์อยู่ใน transaction เดียว → `ROLLBACK;` คืนทันที (default dry-run เป็น rollback อยู่แล้ว)
2. **RPC:** `create or replace` กลับ body เดิม (เก็บ body 54A-4 / 54A-3 ไว้เป็นสำเนา rollback)
3. **Schema additive:** ถ้าจำเป็นต้องถอน (เฉพาะ staging, เฉพาะเมื่อยังไม่มีข้อมูลใช้จริง):
   - `drop table if exists public.case_workers;`
   - `alter table public.cases drop column if exists mou_side;`
   - `alter table public.cases drop column if exists establishment_id;`
   - `alter table public.case_template_checklist_items drop column if exists mou_side;`

**ตรวจ rollback สำเร็จ:**
- [ ] row count ของ 12 ตารางกลับเท่า baseline (§3)
- [ ] schema กลับสภาพเดิม (column/constraint/index ที่เพิ่มหายไป — ถ้าเลือกถอน)
- [ ] RPC signature/behavior กลับเดิม
- [ ] frontend Phase 1 + Phase 2 เดิมทำงานปกติ (สุ่ม §6-A, §6-B)

**ตารางข้อมูลที่ได้รับผลกระทบ (ต้องเฝ้า):**
`case_templates`, `case_template_checklist_items` (เนื้อหา checklist), `cases` (field ใหม่), `case_documents` (ownership link ใหม่), `documents` (owner_type/owner_id) + ตารางใหม่ `case_workers`

**กติกาบังคับ:**
- [ ] เก็บ backup ให้ **immutable** — ห้ามเขียนทับ; rollback อ่านจาก backup timestamp
- [ ] **rollback ต้องทดสอบบน staging ก่อน** ถึงจะถือว่าพร้อมสำหรับ production

---

## 8. Production Gate Checklist

อนุญาต apply บน **production** เฉพาะเมื่อครบทุกข้อ:

- [ ] staging **backup** เสร็จ + ตรวจแล้ว
- [ ] staging **apply** เสร็จ (schema + RPC + เนื้อหา ตามที่อนุมัติ)
- [ ] staging **rollback** ทดสอบแล้วว่าถอนได้จริง
- [ ] **runtime tests ผ่าน** ครบ (§6 A–F)
- [ ] **เจ้าของอนุมัติชัดเจน** (เป็นลายลักษณ์)
- [ ] **ไม่มี NEED_REVIEW ที่ยัง block งานจริง** (item ที่ยังไม่ยืนยันกฎหมาย/แบบฟอร์มต้องไม่ถูกใช้เป็น required ที่ทำให้พนักงานทำผิด)
- [ ] ยืนยัน **เส้นทางความพร้อม 12-user rollout**
- [ ] **2–3 user test เป็น gate สุดท้ายเท่านั้น** — ทำหลังระบบพร้อมเต็ม ไม่ใช่ตอนนี้

> production apply ก็ต้องมี **backup production + PITR window** ก่อนเสมอ (ทำ §3 บน production ก่อนกด)

---

## 9. Hard Stops (ย้ำ — ห้ามข้าม)

- ❌ ยังไม่ทำ 2–3 user test
- ❌ ยังไม่ทำ 12-user rollout
- ❌ ไม่ auto-submit ไป e-WorkPermit
- ❌ ไม่เชื่อมต่อระบบราชการโดยตรง
- ❌ ไม่ automate การออกเอกสารราชการ
- ❌ ไม่มี OCR/AI assist
- ❌ ไม่มี Customer Upload Portal / PWA
- ❌ ไม่ apply production DB
- ❌ ไม่รัน SQL ใน 58G
- ❌ ไม่สร้าง migration ใน 58G
- ❌ ไม่เปลี่ยน Storage / RLS / Edge Function
- ❌ ไม่ทำ backend implementation โดยไม่มีการอนุมัติชัดเจน

---

## 10. Recommended Next Stages

- **58H** — Additive backend foundation (`mou_side`, `establishment_id`, `case_template_checklist_items.mou_side`) บน **staging เท่านั้น** หลังอนุมัติ
- **58I** — Apply approved checklist content (5 แม่แบบ, 58F §B) ผ่าน apply-script dry-run/ROLLBACK
- **58J** — `case_workers` / Name List foundation (backend + UI)
- **58K** — multi-owner document linking RPC (58F §E) + เปิดใช้ frontend
- **58L** — extra case fields (58F §F: `name_list_status` ฯลฯ) ถ้ายังจำเป็น
- **58M** — production verification gate

---

*จบ runbook 58G — documentation only. ไม่มีการรัน SQL, ไม่แตะ DB/สภาพแวดล้อม, ไม่แก้ migration/frontend, ไม่ commit จนกว่าเจ้าของอนุมัติ*
