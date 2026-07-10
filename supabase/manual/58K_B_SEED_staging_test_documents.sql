-- =====================================================================
-- ███  STAGING ONLY  ███
-- STAGE 58K-B-SEED-A — Metadata-only synthetic test documents (TEST_58K_)
--
--   Target project : rungfar-crm-staging
--   Project ref    : bzwtknqvhvdmatangzqf
--
--   ██ DO NOT APPLY TO PRODUCTION ██
--   ██ DO NOT APPLY TO: magwqolbjmwymqxelizl ██
--     (การอ้างถึง ref ของ production ปรากฏ "เฉพาะในคอมเมนต์คำเตือนนี้" เท่านั้น
--      ห้ามมี ref production ใน SQL ที่รันจริงโดยเด็ดขาด)
--
--   * Metadata-only synthetic test data — file_data / storage_bucket /
--     storage_path เป็น null ทั้งหมด ❌ ไม่มีไฟล์จริง ไม่มี Storage object
--   * ❌ ไม่มีข้อมูลลูกค้าจริง / ไฟล์ลูกค้าจริง / ข้อมูลที่คัดลอกจาก production
--   * Manual execution only — รันด้วยมือใน SQL Editor ของ staging เท่านั้น
--   * ต้อง backup/export ก่อน apply เสมอ
--   * Cleanup block (SECTION 8) ถูกคอมเมนต์ไว้ทั้งบล็อก — ไม่รันอัตโนมัติ
--
--   สิ่งที่สคริปต์นี้ทำ (ทั้งหมดอยู่ใน 1 transaction):
--     - ตรวจ precondition ลายนิ้วมือ staging อย่างเข้ม (ผิด = abort ทั้งหมด)
--     - insert แถว metadata-only ลง public.documents 5 แถว (idempotent)
--   สิ่งที่สคริปต์นี้ "ไม่ทำ":
--     - ❌ ไม่ update/delete แถวใด ๆ ที่มีอยู่เดิม
--     - ❌ ไม่ insert ตารางอื่นนอกจาก public.documents
--     - ❌ ไม่สร้าง case_documents (ลิงก์ทำผ่าน UI ใน 58K-B3 เท่านั้น)
--     - ❌ ไม่แตะ cases / customers / employers / case_workers / checklist
--     - ❌ ไม่มี DDL / grant / revoke / RLS / function / sequence / Storage
--
--   อ้างอิงแผน: 58K-B-SEED-RESET-1 audit → decision
--     SAFE_TO_DRAFT_STAGING_METADATA_SEED_SCRIPT_NEXT
-- =====================================================================


-- =====================================================================
-- SECTION 0 — OPERATOR CHECKLIST (comments only — ตรวจก่อนรันทุกครั้ง)
-- =====================================================================
-- [ ] 1. URL ของ SQL Editor ในเบราว์เซอร์ต้องมี:  bzwtknqvhvdmatangzqf
-- [ ] 2. URL ต้อง "ไม่มี" ref ของ production (ดูคำเตือนหัวไฟล์)
-- [ ] 3. ทำ export/backup ของ staging เรียบร้อยแล้ว (อย่างน้อย: documents,
--        case_documents, cases, customers, employers, case_workers)
-- [ ] 4. สร้าง synthetic rows ผ่าน UI ที่รองรับ "ก่อน" รันสคริปต์นี้:
--        - ลูกค้า:   TEST_58K_UNRELATED_CUSTOMER   (ลูกค้าสังเคราะห์ ไม่เกี่ยวกับเคสใด)
--        - นายจ้าง:  TEST_58K_EMPLOYER             (ผ่านหน้านายจ้าง / app_save_employer)
--        - ลูกค้า:   TEST_58K_EMP_WORKER           (ผูกนายจ้าง TEST_58K_EMPLOYER ในฟอร์มลูกค้า)
--        - เคสทิ้งได้: case_title = TEST_58K_EMPLOYER_CASE
--          (สร้างเคสใหม่ให้ TEST_58K_EMP_WORKER — app_create_case จะคัดลอก employer_id
--           ของลูกค้าเข้าเคสให้เอง — ❌ ห้ามแก้เคสเดิม)
-- [ ] 5. เคสเดิมยังอยู่ครบ:  CASE-20260709-000001 (17 รายการเช็กลิสต์, แรงงาน 2 คน)
--
-- ถ้าข้อใดไม่ผ่าน — หยุด อย่ารันสคริปต์นี้
-- =====================================================================


-- =====================================================================
-- SECTION 1 + 2 + 3 + 4 — TRANSACTION: preconditions → resolve IDs → seed
--   ทุก assertion ใช้ raise exception → transaction abort ทั้งก้อน (all-or-nothing)
--   ❌ ไม่มี hardcoded numeric id — resolve จาก marker เฉพาะทางเท่านั้น
-- =====================================================================
begin;

do $$
declare
  -- ── SECTION 2: runtime-resolved IDs (ห้าม hardcode) ──
  v_admin_username          text := 'leejunkik2';
  v_admin_id                bigint;
  v_original_case_id        bigint;
  v_original_case_cust      bigint;
  v_primary_customer_id     bigint;
  v_secondary_customer_id   bigint;
  v_primary_case_worker_id  bigint;
  v_secondary_case_worker_id bigint;
  v_unrelated_customer_id   bigint;
  v_employer_id             bigint;
  v_employer_customer_id    bigint;
  v_employer_case_id        bigint;
  -- ── ตัวช่วยตรวจนับ ──
  v_cnt   integer;
  v_txt   text;
  r_doc   record;
begin

  -- ═══════════ SECTION 1.A — ตารางที่ต้องมี ═══════════
  if to_regclass('public.documents')    is null then raise exception 'PRECONDITION FAILED: table public.documents missing';    end if;
  if to_regclass('public.customers')    is null then raise exception 'PRECONDITION FAILED: table public.customers missing';    end if;
  if to_regclass('public.cases')        is null then raise exception 'PRECONDITION FAILED: table public.cases missing';        end if;
  if to_regclass('public.case_workers') is null then raise exception 'PRECONDITION FAILED: table public.case_workers missing (58H not applied?)'; end if;
  if to_regclass('public.app_users')    is null then raise exception 'PRECONDITION FAILED: table public.app_users missing';    end if;
  if to_regclass('public.employers')    is null then raise exception 'PRECONDITION FAILED: table public.employers missing';    end if;
  -- 58K-B-SEED-FIX-1 (O3): สคริปต์อ่าน case_documents ตอน assert ว่า seed ไม่สร้างลิงก์ — ต้องมีตาราง (20260803)
  if to_regclass('public.case_documents') is null then raise exception 'PRECONDITION FAILED: table public.case_documents missing (apply 20260803 first)'; end if;

  -- ═══════════ SECTION 1.B — คอลัมน์ documents ที่สคริปต์นี้พึ่งพา ═══════════
  -- 58K-B-SEED-FIX-1 (O1): เพิ่ม doc_note/doc_expiry/doc_status (INSERT อ้างถึง — ขาดต้อง abort แบบ precondition ชัด ๆ)
  select count(*) into v_cnt
  from information_schema.columns
  where table_schema='public' and table_name='documents'
    and column_name in ('id','customer_id','doc_type','doc_name','file_data',
                        'storage_bucket','storage_path','source','owner_type',
                        'owner_id','uploaded_by','doc_note','doc_expiry','doc_status');
  if v_cnt <> 14 then
    raise exception 'PRECONDITION FAILED: public.documents missing required columns (found %/14) — apply 20260630/20260703/20260706/20260731 first', v_cnt;
  end if;

  -- 58K-B-SEED-FIX-2: schema จริงบน staging ยืนยันแล้วว่า documents.customer_id เป็น NOT NULL
  --   (ตาราง documents สร้างก่อนยุค migration ในรีโป — ทุกเอกสารต้องมี customer parent เสมอ)
  --   → seed ทุกแถวจึง "ใส่ customer_id เสมอ" รวมถึงแถว case/employer:
  --     - แถว case:     customer_id = ลูกค้าเจ้าของเคสเดิม (parent context)
  --     - แถว employer: customer_id = TEST_58K_EMP_WORKER (parent context)
  --   ⚠️ ownership/authorization ยังยึด owner_type + owner_id ตามเดิมทุกประการ —
  --     customer_id เป็นเพียง parent/customer context ไม่เปลี่ยนเจตนาความเป็นเจ้าของ
  --   (ไม่ abort ไม่ว่า customer_id จะ nullable หรือไม่ — สคริปต์ใส่ค่าให้ครบทุกแถวอยู่แล้ว)

  -- file_data ต้อง nullable (metadata-only) — 20260701
  select is_nullable into v_txt from information_schema.columns
  where table_schema='public' and table_name='documents' and column_name='file_data';
  if v_txt <> 'YES' then
    raise exception 'PRECONDITION FAILED: documents.file_data is NOT NULL — apply 20260701_documents_file_data_nullable first';
  end if;

  -- คอลัมน์บังคับ (NOT NULL ไม่มี default) ที่สคริปต์ "ไม่ได้ใส่ค่า" → ต้องไม่มีเลย
  --   ค่าที่สคริปต์ใส่เอง (non-null เสมอ): customer_id, doc_type, doc_name, uploaded_by,
  --   source, owner_type (58K-B-SEED-FIX-2: customer_id ใส่ครบทุกแถวแล้ว — schema จริง NOT NULL)
  --   owner_id ใส่ non-null ทุกแถวเช่นกัน; doc_note/doc_status/doc_expiry ใส่ (บางค่า null ตามดีไซน์)
  --   หมายเหตุ created_at: ถ้า NOT NULL โดยไม่มี default จะติดเงื่อนไขนี้และ abort
  --   (ตั้งใจ — ไม่ใช้ dynamic SQL เพื่อเดาโครงสร้าง)
  --   58K-B-SEED-FIX-1 (F1): identity/generated columns มี column_default = null ใน
  --   information_schema ทั้งที่ DB เติมค่าให้เอง (เช่น id แบบ GENERATED AS IDENTITY
  --   ที่ Supabase Table Editor สร้าง) — ต้อง exclude ด้วย is_identity / is_generated
  --   ไม่งั้น guard จะ false-abort ทุกครั้ง; ❌ ไม่ hardcode ชื่อ 'id' — ใช้ semantics จริง
  select string_agg(column_name, ', ') into v_txt
  from information_schema.columns
  where table_schema='public' and table_name='documents'
    and is_nullable='NO' and column_default is null
    and coalesce(is_identity,'NO')='NO'
    and coalesce(is_generated,'NEVER')='NEVER'
    and column_name not in ('customer_id','owner_id','doc_name','doc_type','uploaded_by','source','owner_type');
  if v_txt is not null then
    raise exception 'PRECONDITION FAILED: documents has mandatory column(s) this script does not supply: % — review schema before seeding', v_txt;
  end if;

  -- ═══════════ SECTION 1.C — ลายนิ้วมือ staging (เคส/แอดมิน/แรงงาน) ═══════════
  -- เคสเดิมต้องมี "หนึ่งเดียว"
  select count(*) into v_cnt from public.cases where case_code='CASE-20260709-000001';
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 case CASE-20260709-000001, found % — WRONG ENVIRONMENT? STOP', v_cnt;
  end if;
  select cs.id, cs.customer_id into v_original_case_id, v_original_case_cust
  from public.cases cs where cs.case_code='CASE-20260709-000001';

  -- แอดมินทดสอบ active หนึ่งเดียว
  select count(*) into v_cnt from public.app_users u
  where u.username=v_admin_username and coalesce(u.is_active,true)=true and u.role is not null;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 active app_users % — found %', v_admin_username, v_cnt;
  end if;
  select u.id into v_admin_id from public.app_users u
  where u.username=v_admin_username and coalesce(u.is_active,true)=true and u.role is not null;

  -- แรงงาน active ของเคสเดิมต้องมี 2 คนพอดี (case_workers คือแหล่งความจริง)
  select count(*) into v_cnt from public.case_workers w
  where w.case_id=v_original_case_id and w.is_active;
  if v_cnt <> 2 then
    raise exception 'PRECONDITION FAILED: expected exactly 2 active case_workers for original case, found %', v_cnt;
  end if;

  -- แรงงานหลัก = แถว case_workers ที่ customer_id ตรงกับ cases.customer_id (นิยาม 58H) — หนึ่งเดียว
  select count(*) into v_cnt from public.case_workers w
  where w.case_id=v_original_case_id and w.is_active and w.customer_id=v_original_case_cust;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 primary case worker, found %', v_cnt;
  end if;
  select w.id, w.customer_id into v_primary_case_worker_id, v_primary_customer_id
  from public.case_workers w
  where w.case_id=v_original_case_id and w.is_active and w.customer_id=v_original_case_cust;

  -- ชื่อแรงงานหลักต้อง resolve เป็น TEST WORKER 58I (คอลัมน์ customers.name — คอลัมน์เดียวกับที่ app_list_case_workers ใช้)
  select count(*) into v_cnt from public.customers c
  where c.id=v_primary_customer_id and c.name='TEST WORKER 58I';
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: primary case worker customer is not TEST WORKER 58I — WRONG ENVIRONMENT? STOP';
  end if;

  -- แรงงานรอง active หนึ่งเดียว (แถว active ที่ไม่ใช่ primary)
  select count(*) into v_cnt from public.case_workers w
  where w.case_id=v_original_case_id and w.is_active and w.customer_id<>v_original_case_cust;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 secondary active case worker, found %', v_cnt;
  end if;
  select w.id, w.customer_id into v_secondary_case_worker_id, v_secondary_customer_id
  from public.case_workers w
  where w.case_id=v_original_case_id and w.is_active and w.customer_id<>v_original_case_cust;

  select count(*) into v_cnt from public.customers c
  where c.id=v_secondary_customer_id and c.name='TEST WORKER 58J SECOND';
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: secondary case worker customer is not TEST WORKER 58J SECOND — WRONG ENVIRONMENT? STOP';
  end if;

  -- เช็กลิสต์เดิม 17 รายการ (fingerprint เพิ่มเติม — สคริปต์นี้ไม่แตะเช็กลิสต์)
  if to_regclass('public.case_checklist_items') is null then
    raise exception 'PRECONDITION FAILED: case_checklist_items missing';
  end if;
  select count(*) into v_cnt from public.case_checklist_items i where i.case_id=v_original_case_id;
  if v_cnt <> 17 then
    raise exception 'PRECONDITION FAILED: expected 17 checklist items on original case, found %', v_cnt;
  end if;

  -- ═══════════ SECTION 1.D — synthetic entities ที่สร้างผ่าน UI ก่อนหน้า ═══════════
  -- ลูกค้าไม่เกี่ยวข้อง (soft delete = deleted_at — เงื่อนไขเดียวกับ 58H/app_add_case_worker)
  select count(*) into v_cnt from public.customers c
  where c.name='TEST_58K_UNRELATED_CUSTOMER' and c.deleted_at is null;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 customer TEST_58K_UNRELATED_CUSTOMER, found % — create it via UI first (SECTION 0.4)', v_cnt;
  end if;
  select c.id into v_unrelated_customer_id from public.customers c
  where c.name='TEST_58K_UNRELATED_CUSTOMER' and c.deleted_at is null;

  -- นายจ้างสังเคราะห์
  select count(*) into v_cnt from public.employers e where e.name='TEST_58K_EMPLOYER';
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 employer TEST_58K_EMPLOYER, found % — create it via UI first (SECTION 0.4)', v_cnt;
  end if;
  select e.id into v_employer_id from public.employers e where e.name='TEST_58K_EMPLOYER';

  -- ลูกค้าที่ผูกนายจ้างสังเคราะห์
  select count(*) into v_cnt from public.customers c
  where c.name='TEST_58K_EMP_WORKER' and c.deleted_at is null;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 customer TEST_58K_EMP_WORKER, found % — create it via UI first (SECTION 0.4)', v_cnt;
  end if;
  select c.id into v_employer_customer_id from public.customers c
  where c.name='TEST_58K_EMP_WORKER' and c.deleted_at is null;

  select count(*) into v_cnt from public.customers c
  where c.id=v_employer_customer_id and c.employer_id=v_employer_id;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: TEST_58K_EMP_WORKER is not bound to TEST_58K_EMPLOYER — fix via customer form first';
  end if;

  -- เคสทิ้งได้ของนายจ้างสังเคราะห์ (marker ใน case_title) — หนึ่งเดียว + ผูกถูกคู่
  select count(*) into v_cnt from public.cases cs
  where cs.case_title like '%TEST\_58K\_EMPLOYER\_CASE%' escape '\';
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: expected exactly 1 case titled TEST_58K_EMPLOYER_CASE, found % — create it via UI first (SECTION 0.4)', v_cnt;
  end if;
  select cs.id into v_employer_case_id from public.cases cs
  where cs.case_title like '%TEST\_58K\_EMPLOYER\_CASE%' escape '\';

  select count(*) into v_cnt from public.cases cs
  where cs.id=v_employer_case_id
    and cs.customer_id=v_employer_customer_id
    and cs.employer_id=v_employer_id;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: TEST_58K_EMPLOYER_CASE is not bound to TEST_58K_EMP_WORKER + TEST_58K_EMPLOYER as expected';
  end if;

  -- ═══════════ SECTION 1.E — ความปลอดภัยของเคสเดิม ═══════════
  -- เคสเดิมต้อง "ยังไม่ผูกนายจ้าง" — สคริปต์นี้ (และ 58K ทั้งสาย) ห้ามแก้เคสเดิม
  select count(*) into v_cnt from public.cases cs
  where cs.id=v_original_case_id and cs.employer_id is null;
  if v_cnt <> 1 then
    raise exception 'PRECONDITION FAILED: original case employer_id is no longer null — investigate before seeding (this script must never update it)';
  end if;

  -- ═══════════ SECTION 1.F — ความสะอาดของ marker ═══════════
  -- ทุกแถวที่อ้างว่าเป็น seed (source) ต้องมีชื่อขึ้นต้น TEST_58K_ เท่านั้น
  select count(*) into v_cnt from public.documents d
  where d.source='TEST_58K_SEED'
    and d.doc_name not like 'TEST\_58K\_%' escape '\';
  if v_cnt > 0 then
    raise exception 'PRECONDITION FAILED: % existing row(s) have source=TEST_58K_SEED but doc_name without TEST_58K_ prefix — clean up manually first', v_cnt;
  end if;

  -- ═══════════ SECTION 3 + 4 — SEED 5 แถว (idempotent, ห้าม update เงียบ) ═══════════
  -- แต่ละแถว: ถ้ายังไม่มี → insert; ถ้ามีอยู่แล้ว → ตรวจว่า owner ถูกต้อง (ผิด = abort);
  -- ถ้าซ้ำเกิน 1 แถว = abort — first-writer เป็นผู้กำหนดค่า ไม่มีการแก้ทับ

  -- ── 3.1 เอกสารแรงงานหลัก ──
  select count(*) into v_cnt from public.documents
  where source='TEST_58K_SEED' and doc_name='TEST_58K_PRIMARY_PASSPORT';
  if v_cnt > 1 then
    raise exception 'SEED ABORT: duplicate TEST_58K_PRIMARY_PASSPORT rows (%)', v_cnt;
  elsif v_cnt = 1 then
    -- 58K-B-SEED-FIX-1 (O2): fingerprint ครบทุก field สำคัญ (null-safe) — ผิดข้อใดข้อหนึ่ง = abort ไม่แก้ทับ
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name='TEST_58K_PRIMARY_PASSPORT'
      and doc_type='passport'
      and customer_id is not distinct from v_primary_customer_id
      and owner_type='customer'
      and owner_id is not distinct from v_primary_customer_id
      and uploaded_by='leejunkik2'
      and doc_note like '%TEST\_58K\_SEED%' escape '\'
      and file_data is null and storage_path is null and storage_bucket is null
      and doc_expiry is null and doc_status is null;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: existing TEST_58K_PRIMARY_PASSPORT has wrong owner/metadata fingerprint — will not update silently';
    end if;
  else
    insert into public.documents
      (customer_id, doc_type, doc_name, file_data, storage_bucket, storage_path,
       source, owner_type, owner_id, uploaded_by, doc_note, doc_expiry, doc_status)
    values
      (v_primary_customer_id, 'passport', 'TEST_58K_PRIMARY_PASSPORT', null, null, null,
       'TEST_58K_SEED', 'customer', v_primary_customer_id, 'leejunkik2',
       'TEST_58K_SEED — synthetic metadata-only test row (primary worker) — no real file', null, null);
  end if;

  -- ── 3.2 เอกสารแรงงานรอง (Name List) ──
  select count(*) into v_cnt from public.documents
  where source='TEST_58K_SEED' and doc_name='TEST_58K_SECONDARY_PASSPORT';
  if v_cnt > 1 then
    raise exception 'SEED ABORT: duplicate TEST_58K_SECONDARY_PASSPORT rows (%)', v_cnt;
  elsif v_cnt = 1 then
    -- 58K-B-SEED-FIX-1 (O2): fingerprint ครบทุก field สำคัญ (null-safe)
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name='TEST_58K_SECONDARY_PASSPORT'
      and doc_type='passport'
      and customer_id is not distinct from v_secondary_customer_id
      and owner_type='customer'
      and owner_id is not distinct from v_secondary_customer_id
      and uploaded_by='leejunkik2'
      and doc_note like '%TEST\_58K\_SEED%' escape '\'
      and file_data is null and storage_path is null and storage_bucket is null
      and doc_expiry is null and doc_status is null;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: existing TEST_58K_SECONDARY_PASSPORT has wrong owner/metadata fingerprint — will not update silently';
    end if;
  else
    insert into public.documents
      (customer_id, doc_type, doc_name, file_data, storage_bucket, storage_path,
       source, owner_type, owner_id, uploaded_by, doc_note, doc_expiry, doc_status)
    values
      (v_secondary_customer_id, 'passport', 'TEST_58K_SECONDARY_PASSPORT', null, null, null,
       'TEST_58K_SEED', 'customer', v_secondary_customer_id, 'leejunkik2',
       'TEST_58K_SEED — synthetic metadata-only test row (secondary Name List worker) — no real file', null, null);
  end if;

  -- ── 3.3 เอกสารของเคสเดิม (ใช้ทดสอบทั้งแขนง case และ internal — internal คือ attribution
  --        ของ "ลิงก์" เท่านั้น ❌ ไม่มี owner_type='internal' ใน documents CHECK) ──
  select count(*) into v_cnt from public.documents
  where source='TEST_58K_SEED' and doc_name='TEST_58K_CASE_DOCUMENT';
  if v_cnt > 1 then
    raise exception 'SEED ABORT: duplicate TEST_58K_CASE_DOCUMENT rows (%)', v_cnt;
  elsif v_cnt = 1 then
    -- 58K-B-SEED-FIX-1 (O2): fingerprint ครบทุก field สำคัญ (null-safe)
    -- 58K-B-SEED-FIX-2: customer_id = ลูกค้าเจ้าของเคสเดิม (schema NOT NULL) — ownership ยังเป็น case
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name='TEST_58K_CASE_DOCUMENT'
      and doc_type='request_form'
      and customer_id is not distinct from v_original_case_cust
      and owner_type='case'
      and owner_id is not distinct from v_original_case_id
      and uploaded_by='leejunkik2'
      and doc_note like '%TEST\_58K\_SEED%' escape '\'
      and file_data is null and storage_path is null and storage_bucket is null
      and doc_expiry is null and doc_status is null;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: existing TEST_58K_CASE_DOCUMENT has wrong owner/metadata fingerprint — will not update silently';
    end if;
  else
    -- doc_type='request_form' = ค่าที่มีจริงใน taxonomy ฝั่งแอป (_DC_DOC_TYPE_LABELS →
    -- 'ใบรับคำขอ'); documents.doc_type เป็น text ไม่มี CHECK constraint (ตรวจแล้ว 20260703/20260706)
    -- 58K-B-SEED-FIX-2: customer_id = v_original_case_cust (parent context — NOT NULL schema);
    --   ความเป็นเจ้าของจริงยังเป็น owner_type='case' + owner_id=เคสเดิม
    insert into public.documents
      (customer_id, doc_type, doc_name, file_data, storage_bucket, storage_path,
       source, owner_type, owner_id, uploaded_by, doc_note, doc_expiry, doc_status)
    values
      (v_original_case_cust, 'request_form', 'TEST_58K_CASE_DOCUMENT', null, null, null,
       'TEST_58K_SEED', 'case', v_original_case_id, 'leejunkik2',
       'TEST_58K_SEED — synthetic metadata-only test row (case-owned; also used for internal-attribution link test) — no real file', null, null);
  end if;

  -- ── 3.4 เอกสารของลูกค้าที่ไม่เกี่ยวข้อง (negative test) ──
  select count(*) into v_cnt from public.documents
  where source='TEST_58K_SEED' and doc_name='TEST_58K_UNRELATED_PASSPORT';
  if v_cnt > 1 then
    raise exception 'SEED ABORT: duplicate TEST_58K_UNRELATED_PASSPORT rows (%)', v_cnt;
  elsif v_cnt = 1 then
    -- 58K-B-SEED-FIX-1 (O2): fingerprint ครบทุก field สำคัญ (null-safe)
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name='TEST_58K_UNRELATED_PASSPORT'
      and doc_type='passport'
      and customer_id is not distinct from v_unrelated_customer_id
      and owner_type='customer'
      and owner_id is not distinct from v_unrelated_customer_id
      and uploaded_by='leejunkik2'
      and doc_note like '%TEST\_58K\_SEED%' escape '\'
      and file_data is null and storage_path is null and storage_bucket is null
      and doc_expiry is null and doc_status is null;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: existing TEST_58K_UNRELATED_PASSPORT has wrong owner/metadata fingerprint — will not update silently';
    end if;
  else
    insert into public.documents
      (customer_id, doc_type, doc_name, file_data, storage_bucket, storage_path,
       source, owner_type, owner_id, uploaded_by, doc_note, doc_expiry, doc_status)
    values
      (v_unrelated_customer_id, 'passport', 'TEST_58K_UNRELATED_PASSPORT', null, null, null,
       'TEST_58K_SEED', 'customer', v_unrelated_customer_id, 'leejunkik2',
       'TEST_58K_SEED — synthetic metadata-only test row (unrelated customer, rejection test) — no real file', null, null);
  end if;

  -- ── 3.5 เอกสารนายจ้างสังเคราะห์ ──
  select count(*) into v_cnt from public.documents
  where source='TEST_58K_SEED' and doc_name='TEST_58K_EMPLOYER_CERT';
  if v_cnt > 1 then
    raise exception 'SEED ABORT: duplicate TEST_58K_EMPLOYER_CERT rows (%)', v_cnt;
  elsif v_cnt = 1 then
    -- 58K-B-SEED-FIX-1 (O2): fingerprint ครบทุก field สำคัญ (null-safe)
    -- 58K-B-SEED-FIX-2: customer_id = TEST_58K_EMP_WORKER (schema NOT NULL) — ownership ยังเป็น employer
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name='TEST_58K_EMPLOYER_CERT'
      and doc_type='company_certificate'
      and customer_id is not distinct from v_employer_customer_id
      and owner_type='employer'
      and owner_id is not distinct from v_employer_id
      and uploaded_by='leejunkik2'
      and doc_note like '%TEST\_58K\_SEED%' escape '\'
      and file_data is null and storage_path is null and storage_bucket is null
      and doc_expiry is null and doc_status is null;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: existing TEST_58K_EMPLOYER_CERT has wrong owner/metadata fingerprint — will not update silently';
    end if;
  else
    -- 58K-B-SEED-FIX-2: customer_id = v_employer_customer_id (parent context — NOT NULL schema);
    --   ความเป็นเจ้าของจริงยังเป็น owner_type='employer' + owner_id=TEST_58K_EMPLOYER
    insert into public.documents
      (customer_id, doc_type, doc_name, file_data, storage_bucket, storage_path,
       source, owner_type, owner_id, uploaded_by, doc_note, doc_expiry, doc_status)
    values
      (v_employer_customer_id, 'company_certificate', 'TEST_58K_EMPLOYER_CERT', null, null, null,
       'TEST_58K_SEED', 'employer', v_employer_id, 'leejunkik2',
       'TEST_58K_SEED — synthetic metadata-only test row (synthetic employer) — no real file', null, null);
  end if;

  -- ═══════════ SECTION 4 (ต่อ) — post-insert assertions ═══════════
  -- แต่ละ marker ต้อง resolve เป็น 1 แถวพอดี
  for r_doc in
    select m.nm from (values ('TEST_58K_PRIMARY_PASSPORT'),('TEST_58K_SECONDARY_PASSPORT'),
                             ('TEST_58K_CASE_DOCUMENT'),('TEST_58K_UNRELATED_PASSPORT'),
                             ('TEST_58K_EMPLOYER_CERT')) as m(nm)
  loop
    select count(*) into v_cnt from public.documents
    where source='TEST_58K_SEED' and doc_name=r_doc.nm;
    if v_cnt <> 1 then
      raise exception 'SEED ABORT: expected exactly 1 row for %, found %', r_doc.nm, v_cnt;
    end if;
  end loop;

  -- รวมทั้งชุดต้องเป็น 5 แถวพอดี และห้ามมี link ใด ๆ เกิดขึ้นจาก seed
  select count(*) into v_cnt from public.documents where source='TEST_58K_SEED';
  if v_cnt <> 5 then
    raise exception 'SEED ABORT: expected exactly 5 TEST_58K_SEED documents, found %', v_cnt;
  end if;
  select count(*) into v_cnt from public.case_documents l
  where l.document_id in (select d.id from public.documents d where d.source='TEST_58K_SEED');
  if v_cnt <> 0 then
    raise notice 'NOTE: % case_documents link(s) already exist on seed documents (re-run after 58K-B3 started?) — seed itself created none', v_cnt;
  end if;

  raise notice 'SEED OK: 5 metadata-only TEST_58K_SEED documents present. No links created. No existing rows updated.';
end$$;

-- ═══════════ SECTION 5 — ผลลัพธ์การ seed (read-only, แสดงก่อน commit) ═══════════
-- 58K-B-SEED-FIX-1 (O4) — หมายเหตุสำหรับผู้รัน:
--   Supabase SQL Editor ปกติแสดง "เฉพาะตารางผลลัพธ์ของ statement สุดท้าย" เมื่อรัน
--   หลาย statement พร้อมกัน — SELECT ทั้งสามของ SECTION 5 ยังรันครบใน transaction
--   แต่บนจออาจเห็นแค่ผล seed_links ตัวสุดท้าย ถ้าต้องการดูครบทุกตาราง ให้รัน
--   query ใน SECTION 7 ทีละคำสั่ง "หลัง commit" (read-only ทั้งหมด รันซ้ำได้)
select d.id,
       d.doc_name,
       d.doc_type,
       d.customer_id,
       d.owner_type,
       d.owner_id,
       d.source,
       (d.storage_path is not null) as has_storage,          -- ต้องเป็น false ทุกแถว
       case d.doc_name
         when 'TEST_58K_PRIMARY_PASSPORT'   then 'primary-worker selector + worker attribution test'
         when 'TEST_58K_SECONDARY_PASSPORT' then 'secondary Name List isolation + attribution test'
         when 'TEST_58K_CASE_DOCUMENT'      then 'case + internal link tests (original case)'
         when 'TEST_58K_UNRELATED_PASSPORT' then 'negative visibility + forced-link rejection test'
         when 'TEST_58K_EMPLOYER_CERT'      then 'employer selector test (disposable employer case)'
       end as test_purpose,
       coalesce(c.name, e.name, cs.case_code)               as resolved_owner_label
from public.documents d
left join public.customers c on d.owner_type='customer' and c.id=d.owner_id
left join public.employers e on d.owner_type='employer' and e.id=d.owner_id
left join public.cases     cs on d.owner_type='case'     and cs.id=d.owner_id
where d.source='TEST_58K_SEED'
order by d.doc_name;

-- คาดหวัง: 5 แถว, has_storage=false ทั้งหมด, owner label ตรงตามตาราง §3
select count(*) as seed_documents            -- คาดหวัง 5
from public.documents where source='TEST_58K_SEED';
select count(*) as seed_links                -- คาดหวัง 0 (ยังไม่มีการลิงก์ก่อน 58K-B3)
from public.case_documents
where document_id in (select id from public.documents where source='TEST_58K_SEED');

commit;

-- =====================================================================
-- SECTION 6 — การใช้งานใน 58K-B3 (comments only)
-- =====================================================================
-- เอกสาร → กลุ่มที่ต้องปรากฏใน selector (เคสเดิม CASE-20260709-000001):
--   TEST_58K_PRIMARY_PASSPORT   → เฉพาะ section "แรงงานหลัก — TEST WORKER 58I"
--   TEST_58K_SECONDARY_PASSPORT → เฉพาะ section "แรงงานในรายชื่อ 2 — TEST WORKER 58J SECOND"
--   TEST_58K_CASE_DOCUMENT      → section "เคสนี้" / "หลักฐานภายใน (เอกสารของเคสนี้)"
--   TEST_58K_UNRELATED_PASSPORT → ต้อง "ไม่ปรากฏ" ในทุก section; ยิง RPC ตรง → document_not_allowed
--   TEST_58K_EMPLOYER_CERT      → เคสทิ้งได้ TEST_58K_EMPLOYER_CASE (section นายจ้าง/บริษัท)
--                                 บนเคสเดิม (ไม่มีนายจ้าง) ต้องเห็นข้อความ
--                                 "ยังไม่มีนายจ้าง / บริษัทที่ผูกกับเคสนี้"
--
-- ⚠️ 58K-B-SEED-FIX-2 — ผลของ schema จริง (customer_id NOT NULL) ต่อความคาดหวังใน B3:
--   app_list_documents กรองด้วย p_customer_id จะเห็นแถวที่ d.customer_id ตรง (semantics เดิม)
--   → TEST_58K_CASE_DOCUMENT (customer_id = ลูกค้าเจ้าของเคส) จะ "ปรากฏเพิ่ม" ใน section
--     แรงงานหลักของเคสเดิม และเลือก/ลิงก์แบบ worker ได้ (server ยอมรับตาม legacy customer rule)
--   → TEST_58K_EMPLOYER_CERT (customer_id = TEST_58K_EMP_WORKER) จะ "ปรากฏเพิ่ม" ใน section
--     แรงงานของเคส TEST_58K_EMPLOYER_CASE ด้วย
--   นี่คือพฤติกรรมที่ถูกต้องตาม schema/RPC จริง — ไม่ใช่ bug; การทดสอบ "เฉพาะกลุ่ม" ให้ยึด
--   แถว 1/2/4 (passport ของแรงงาน/ลูกค้า) เป็นตัววัด isolation หลัก
--
-- ⚠️ กดปุ่ม "เปิดดู" บนเอกสาร metadata-only จะขึ้น "เปิดไฟล์ไม่สำเร็จ" —
--    เป็นพฤติกรรมที่คาดหวัง (ไม่มีไฟล์จริงโดยตั้งใจ) ไม่ใช่ความล้มเหลวของการทดสอบลิงก์
-- =====================================================================

-- =====================================================================
-- SECTION 7 — READ-ONLY VERIFICATION QUERIES (รันแยกได้ทุกเมื่อ ไม่แก้ข้อมูล)
-- =====================================================================
-- 7.1 ทุก marker resolve หนึ่งเดียว + storage ว่างทุกช่อง:
--   select doc_name, count(*) as n,
--          bool_and(file_data is null and storage_path is null and storage_bucket is null) as metadata_only
--   from public.documents where source='TEST_58K_SEED'
--   group by doc_name order by doc_name;            -- คาดหวัง 5 แถว, n=1, metadata_only=true
--
-- 7.2 ความเป็นเจ้าของรายแถว (ต้องตรงตาราง §3 ของสคริปต์):
--   select d.doc_name, d.customer_id, d.owner_type, d.owner_id,
--          coalesce(c.name, e.name, cs.case_code) as owner_label
--   from public.documents d
--   left join public.customers c on d.owner_type='customer' and c.id=d.owner_id
--   left join public.employers e on d.owner_type='employer' and e.id=d.owner_id
--   left join public.cases     cs on d.owner_type='case'     and cs.id=d.owner_id
--   where d.source='TEST_58K_SEED' order by d.doc_name;
--
-- 7.3 ยังไม่มีลิงก์ก่อนเริ่มทดสอบ browser:
--   select count(*) from public.case_documents
--   where document_id in (select id from public.documents where source='TEST_58K_SEED');
--     -- คาดหวัง 0 (ก่อน 58K-B3)
--
-- 7.4 เคสเดิมยังมีแรงงาน active 2 คน + เช็กลิสต์ 17 รายการ + ไม่มีนายจ้าง:
--   select (select count(*) from public.case_workers w
--            join public.cases cs on cs.id=w.case_id
--            where cs.case_code='CASE-20260709-000001' and w.is_active)      as active_workers,   -- 2
--          (select count(*) from public.case_checklist_items i
--            join public.cases cs on cs.id=i.case_id
--            where cs.case_code='CASE-20260709-000001')                       as checklist_items,  -- 17
--          (select employer_id from public.cases
--            where case_code='CASE-20260709-000001')                          as original_employer; -- null
--
-- 7.5 เคสนายจ้างทดสอบผูกนายจ้างถูกตัว:
--   select cs.case_code, cs.case_title, cs.employer_id, e.name
--   from public.cases cs join public.employers e on e.id=cs.employer_id
--   where cs.case_title like '%TEST\_58K\_EMPLOYER\_CASE%' escape '\';
--     -- คาดหวัง 1 แถว, e.name='TEST_58K_EMPLOYER'
--
-- 7.6 ไม่มีเอกสาร non-TEST ถูกแตะ (ก่อน seed มี documents=0 → หลัง seed
--     เอกสารที่ source ไม่ใช่ TEST_58K_SEED ต้องเป็น 0):
--   select count(*) from public.documents
--   where source is distinct from 'TEST_58K_SEED';   -- คาดหวัง 0 บน staging ชุดนี้
-- =====================================================================

-- =====================================================================
-- SECTION 8 — MANUAL CLEANUP — DO NOT UNCOMMENT UNTIL 58K-B3 TESTING IS COMPLETE
--   (บล็อกนี้ถูกคอมเมนต์ทั้งหมด — ไม่รันอัตโนมัติ — idempotent เมื่อรันซ้ำ)
-- =====================================================================
-- begin;
--
-- -- ก่อนลบ: นับก่อน (before counts)
-- -- select (select count(*) from public.documents where source='TEST_58K_SEED')      as docs_before,
-- --        (select count(*) from public.case_documents l
-- --          where l.document_id in (select id from public.documents
-- --                                  where source='TEST_58K_SEED'))                   as links_before;
--
-- -- 1) ลบเฉพาะ "ลิงก์" ของเอกสาร seed (case_documents เท่านั้น — เอกสาร/เช็กลิสต์ไม่ถูกแตะ):
-- -- delete from public.case_documents l
-- -- where l.document_id in (
-- --   select d.id from public.documents d
-- --   where d.source='TEST_58K_SEED'
-- --     and d.doc_name like 'TEST\_58K\_%' escape '\'
-- -- );
--
-- -- 2) ลบเฉพาะเอกสาร seed ตาม allowlist ชื่อเป๊ะ 5 ชื่อ + source ตรง:
-- -- delete from public.documents d
-- -- where d.source='TEST_58K_SEED'
-- --   and d.doc_name in ('TEST_58K_PRIMARY_PASSPORT','TEST_58K_SECONDARY_PASSPORT',
-- --                      'TEST_58K_CASE_DOCUMENT','TEST_58K_UNRELATED_PASSPORT',
-- --                      'TEST_58K_EMPLOYER_CERT');
--
-- -- หลังลบ: นับหลัง (after counts — คาดหวัง 0 ทั้งคู่):
-- -- select (select count(*) from public.documents where source='TEST_58K_SEED')      as docs_after,
-- --        (select count(*) from public.case_documents l
-- --          where l.document_id in (select id from public.documents
-- --                                  where source='TEST_58K_SEED'))                   as links_after;
--
-- commit;
--
-- ❌ ห้ามลบใน cleanup นี้:
--   - audit_logs (เก็บตามนโยบาย retention — ไม่ลบเด็ดขาด)
--   - TEST WORKER 58I / TEST WORKER 58J SECOND (customers)
--   - CASE-20260709-000001 + เช็กลิสต์ + case_workers ของมัน
--   - แถว synthetic ที่สร้างผ่าน UI (ดู checklist ด้านล่าง)
--
-- CLEANUP CHECKLIST สำหรับ entity สังเคราะห์ (ทำผ่าน UI/RPC ที่รองรับเท่านั้น):
--   [ ] ปิดเคสทิ้งได้ TEST_58K_EMPLOYER_CASE ด้วยการเปลี่ยนสถานะ (cancelled) ผ่าน UI เดิม
--   [ ] soft-deactivate ลูกค้า TEST_58K_UNRELATED_CUSTOMER ถ้าต้องการ (ผ่าน UI เดิม)
--   [ ] soft-deactivate ลูกค้า TEST_58K_EMP_WORKER ถ้าต้องการ (ผ่าน UI เดิม)
--   [ ] ปล่อย TEST_58K_EMPLOYER ไว้แบบ inactive หรือจัดการผ่าน UI/RPC นายจ้างเดิม
--   [ ] ❌ ห้าม raw-delete แถว customers/employers/cases เหล่านี้ เว้นแต่มี stage
--       cleanup ที่รีวิวแยกต่างหากอนุมัติ
-- =====================================================================

-- =====================================================================
-- SECTION 9 — ROLLBACK BEHAVIOR (comments only)
-- =====================================================================
-- * ทุก exception ก่อน commit ทำให้ transaction ทั้งก้อน abort — ไม่มี seed ค้างครึ่งเดียว
-- * ถ้าใช้ SQL Editor แล้วเจอ error: สั่ง  rollback;  อย่างชัดเจนก่อนทำอย่างอื่น
-- * ❌ อย่ารันซ้ำทันทีหลัง error — เก็บข้อความ error ฉบับเต็มก่อน แล้ววิเคราะห์สาเหตุ
-- * seed นี้ไม่สร้าง case_documents ใด ๆ — การลิงก์เกิดใน 58K-B3 ผ่าน UI เท่านั้น
-- * เอกสารที่ไม่ใช่ TEST_58K ไม่ถูก update/delete ในทุกกรณี (สคริปต์ไม่มีคำสั่ง
--   update และ delete มีเฉพาะในบล็อก cleanup ที่คอมเมนต์ไว้ + จำกัดด้วย marker)
-- =====================================================================
-- END 58K-B-SEED-A — STAGING ONLY — DO NOT APPLY TO PRODUCTION
-- =====================================================================
