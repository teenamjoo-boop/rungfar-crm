# PHASE 2 BACKEND CONTRACT — Stage 58F-RESET-2

**Type:** DRAFT / PLANNING ONLY — ไม่มีการรัน SQL, ไม่แตะ DB, ไม่เปลี่ยนพฤติกรรม runtime
**Generated:** 2026-07-08
**Branch:** `feature-attendance`
**Baseline HEAD:** `cf8b7ed` — "Polish template preview staff wording"
**Scope:** ร่างสัญญา (contract) การทำงานฝั่ง backend สำหรับ Phase 2 — เนื้อหาเช็คลิสต์จริง, Name List หลายแรงงาน, และการลิงก์เอกสารหลายเจ้าของ

> ⚠️ เอกสารนี้เป็น **ร่าง (draft)** เพื่อรีวิวเท่านั้น
> ทุก SQL/DDL ที่กล่าวถึงต้องผ่าน backup + staging + การอนุมัติของเจ้าของก่อนใช้จริง
> ยังไม่สร้าง migration ใต้ `supabase/migrations/` · ยังไม่แก้ `rungfar_crm_17.html` · ยังไม่แก้ app code

---

## หลักการทั่วไปของสัญญานี้ (contract principles)

Phase 2 เดิมทั้งหมดสร้างด้วย pattern เดียวกันซึ่ง **ต้องรักษาไว้** ในทุกงานต่อจากนี้:

1. **RPC-only** — ตารางใหม่ทุกตัว `revoke all ... from public, anon, authenticated` (รวม sequence) เขียน/อ่านผ่าน `SECURITY DEFINER` function เท่านั้น
2. **Identity predicate เดียวกันทุก RPC:**
   ```sql
   select ... from public.app_users u
   where u.id::text = p_user_id and u.username = p_username
     and coalesce(u.is_active, true) = true and u.role is not null limit 1;
   ```
   staff+admin ทำงานทั่วไป · admin-only สำหรับ toggle active / แก้ template
3. **Metadata-only** — RPC ห้ามคืน `file_data` / `base64` / `storage_path` / `storage_bucket` / signed URL; เปิดไฟล์ผ่าน flow เดิม (`dcOpenDoc` / document_id) เท่านั้น; ให้คืน `has_storage boolean` แทน path
4. **Additive + Idempotent** — `create table if not exists`, `add column if not exists`, guarded `add constraint`, `create or replace function`, `on conflict do nothing`
5. **No hard delete** — ยกเลิก = เปลี่ยนสถานะ / soft `is_active=false`; unlink = ลบเฉพาะแถวลิงก์ ไม่ลบเอกสารจริง
6. **Audit best-effort** — insert `audit_logs` ใน `begin ... exception when others then null; end;`
7. **ไม่ automate ราชการ** — ไม่เชื่อม/ไม่ scrape/ไม่ยื่นแทน e-WorkPermit; เลขราชการทั้งหมดพิมพ์เอง (optional)

---

## A) Current Confirmed Backend Inventory (ตรวจแล้ว ณ HEAD cf8b7ed)

Legend สถานะฟิลด์: **[U]** usable now · **[P]** partial (มีโครง แต่ยังไม่ครบ/ยังไม่กรอก) · **[M]** missing (ยังไม่มี) · **[N]** should remain manual/note for now

### A.1 `customers` (master เดิม — Phase 1)
สร้างนอกโฟลเดอร์ migration นี้ (ระบบเดิม). ฟิลด์ที่ Phase 2 อ้างถึงและยืนยันว่ามีจริง:
`id, name, passport_no, alien_id, wp_no, employer_id, deleted_at (soft delete), phone, nationality, work_status, exp_visa, exp_wp, next_90`
- [U] ใช้เป็น "แรงงานหลัก/แรงงานที่แสดง" ของเคส (`cases.customer_id`)
- [N] **ไม่แตะแถว customers ในทุกงาน case** — Phase 2 อ่านอย่างเดียว

### A.2 `employers` (master เดิม + ขยาย 54A-5 / `20260804`)
- เดิม: `id, name, business_type, phone, contact_person, address, note, updated_at`
- เพิ่ม (additive): `employer_kind [U]` (default 'company', CHECK company/individual/other), `registration_no [U], tax_id [U], contact_email [U], line_id [U], subdistrict/district/province/postcode [U], business_description [U], authorized_signatory [U], authorized_signatory_position [U], phase2_note [U], updated_by_code [U]`

### A.3 `establishments` (54A-5 / `20260804`)
`id, employer_id (FK, no-cascade/restrict), establishment_code, name, branch_name, address_line, subdistrict, district, province, postcode, contact_person, contact_phone, note, is_active, created_at, created_by_code, updated_at, updated_by_code`
- [U] เขียนผ่าน `app_save_establishment` / `app_set_establishment_active` (admin toggle)
- [P] ยังไม่ผูกเข้ากับ `cases` (ไม่มี `cases.establishment_id`) — ดู F

### A.4 `cases` (54A-3 / `20260802`)
`id, case_code (CASE-YYYYMMDD-nnnnnn), customer_id [U], employer_id [U] (null-able, snapshot ตอนสร้าง), template_id [U], template_code [U], case_title, case_category [U] (CHECK ขยาย registration_resolution ใน 20260809), case_status [U] (9 ค่า), priority [U], assigned_to_code [U], ewp_request_no [P] (พิมพ์เอง), due_date [U], submitted_at [U], completed_at [U], cancelled_at [U], note, created_by_code, updated_by_code, timestamps`
- [M] ยังไม่มี: `mou_side, establishment_id, start_date, out_date, out_reason, work_location, name_list_status, submit_result_note, returned_doc_status, official_reply_status` (ดู F)
- **หมายเหตุ:** `customer_id/employer_id` ตั้งใจไม่มี FK (customers ใช้ soft delete)

### A.5 `case_status_logs` (54A-3) — [U] ประวัติสถานะ append โดย RPC

### A.6 `case_templates` (54A-2 / `20260801` + metadata 54A-9A / `20260808`)
- core: `id, template_code (unique), template_name_th/en, category [U], description, default_case_status, is_active, sort_order, timestamps`
- metadata (20260808): `cabinet_resolution_refs jsonb[] [P], law_refs jsonb[] [P], form_refs jsonb[] [P], eligibility_note [P], internal_guidance [P], process_summary [P], source_note [P], updated_by_code`
- [U] seed 16 แม่แบบ (INTERNAL DRAFT) · 5 แม่แบบมี content ที่อนุมัติแล้วรอ apply (ดู B)

### A.7 `case_template_checklist_items` (54A-2)
`id, template_id (FK cascade), item_code, item_name_th [U], item_name_en [P], doc_type [P], is_required [U], required_from [U] (CHECK worker/employer/establishment/case/payment/internal), note, sort_order, is_active, timestamps` · unique(template_id, item_code)
- [P] seed เป็นเช็คลิสต์ **generic** — ยังไม่ใช่เนื้อหาจริงรายแม่แบบ (ดู B)

### A.8 `case_checklist_items` (54A-4 / `20260803`) — instance ต่อเคส
`id, case_id (FK cascade), template_item_id (FK set null), item_code, item_title_th, item_title_en, doc_type, required_from [P], is_required, checklist_status [U] (missing/received/reviewing/approved/needs_fix/waived/not_required), sort_order, note, checked_by_code, checked_at, timestamps`
- คัดลอกจากแม่แบบผ่าน `app_init_case_checklist` (idempotent)
- [P] `required_from` คัดลอกมาแต่ยังไม่ถูกใช้จัดกลุ่ม readiness รายเจ้าของในระดับ UI จริง

### A.9 `case_documents` (54A-4) — ลิงก์เอกสาร↔เช็คลิสต์
`id, case_id, case_checklist_item_id (null-able), document_id (FK cascade), link_note, linked_by_code, created_at`
- [U] `app_link_case_document` / `app_unlink_case_document`
- [P] **ตรวจ ownership เฉพาะ customer/case** เท่านั้น (ดู E) — ยังลิงก์เอกสาร employer/establishment ไม่ได้

### A.10 `documents` (master เดิม + generalization 54A-1B / `20260731`)
- เดิม: `id, customer_id, doc_type, doc_name, file_type, mime_type, file_size, uploaded_by, source, doc_expiry, doc_status, doc_note, storage_bucket, storage_path (ไม่คืนออก), created_at`
- เพิ่ม: `owner_type [P]` (not null default 'customer', CHECK customer/employer/establishment/case), `owner_id bigint [P]` (null-able)
- [N] **ไม่ backfill แถวเดิม** — แถวเก่า owner_type='customer', owner_id=null, ถือ `owner_id ≡ customer_id`
- `app_list_documents` รองรับ `p_owner_type / p_owner_id` แล้ว (metadata-only)

### A.11 `case_payments` (54A-6A / `20260805`)
`id, case_id, payment_code, payment_type [U] (7 ค่า), payment_title, amount_due, amount_paid, payment_status [U] (7 ค่า), due_date, paid_at, proof_document_id [U] (FK set null), note, is_active, timestamps`
- [U] proof เชื่อมผ่าน `proof_document_id` เท่านั้น + ตรวจ ownership (case_documents / customer / case)

### A.12 `case_appointments` (54A-6B / `20260806`)
`id, case_id, appointment_type [U] (9 ค่า), appointment_title, appointment_status [U] (5 ค่า), appointment_date, appointment_time, location, officer_or_contact, note, result_note, completed_at, cancelled_at, timestamps`
- [U] ไม่มีไฟล์แนบ (note-only by design)

### A.13 `case_tracking_logs` (54A-7B / `20260807`) — append-only
`id, case_id, tracking_type [U] (ewp/government_office/phone/onsite/internal), gov_status_text [U] (พิมพ์เอง), note, evidence_document_id [U] (FK set null), next_check_date, tracked_at, created_by_code, created_at`
- [U] `app_add_case_tracking_log` (ไม่มี edit/delete) + ตรวจ ownership เดียวกับ payment

### สรุปช่องว่างหลัก (gap summary)
| ต้องการสำหรับ Phase 2 จริง | สถานะ |
|---|---|
| เนื้อหาเช็คลิสต์จริงรายแม่แบบ (แทน generic) | [P] apply script รอ COMMIT (5 แม่แบบ metadata; **checklist items ยังไม่ทำ**) |
| หลายแรงงานต่อเคส (Name List) | [M] ยังไม่มี `case_workers` |
| ลิงก์เอกสาร employer/establishment เข้าเคส | [P] โครง owner_* พร้อม แต่ RPC ยังไม่ตรวจให้ผ่าน |
| `cases.mou_side` (41 vs 46) | [M] |
| `cases.establishment_id` | [M] |

---

## B) Real Checklist Template Content Contract

> เป้าหมาย: แทน checklist "generic" (passport / photo / employer_documents / payment_receipt / appointment / result_note) ด้วยรายการจริงรายแม่แบบ
> **ต้องไม่ตัดสินความถูกต้องทางกฎหมายเอง** — ทุกอย่างไม่ชัด = `NEED_REVIEW` (staff-facing wording เท่านั้น)

### B.0 กลไกที่ใช้ (ยืนยันแล้ว)
- โครงตาราง `case_template_checklist_items` รองรับครบ: `item_code, item_name_th, item_name_en, sort_order, is_required, required_from (6 ค่า), doc_type, note`
- **status badge wording** = mapping จาก `checklist_status` ของ instance (ไม่ใช่ของ template): missing→"ยังไม่มีเอกสาร", received→"ได้รับแล้ว", reviewing→"กำลังตรวจ", approved→"ครบถ้วน", needs_fix→"ต้องแก้ไข", waived→"ยกเว้น", not_required→"ไม่ต้องใช้"
- **readiness note** = `internal_guidance` / `note` ต่อ item (staff-facing)
- วิธี apply เนื้อหา: ผ่าน RPC `app_admin_save_case_template_item` (audited, admin-only) ในสคริปต์ dry-run/ROLLBACK **นอก** `supabase/migrations/` (pattern เดียวกับ `APPLY_CASE_TEMPLATE_APPROVED_CONTENT_20260704.sql`)

### B.1 MOU_MYANMAR_NEW / MOU_LAOS_NEW / MOU_CAMBODIA_NEW (โครงเดียวกัน 3 สัญชาติ)
Status worksheet: `READY_TO_ENTER_CRM` (เฉพาะช่องยืนยัน · ค่าธรรมเนียม/มติ = NEED_REVIEW)
เช็คลิสต์จริงที่เสนอ (draft — ยืนยันกับเจ้าของก่อน apply):

| item_code | item_name_th | sort | required | owner (required_from) | doc_type | readiness note | สถานะ |
|---|---|---|---|---|---|---|---|
| passport_or_ci | พาสปอร์ต / CI ของแรงงาน | 10 | ✓ | worker | passport | ต่อแรงงานแต่ละคน | usable now |
| worker_photo | รูปถ่ายแรงงาน | 20 | ✓ | worker | photo | 3x4 ซม. (ยืนยันขนาดกับแหล่ง) | NEED_REVIEW (ขนาด) |
| name_list_certified | Name List รับรองจากประเทศต้นทาง | 25 | ✓ | case | — | ต้องได้ก่อนยื่น บต.31/33 | usable now |
| company_certificate | หนังสือรับรองบริษัทนายจ้าง | 32 | ✓ | employer | — | ต่อ 1 นายจ้าง | needs backend later (E) |
| power_of_attorney | หนังสือมอบอำนาจ | 34 | ✓ | employer | — | — | needs backend later (E) |
| demand_letter_nj2 | คำร้องนำเข้า (นจ.2) | 40 | ✓ | case | — | ยื่นขั้นนำเข้า | usable now |
| medical_certificate | ใบรับรองแพทย์ | 50 | ✓ | worker | — | เมื่อคนต่างด้าวเข้าประเทศ | usable now |
| employment_contract | สัญญาจ้าง | 55 | ✓ | employer | — | — | usable now |
| payment_receipt | หลักฐานการชำระเงิน | 70 | ✓ | payment | receipt | ค่าธรรมเนียม = NEED_REVIEW | usable now |
| appointment_date | วันนัด/วันยื่น (ศูนย์แรกรับ) | 80 | ✗ | case | — | — | usable now |
| submit_result_note | หมายเหตุผลการยื่น | 90 | ✗ | internal | — | — | usable now |

- มาตราอ้างอิง (จาก worksheet, **staff note ภายในเท่านั้น ไม่ตัดสินกฎหมาย**): ม.41 (สายบริษัทนำเข้า), ม.46 (สายนายจ้าง), ม.43 (แจ้งส่งมอบ) → ผูกกับ `mou_side` ใน C
- MOU **ไม่ใช่งานมติ ครม.** → ไม่มี cabinet refs

### B.2 EMPLOYER_NOTIFICATION_OUT (แจ้งแรงงานออก)
Status: `READY_TO_ENTER_CRM` (กรอบเวลาแจ้ง = NEED_REVIEW)

| item_code | item_name_th | sort | required | owner | doc_type | สถานะ |
|---|---|---|---|---|---|---|
| worker_passport | พาสปอร์ต/CI แรงงาน | 10 | ✓ | worker | passport | usable now |
| work_permit_current | ใบอนุญาตทำงาน (เดิม) | 20 | ✓ | worker | work_permit | usable now |
| bt53_out_form | แบบแจ้งออก (บต.53) | 30 | ✓ | case | — | usable now |
| resignation_or_termination | หลักฐานลาออก/เลิกจ้าง | 40 | ✓ | employer | — | needs backend later (E) |
| company_certificate | หนังสือรับรองบริษัท | 50 | ✓ | employer | — | needs backend later (E) |
| power_of_attorney | หนังสือมอบอำนาจ | 55 | ✗ | employer | — | needs backend later (E) |
| submit_result_note | หมายเหตุผลการยื่น | 90 | ✗ | internal | — | usable now |

- มาตรา: ม.13 วรรคหนึ่ง / ม.46 วรรคสาม · แบบฟอร์ม บต.53 · **กรอบเวลาแจ้งหลังพนักงานออก = NEED_REVIEW**

### B.3 EMPLOYER_NOTIFICATION_IN (แจ้งแรงงานเข้า)
Status: `PARTIAL_INTERNAL` — เจ้าของยืนยัน = แจ้งเข้า แต่ **มาตรา/แบบฟอร์ม/มติ = NEED_REVIEW** (ไฟล์ P01/P07 ปนถ้อยคำ บต.53/แจ้งออก)

| item_code | item_name_th | sort | required | owner | doc_type | สถานะ |
|---|---|---|---|---|---|---|
| worker_passport | พาสปอร์ต/CI แรงงาน | 10 | ✓ | worker | passport | usable now |
| work_permit_or_approval | ใบอนุญาต/หลักฐานอนุญาตทำงาน | 20 | ✓ | worker | — | NEED_REVIEW |
| notify_in_form | แบบแจ้งเข้าทำงาน | 30 | ✓ | case | — | **NEED_REVIEW (รหัสแบบฟอร์ม — ห้ามเดา)** |
| company_certificate | หนังสือรับรองบริษัท | 50 | ✓ | employer | — | needs backend later (E) |
| power_of_attorney | หนังสือมอบอำนาจ | 55 | ✗ | employer | — | needs backend later (E) |
| submit_result_note | หมายเหตุผลการยื่น | 90 | ✗ | internal | — | usable now |

- ⚠️ `notify_in_form` **ต้องให้คนตรวจยืนยันรหัสแบบฟอร์มก่อน finalize** — worksheet เตือน "บต.53 เป็นแบบของออก"

### B.4 แม่แบบอื่นที่ยังไม่พร้อม (คง generic / manual only)
CI_MYANMAR (deferred → registration_resolution family), VISA_WP_RENEWAL / WP_RENEWAL (NEED_OCR P10), VISA_RENEWAL / REPORT_90_DAYS / HEALTH_INSURANCE (NEED_SOURCE), CHANGE_EMPLOYER(_URGENT) (PARTIAL), WORKER_DOCUMENT_FIX / PASSPORT_UPDATE / OTHER_LABOR_DOCUMENT (PARTIAL/internal) → **คงเช็คลิสต์ generic เดิมไว้ก่อน จนกว่าจะมีแหล่งตรวจแล้ว**

---

## C) MOU มาตรา 41 (บริษัทนำเข้ายื่น) vs มาตรา 46 (นายจ้างยื่นเอง)

### C.1 คำถามหลัก: template แยก หรือ metadata field?
**คำแนะนำที่ปลอดภัย (เลือก option B): เพิ่ม field `cases.mou_side`** ไม่แตกเป็น 6 แม่แบบ

| ทางเลือก | ข้อดี | ข้อเสีย |
|---|---|---|
| A) แยก 6 แม่แบบ (MOU_MYANMAR_M41, _M46, ...) | filter ชัด | seed บวม 2 เท่า · เนื้อหาซ้ำ · แก้ที่เดียวไม่ได้ |
| **B) 1 แม่แบบ/สัญชาติ + `cases.mou_side` (41/46)** ✅ | ข้อมูลกลางที่เดียว · เพิ่ม/ลบ item ตาม side ได้ · worksheet ผูก ม.41/46 อยู่แล้ว | ต้อง logic แสดง/ซ่อน item ตาม side |

### C.2 ข้อจำกัดปัจจุบัน
- ยังไม่มีวิธีระบุ 41 vs 46 เลย — เคส MOU ทุกอันเหมือนกันหมด
- checklist instance คัดลอกทุก item จาก template โดยไม่รู้ side

### C.3 create-case จะรู้ 41 vs 46 ได้อย่างไร (อนาคต — ไม่ implement)
- เพิ่มพารามิเตอร์ `p_mou_side text default null` ให้ `app_create_case` → เขียน `cases.mou_side` (CHECK '41'/'46'/null)
- ตอน `app_init_case_checklist`: ถ้า template เป็น MOU และ `mou_side` มีค่า → คัดลอกเฉพาะ item ที่ตรง side (ต้องมี field แยก side บน template item — ดูล่าง)

### C.4 item ที่ต่าง / ที่ร่วม (draft — NEED_REVIEW ทางกฎหมาย)
- **ร่วม (ทั้ง 41 และ 46):** passport_or_ci, worker_photo, name_list_certified, medical_certificate, employment_contract, payment_receipt, appointment_date, demand_letter_nj2
- **เฉพาะสาย 41 (บริษัทนำเข้า):** บต.31 (คำขออนุญาตทำงานแทนฯ สายบริษัทนำเข้า)
- **เฉพาะสาย 46 (นายจ้างยื่นเอง):** บต.33 (คำขออนุญาตทำงานแทนฯ สายนายจ้าง)
- ม.43 (บต.13 แจ้งส่งมอบ MoU) = ขั้นตอนต่อเนื่อง (ยืนยัน side กับเจ้าของ)
- กลไกเสนอ: เพิ่มคอลัมน์ `case_template_checklist_items.mou_side text null` (CHECK 41/46/null; null=ร่วม) — additive, filter ตอน init

> ❗ ห้าม implement ใน 58F — เป็นแผนเท่านั้น · การจับคู่ item↔side ต้องให้เจ้าของยืนยัน

---

## D) `case_workers` / Name List Plan (หลายแรงงานต่อเคส)

### D.1 ตารางเสนอ (additive only — ไม่แตะ cases/customers)
```
public.case_workers
  id              bigserial pk
  case_id         bigint not null references cases(id) on delete cascade
  customer_id     bigint not null            -- อ้าง customers (ไม่ FK — customers ใช้ soft delete เหมือน cases.customer_id)
  role            text not null default 'worker'   -- CHECK worker/... (ขยายภายหลัง)
  name_list_seq   integer null               -- ลำดับใน Name List
  note            text null
  is_active       boolean not null default true
  created_at      timestamptz not null default now()
  created_by_code text null                   -- ตาม pattern created_by_code เดิม (auth ปัจจุบันรองรับ)
  -- unique (case_id, customer_id) where is_active  → กันเพิ่มซ้ำ
```

### D.2 กติกา
1. หนึ่งเคสมีได้หลายแรงงาน (1..N)
2. `cases.customer_id` = **แรงงานหลัก/แสดง** — คงไว้เพื่อ backward compatibility (หน้าเดิมทั้งหมดยังทำงาน)
3. MOU Name List อ่านจาก `case_workers`
4. readiness ต้องนับเอกสาร required **ต่อแรงงานแต่ละคน** (ต้องผูก case_checklist_items/case_documents กับ worker — ดู D.4)
5. เคสเดี่ยวเดิมยังทำงาน: migration แบบ additive; **ไม่ backfill บังคับ** (ทางอ่าน: ถ้าไม่มีแถว case_workers → ใช้ cases.customer_id เป็นแรงงานเดียว)
6. migration additive ล้วน — ไม่มี DROP/RENAME/UPDATE แถวเดิม

### D.3 RPC เสนอ (อนาคต — ไม่ implement)
- `app_add_case_worker(p_user, p_case_id, p_customer_id, p_role, p_name_list_seq, p_note)` — ตรวจ case มีจริง + customer ไม่ soft-deleted
- `app_list_case_workers(p_user, p_case_id)` — metadata แรงงาน + นับ required docs ต่อคน
- `app_remove_case_worker(p_user, p_case_worker_id)` — soft `is_active=false` (ไม่ hard delete) · **ห้ามลบแรงงานหลักถ้ายังเป็น cases.customer_id**

### D.4 ผลกระทบ readiness รายแรงงาน (ต้องตัดสินใน stage หลัง)
- ทางเลือก 1: เพิ่ม `case_checklist_items.case_worker_id null` → เช็คลิสต์แยกรายคน (ตรงที่สุด แต่ instance บวม)
- ทางเลือก 2: เช็คลิสต์ระดับเคส + `case_documents.case_worker_id null` เพื่อระบุว่าเอกสารเป็นของใคร
- **เสนอเริ่มด้วยทางเลือก 2** (เบากว่า, ไม่แตะ init logic เดิม) — ยืนยันกับเจ้าของ

---

## E) Multi-owner Document Linking RPC Contract

### E.1 สถานะปัจจุบัน (`app_link_case_document` 54A-4)
ตรวจ ownership อนุญาตเฉพาะ:
```
d.customer_id = cases.customer_id
OR (d.owner_type='customer' AND d.owner_id = cases.customer_id)
OR (d.owner_type='case'     AND d.owner_id = cases.id)
```
→ เอกสาร **employer / establishment ลิงก์ไม่ได้** (raise `document_not_allowed`)

### E.2 การตรวจ validation ที่เสนอ (อนาคต — ไม่ implement)
ขยายเงื่อนไข ownership (ยังคง raise `document_not_allowed` ถ้าไม่ผ่าน):

| ประเภทเอกสาร | เงื่อนไขที่ต้องผ่าน |
|---|---|
| customer doc | `d.customer_id = cs.customer_id` **หรือ** (มี case_workers) `d.customer_id IN (select customer_id from case_workers where case_id = cs.id and is_active)` **หรือ** owner_type='customer' owner_id ตรงชุดเดียวกัน |
| case doc | `d.owner_type='case' AND d.owner_id = cs.id` |
| employer doc | `d.owner_type='employer' AND d.owner_id = cs.employer_id` (cs.employer_id ต้องไม่ null) |
| establishment doc | `d.owner_type='establishment' AND d.owner_id IN (select s.id from establishments s where s.employer_id = cs.employer_id)` **และ/หรือ** `= cs.establishment_id` (ถ้าเพิ่ม field ใน F) |
| payment proof | คงไหลผ่าน `case_payments.proof_document_id` เท่านั้น (ตรวจ ownership เดิม) — ไม่เปิดช่องใหม่ |
| tracking/returned doc | คงไหลผ่าน `case_tracking_logs.evidence_document_id` เท่านั้น (ตรวจ ownership เดิม) |

### E.3 ข้อบังคับความปลอดภัย (ห้ามละเมิด)
- ❌ ไม่คืน/ไม่เปิดเผย `storage_path` / signed URL / base64 — เปิดไฟล์ผ่าน `dcOpenDoc` / document_id flow เดิมเท่านั้น
- ❌ ไม่อนุญาต arbitrary `owner_id` — ต้องพิสูจน์ความเชื่อมโยงกับเคส (employer ของเคส / establishment ใต้ employer ของเคส) ทุกครั้ง
- ❌ ไม่ลดทอน `security definer` identity check (staff/admin active)
- ✅ คงกติกา idempotent (`on conflict do nothing`, already_linked) และ auto missing→received เดิม

### E.4 การเปลี่ยน signature
- **ไม่เปลี่ยน signature จริงใน 58F** — เมื่อทำจริง: `create or replace` body เดิม เพิ่มเฉพาะ OR-clause (พารามิเตอร์เดิมครบ ลำดับเดิม) → frontend ไม่ต้องแก้

---

## F) Case Fields Contract

| field | Classification | หมายเหตุ |
|---|---|---|
| `ewp_request_no` | **already exists** (cases 54A-3) | พิมพ์เอง optional |
| `submitted_at` | **already exists** (cases 54A-3) | stamp ตอนสถานะ submitted |
| `mou_side` | **add in backend foundation** | text CHECK '41'/'46'/null — ผูก C · ต้องอัปเดต `app_create_case` (+arg) |
| `establishment_id` | **add in backend foundation** | bigint null (ไม่ FK cascade / restrict) — ผูก establishment เข้าเคส; ปลดล็อก E establishment doc |
| `start_date` | **note/manual for now** | ใช้ due_date/appointment ได้ก่อน |
| `out_date` | **defer until real need** | เกี่ยวงานแจ้งออก — ใช้ appointment/tracking แทนได้ |
| `out_reason` | **defer until real need** | ใช้ note/appointment result_note แทนได้ |
| `work_location` | **note/manual for now** | จะได้จาก establishment เมื่อผูกแล้ว |
| `name_list_status` | **add เมื่อทำ D** | text — สถานะ Name List (draft/certified/submitted) |
| `submit_result_note` | **note/manual for now** | มี checklist item + tracking รองรับแล้ว |
| `returned_doc_status` | **defer** | ใช้ `case_tracking_logs` (evidence_document_id) แทนได้ |
| `official_reply_status` | **defer** | ใช้ `case_tracking_logs.gov_status_text` แทนได้ |

> หลักการ: เพิ่มเฉพาะ `mou_side` + `establishment_id` ใน foundation (ปลดล็อก C/E) — ที่เหลือ defer จนมีความจำเป็นจริง เพื่อไม่ให้ schema บวม

---

## G) Draft SQL Sections (สรุป — เนื้อหาเต็มในไฟล์ .sql)
ดูไฟล์ `DRAFT_PHASE2_BACKEND_SQL_58F_DO_NOT_APPLY.sql` ในโฟลเดอร์เดียวกัน — แบ่ง 7 ส่วน (comment ล้วน ห้ามรัน):
1. Backup queries / snapshot notes
2. Additive schema draft: `case_workers`
3. Additive fields draft: `cases.mou_side`, `cases.establishment_id`, `case_template_checklist_items.mou_side`
4. Draft `app_link_case_document` validation update (เพิ่ม OR-clause employer/establishment)
5. Draft checklist content update/insert approach (ผ่าน `app_admin_save_case_template_item`, dry-run/ROLLBACK)
6. Draft rollback outline
7. Draft verification queries

---

## H) Staging Verification Plan (ทำเมื่อถึง stage apply จริง)
1. [ ] **Backup ก่อน apply** — snapshot `case_templates`, `case_template_checklist_items`, `cases`, `case_documents` (นับแถว + checksum); เปิด transaction/PITR window
2. [ ] **Apply บน staging เท่านั้น** — ห้าม production
3. [ ] สร้างเคส MOU (`app_create_case` + mou_side ถ้าทำ C)
4. [ ] `app_init_case_checklist` — ตรวจ item จริงถูกคัดลอก (นับตรง, ไม่ duplicate เมื่อรันซ้ำ)
5. [ ] แนบเอกสาร worker → `app_link_case_document` ผ่าน (customer doc)
6. [ ] แนบเอกสาร case (owner_type='case') → ผ่าน
7. [ ] **ก่อน RPC update:** แนบ employer doc → ต้อง **ถูกปฏิเสธ** (`document_not_allowed`)
8. [ ] **หลัง RPC update (approved):** แนบ employer doc ของ employer เจ้าของเคส → ผ่าน
9. [ ] แนบ employer doc ของ **employer อื่น** → ต้อง **ถูกปฏิเสธ**
10. [ ] ตรวจ response ทุก RPC — **ไม่มี** storage_path/signed URL/base64 (มีแค่ has_storage)
11. [ ] ทดสอบ rollback — ROLLBACK แล้วค่าตารางกลับเดิม (เทียบ snapshot ข้อ 1)
12. [ ] ตรวจหน้า Phase 1 (customers/documents/attendance/LINE inbox/login) ยังทำงานปกติ
13. [ ] case_workers: เพิ่ม 2 แรงงาน, เคสเดี่ยวเดิม (ไม่มีแถว) ยังแสดงแรงงานหลักถูกต้อง

---

## I) Recommended Next Stages After 58F
- **58G** — Backup + staging test runbook (เอกสารเท่านั้น, no code)
- **58H** — Additive backend foundation (`mou_side`, `establishment_id`, `case_template_checklist_items.mou_side`) — approved only
- **58I** — Apply approved real checklist content (5 แม่แบบ B.1–B.3) ผ่าน apply-script dry-run/ROLLBACK
- **58J** — `case_workers` / Name List backend + UI foundation
- **58K** — multi-owner document linking RPC (E) + เปิดใช้ฝั่ง frontend
- **58L** — extra case fields (F: name_list_status ฯลฯ) ถ้ายังจำเป็น
- **58M** — production verification gate

---

## J) Hard Stops (ย้ำ — ห้ามข้าม)
- ❌ ไม่ทำ user test 2–3 คน จนกว่าระบบพร้อมพอสำหรับ rollout 12 users
- ❌ ไม่ auto-submit ไป e-WorkPermit
- ❌ ไม่เชื่อมต่อระบบราชการโดยตรง
- ❌ ไม่ automate การออกเอกสารราชการ
- ❌ ไม่มี OCR/AI assist
- ❌ ไม่มี Customer Upload Portal / PWA
- ❌ ไม่รัน SQL ใน 58F
- ❌ ไม่เปลี่ยน production DB
- ❌ ไม่สร้าง migration ใต้ `supabase/migrations/` ใน 58F
- ❌ ไม่ทำ backend implementation ใด ๆ โดยไม่มี backup + การอนุมัติ

---

*จบร่างสัญญา 58F — planning only. ไม่มีการรัน SQL, ไม่แตะ DB, ไม่แก้ app code, ไม่ commit จนกว่าเจ้าของอนุมัติ*
