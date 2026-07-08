-- =====================================================================
-- STAGE 58I-FIX-1 — Apply REAL Checklist-ITEM Content (5 pilot templates)
--   (companion to manual/PHASE2_BACKEND_CONTRACT_58F.md §B.1–B.3)
--
--   ⚠️⚠️⚠️  MANUAL REVIEW REQUIRED — ไฟล์นี้อยู่นอก supabase/migrations โดยตั้งใจ
--            ห้ามย้ายเข้า supabase/migrations/  ⚠️⚠️⚠️
--   ⚠️ รันใน Supabase SQL Editor ด้วย role postgres บน **STAGING เท่านั้น**
--        หลัง backup + ตรวจ + อนุมัติ (ดู runbook 58G) — ❌ ห้ามรันบน production
--   ⚠️ ROLLBACK-first (dry-run) — บรรทัดสุดท้ายเป็น `rollback;`
--        ตรวจผล verification (SECTION 2) ก่อน แล้วจึงเปลี่ยน `rollback;` เป็น `commit;`
--        ด้วยมือ — และเฉพาะบน STAGING เท่านั้น · ❌ ไม่มี auto-commit ในไฟล์นี้
--   ⚠️ Idempotent — รันซ้ำได้: resolve item_id จาก (template_id,item_code) ก่อน
--        → มีอยู่แล้ว = UPDATE แถวเดิม · ยังไม่มี = CREATE (ไม่เกิดรายการซ้ำ)
-- =====================================================================
-- เป้าหมาย: กรอก "รายการเช็คลิสต์จริง" (checklist ITEMS) ของ 5 แม่แบบนำร่อง
--   แทนของ generic เดิม — ผ่าน admin RPC public.app_admin_save_case_template_item
--   (migration 20260801, audited, admin-only) — ❌ ไม่ UPDATE ตารางตรง
--
--   5 แม่แบบนำร่อง (เท่านั้น):
--     1) MOU_MYANMAR_NEW
--     2) MOU_LAOS_NEW
--     3) MOU_CAMBODIA_NEW      (MOU 3 สัญชาติใช้ชุด item เดียวกันในรอบนี้)
--     4) EMPLOYER_NOTIFICATION_IN
--     5) EMPLOYER_NOTIFICATION_OUT
--   ⛔ ไม่แตะแม่แบบอื่น (CI_MYANMAR / VISA_* / RENEWAL / CHANGE_EMPLOYER / ฯลฯ)
--
-- ❗ ขอบเขต stage นี้ (checklist items เท่านั้น):
--   - ❌ ไม่เรียก app_admin_save_case_template (ไม่แตะ template metadata / identity)
--   - ❌ ไม่แตะ case_templates, is_active ของ template, sort_order ของ template
--   - ❌ ไม่แตะ customers / cases / case_workers / documents / storage / payments /
--        appointments / tracking / app_users / login / attendance / RLS / grants
--   - ❌ ไม่ hard delete/ไม่ deactivate รายการ generic เดิมที่ code ไม่ตรง —
--        คงไว้ (ทำ deactivate เป็นสเตจแยกถ้าเจ้าของต้องการ ผ่าน app_admin_set_case_template_active)
--
-- ❗ owner (required_from) ใช้เฉพาะค่าใน enum ที่มีจริง (migration 20260801):
--     worker / employer / establishment / case / payment / internal
-- ❗ doc_type ใช้เฉพาะค่าที่ระบบรองรับอยู่แล้ว (passport/photo/receipt/visa/work_permit/ci);
--     ชนิดที่ยังไม่มีใน taxonomy (เช่น medical) → เว้น doc_type = null + ระบุใน note
-- ❗ ห้ามเดา: ความไม่ชัด (ม.41/46, แบบฟอร์มแจ้งเข้า/ออก, ค่าธรรมเนียม, field วันที่/สถานที่)
--     = ใส่คำว่า NEED_REVIEW ใน note ไม่แสร้งว่าแน่นอน
-- ❗ ถ้อยคำเป็น "การเตรียม/ตรวจภายใน" เท่านั้น — ไม่อ้างว่า CRM ยื่น/อนุมัติ/ออกเอกสารราชการ
-- =====================================================================


-- =====================================================================
-- SECTION 0 — PREVIEW (ก่อนแก้): จำนวน item ปัจจุบันของ 5 แม่แบบ (read-only)
-- =====================================================================
begin;

select t.template_code,
       count(i.*)                          as items_now,
       count(i.*) filter (where i.is_active) as items_active_now
from public.case_templates t
left join public.case_template_checklist_items i on i.template_id = t.id
where t.template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_IN','EMPLOYER_NOTIFICATION_OUT')
group by t.template_code
order by t.template_code;


-- =====================================================================
-- SECTION 1 — APPLY checklist items (idempotent, admin RPC, dry-run)
--   ก่อนรัน: แก้ v_admin_username ให้เป็น username ของ admin ตัวจริง "บน STAGING"
-- =====================================================================
do $$
declare
  -- ⬇⬇⬇  แก้ตรงนี้: ใส่ username ของ admin ที่ active "บน STAGING" (RPC ตรวจสิทธิ์ admin เอง)  ⬇⬇⬇
  v_admin_username text := 'leejunkik2';
  -- ⬆⬆⬆ ------------------------------------------------------------------------------------ ⬆⬆⬆
  v_admin_id text;
  v_tid      bigint;
  v_iid      bigint;
  v_tc       text;
  r          record;
begin
  -- ── หา admin id จาก username (ต้อง role admin + active) ──
  select u.id::text into v_admin_id
  from public.app_users u
  where u.username = v_admin_username
    and lower(u.role) = 'admin'
    and coalesce(u.is_active, true) = true
  limit 1;

  if v_admin_id is null then
    raise exception 'ไม่พบผู้ใช้ admin ที่ active ชื่อ "%": โปรดแก้ v_admin_username ให้ตรงกับ STAGING ก่อนรัน', v_admin_username;
  end if;

  -- ===================================================================
  -- (A) MOU_MYANMAR_NEW / MOU_LAOS_NEW / MOU_CAMBODIA_NEW — ชุด item เดียวกัน
  --     ความต่างรายสัญชาติที่ยังไม่ยืนยัน = NEED_REVIEW ใน note
  -- ===================================================================
  foreach v_tc in array array['MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW']
  loop
    select id into v_tid from public.case_templates where template_code = v_tc;
    if v_tid is null then raise exception 'ไม่พบแม่แบบนำร่อง %', v_tc; end if;

    for r in
      select * from (values
        ('mou_side_or_law_review', 'ตรวจสายงาน MOU / มาตรา 41 หรือ 46',            null::text,      true,  'case',     'ต้องตรวจว่าเป็นสายบริษัทนำเข้า ม.41 หรือสายนายจ้างยื่น ม.46 ก่อนใช้งานจริง; ยังไม่แยก field mou_side ในระบบ (NEED_REVIEW)',  10),
        ('passport_or_ci',         'พาสปอร์ต / CI ของแรงงาน',                       'passport'::text, true,  'worker',   'ตรวจเลขเอกสารและวันหมดอายุ; CI ใช้แทนพาสปอร์ตได้ (doc_type=passport เป็นค่าที่ระบบรองรับ)',                        20),
        ('worker_photo',           'รูปถ่ายแรงงาน',                                 'photo'::text,    true,  'worker',   'รูปปัจจุบัน ใช้สำหรับเตรียมเอกสาร',                                                                              30),
        ('name_list',              'Name List / รายชื่อแรงงาน',                     null::text,      true,  'case',     'ต้องรองรับหลายแรงงานต่อเคส; ใช้ร่วมกับ case_workers (58H) แต่ readiness UI รายแรงงานยังต้องต่อภายหลัง',              40),
        ('employer_documents',     'เอกสารนายจ้าง',                                 null::text,      true,  'employer', 'ตอนนี้อาจยังลิงก์เอกสารนายจ้างเข้า checklist ไม่ได้จนกว่า multi-owner RPC stage จะเสร็จ (requires backend later)',   50),
        ('company_certificate',    'หนังสือรับรองบริษัท / เอกสารนิติบุคคล',          null::text,      true,  'employer', 'ใช้กรณีนายจ้างเป็นบริษัท ต้องตรวจเอกสารจริง',                                                                    60),
        ('power_of_attorney',      'หนังสือมอบอำนาจ',                               null::text,      true,  'employer', 'ต้องตรวจผู้ลงนามและผู้รับมอบอำนาจ',                                                                              70),
        ('demand_nj2',             'คำร้องนำเข้า / Demand Letter / นจ.2',            null::text,      true,  'case',     'เอกสารเฉพาะเคส ต้องตรวจตามสายงาน ม.41/ม.46 (NEED_REVIEW)',                                                        80),
        ('bt31_bt33',              'แบบคำขออนุญาตทำงานแทน บต.31 / บต.33',            null::text,      true,  'case',     'บต.31 สำหรับสายบริษัทนำเข้า / บต.33 สำหรับสายนายจ้าง ต้องแยกให้ชัดใน backend ภายหลัง (NEED_REVIEW)',               90),
        ('employment_contract',    'สัญญาจ้าง',                                     null::text,      true,  'case',     'เอกสารเตรียมภายใน/ประกอบงาน ไม่ใช่เอกสารราชการที่ CRM ยื่นอัตโนมัติ',                                              100),
        ('medical_certificate',    'ใบรับรองแพทย์',                                 null::text,      true,  'worker',   'ตรวจวันออกเอกสารและความถูกต้อง; doc_type "medical" ยังไม่มีใน taxonomy → เว้น doc_type ไว้ (NEED_REVIEW)',           110),
        ('visa_entry_stamp',       'VISA / ตรวจลงตรา / ตราประทับเข้าเมือง',          'visa'::text,     false, 'worker',   'ใช้เมื่อต้องตรวจหลังเข้าประเทศ/ก่อนขั้นตอนถัดไป (conditional)',                                                    120),
        ('payment_receipt',        'หลักฐานการชำระเงิน',                            'receipt'::text,  true,  'payment',  'หลักฐานชำระเงินภายใน ไม่ใช่ใบเสร็จราชการ; ค่าธรรมเนียม = NEED_REVIEW',                                             130),
        ('appointment_date',       'วันนัด / วันยื่น',                              null::text,      false, 'case',     'พนักงานกรอกวันนัดเอง หรือผูกกับ case_appointments ภายหลัง',                                                       140),
        ('ewp_request_no',         'เลขคำขอ e-WorkPermit',                          null::text,      false, 'internal', 'บันทึกเลขคำขอหลังพนักงานยื่นจริงเอง ไม่ใช่การยื่นอัตโนมัติ',                                                       150),
        ('reply_document',         'หลักฐานหลังยื่น / เอกสารตอบรับจากระบบ',          null::text,      false, 'case',     'พนักงานแนบเอกสารตอบรับหลังยื่นจริง; ไม่ใช่การอนุมัติอัตโนมัติจาก CRM',                                             160),
        ('submit_result_note',     'หมายเหตุผลการยื่น',                             null::text,      false, 'internal', 'พนักงานบันทึกผล/เลขคำขอ/สิ่งที่ต้องติดตามเอง',                                                                    170)
      ) as s(item_code, name_th, doc_type, is_required, required_from, note, sort_order)
    loop
      select id into v_iid from public.case_template_checklist_items
        where template_id = v_tid and item_code = r.item_code;
      perform public.app_admin_save_case_template_item(
        v_admin_id, v_admin_username,
        v_iid,               -- p_item_id: null=create, มีค่า=update (idempotent)
        v_tid,               -- p_template_id (ใช้ตอน create)
        r.item_code, r.name_th, null::text /*name_en: คงเดิม*/,
        r.doc_type, r.is_required, r.required_from, r.note, r.sort_order);
    end loop;
    raise notice 'applied MOU checklist items → % (tid=%)', v_tc, v_tid;
  end loop;

  -- ===================================================================
  -- (B) EMPLOYER_NOTIFICATION_IN — แจ้งแรงงานเข้า
  --     ⚠️ แบบฟอร์ม/มาตรา = NEED_REVIEW (ไฟล์ต้นทางปนถ้อยคำแจ้งออก)
  -- ===================================================================
  select id into v_tid from public.case_templates where template_code = 'EMPLOYER_NOTIFICATION_IN';
  if v_tid is null then raise exception 'ไม่พบแม่แบบนำร่อง EMPLOYER_NOTIFICATION_IN'; end if;

  for r in
    select * from (values
      ('worker_identity',      'ข้อมูลแรงงาน / ยืนยันตัวตนแรงงาน',        null::text,        true,  'worker',        'ยืนยันตัวตนแรงงานก่อนแจ้งเข้า',                                                                       10),
      ('passport_or_ci',       'พาสปอร์ต / CI แรงงาน',                    'passport'::text,  true,  'worker',        'CI ใช้แทนพาสปอร์ตได้ (doc_type=passport)',                                                            20),
      ('employer_confirmation','ข้อมูลนายจ้าง / ผู้รับเข้าทำงาน',          null::text,        true,  'employer',      'เอกสารนายจ้างอาจยังต้องทำระบบลิงก์เพิ่มก่อน (requires backend later)',                                 30),
      ('start_date',           'วันที่เริ่มงาน',                          null::text,        true,  'case',          'ตอนนี้อาจยังเป็น note/manual จนกว่าจะมี field start_date (NEED_REVIEW)',                                40),
      ('work_location',        'สถานที่ทำงาน / สาขา',                     null::text,        false, 'establishment', 'ต้องมี establishment_id/work_location ในอนาคต (requires backend later)',                               50),
      ('current_work_permit',  'ใบอนุญาตทำงาน / เอกสารสิทธิ์ทำงานปัจจุบัน', 'work_permit'::text, false, 'worker',      'เอกสารสิทธิ์ทำงานปัจจุบัน ถ้ามี',                                                                     60),
      ('notify_in_form',       'แบบแจ้งเข้าทำงาน',                        null::text,        true,  'case',          'แบบฟอร์ม/มาตราที่เกี่ยวข้องต้องตรวจคู่มือจริงก่อน finalize (NEED_REVIEW)',                              70),
      ('payment_receipt',      'หลักฐานการชำระเงิน (ถ้ามี)',              'receipt'::text,   false, 'payment',       'หลักฐานการชำระเงินถ้ามี ไม่ใช่ใบเสร็จราชการ',                                                          80),
      ('ewp_request_no',       'เลขคำขอ e-WorkPermit',                    null::text,        false, 'internal',      'บันทึกเลขคำขอหลังพนักงานยื่นจริงเอง',                                                                  90),
      ('reply_document',       'หลักฐานหลังยื่น / เอกสารตอบรับจากระบบ',    null::text,        false, 'case',          'เอกสารตอบรับหลังยื่นจริง; ไม่ใช่การอนุมัติอัตโนมัติ',                                                  100),
      ('internal_note',        'หมายเหตุภายใน',                          null::text,        false, 'internal',      'หมายเหตุภายในของพนักงาน',                                                                             110)
    ) as s(item_code, name_th, doc_type, is_required, required_from, note, sort_order)
  loop
    select id into v_iid from public.case_template_checklist_items
      where template_id = v_tid and item_code = r.item_code;
    perform public.app_admin_save_case_template_item(
      v_admin_id, v_admin_username, v_iid, v_tid,
      r.item_code, r.name_th, null::text, r.doc_type, r.is_required, r.required_from, r.note, r.sort_order);
  end loop;
  raise notice 'applied EMPLOYER_NOTIFICATION_IN checklist items (tid=%)', v_tid;

  -- ===================================================================
  -- (C) EMPLOYER_NOTIFICATION_OUT — แจ้งแรงงานออก
  --     ⚠️ บต.53 / มาตรา / กรอบเวลา = NEED_REVIEW
  -- ===================================================================
  select id into v_tid from public.case_templates where template_code = 'EMPLOYER_NOTIFICATION_OUT';
  if v_tid is null then raise exception 'ไม่พบแม่แบบนำร่อง EMPLOYER_NOTIFICATION_OUT'; end if;

  for r in
    select * from (values
      ('worker_identity',      'ข้อมูลแรงงาน',                          null::text,       true,  'worker',   'ข้อมูลแรงงานที่จะแจ้งออก',                                                                          10),
      ('passport_or_ci',       'พาสปอร์ต / CI แรงงาน',                  'passport'::text, false, 'worker',   'NEED_REVIEW: จำเป็นหรือไม่ขึ้นกับทิศทางผลิตภัณฑ์ปัจจุบัน; CI ใช้แทนได้ (doc_type=passport)',            20),
      ('employer_confirmation','ข้อมูลนายจ้าง / ผู้แจ้งออก',             null::text,       true,  'employer', 'เอกสารนายจ้างอาจยังต้องทำระบบลิงก์เพิ่มก่อน (requires backend later)',                                30),
      ('out_date',             'วันที่ออก / วันสุดท้ายที่ทำงาน',         null::text,       true,  'case',     'ตอนนี้อาจยังเป็น note/manual จนกว่าจะมี field out_date (NEED_REVIEW)',                                 40),
      ('out_reason',           'เหตุผลออก',                             null::text,       true,  'case',     'ตอนนี้อาจยังเป็น note/manual จนกว่าจะมี field out_reason (NEED_REVIEW)',                               50),
      ('bt53_form',            'แบบแจ้งออก บต.53',                      null::text,       true,  'case',     'ต้องตรวจมาตรา/แบบฟอร์มกับคู่มือจริงก่อน finalize (NEED_REVIEW)',                                       60),
      ('payment_receipt',      'หลักฐานการชำระเงิน (ถ้ามี)',            'receipt'::text,  false, 'payment',  'หลักฐานการชำระเงินถ้ามี ไม่ใช่ใบเสร็จราชการ',                                                          70),
      ('ewp_request_no',       'เลขคำขอ e-WorkPermit',                  null::text,       false, 'internal', 'บันทึกเลขคำขอหลังพนักงานยื่นจริงเอง',                                                                  80),
      ('reply_document',       'หลักฐานหลังยื่น / เอกสารตอบรับจากระบบ',  null::text,       false, 'case',     'เอกสารตอบรับหลังยื่นจริง; ไม่ใช่การอนุมัติอัตโนมัติ',                                                  90),
      ('internal_note',        'หมายเหตุภายใน',                        null::text,       false, 'internal', 'หมายเหตุภายในของพนักงาน',                                                                             100)
    ) as s(item_code, name_th, doc_type, is_required, required_from, note, sort_order)
  loop
    select id into v_iid from public.case_template_checklist_items
      where template_id = v_tid and item_code = r.item_code;
    perform public.app_admin_save_case_template_item(
      v_admin_id, v_admin_username, v_iid, v_tid,
      r.item_code, r.name_th, null::text, r.doc_type, r.is_required, r.required_from, r.note, r.sort_order);
  end loop;
  raise notice 'applied EMPLOYER_NOTIFICATION_OUT checklist items (tid=%)', v_tid;

  raise notice '=== เสร็จ 5 แม่แบบนำร่อง — ยังเป็น dry-run จนกว่าจะเปลี่ยนเป็น COMMIT ===';
end $$;


-- =====================================================================
-- SECTION 2 — VERIFICATION (ยังอยู่ในทรานแซกชัน — ตรวจก่อน commit)
-- =====================================================================
-- 2.1 จำนวน item ต่อแม่แบบ (คาดหวัง: MOU 17 · IN 11 · OUT 10 อย่างน้อย
--     — อาจมากกว่าถ้ามีรายการ generic เดิม code อื่นที่ยังคงอยู่)
select t.template_code,
       count(i.*)                                          as items_total,
       count(i.*) filter (where i.is_active)               as items_active,
       count(i.*) filter (where i.is_required and i.is_active) as items_required
from public.case_templates t
left join public.case_template_checklist_items i on i.template_id = t.id
where t.template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_IN','EMPLOYER_NOTIFICATION_OUT')
group by t.template_code
order by t.template_code;

-- 2.2 item codes + owner + required + doc_type ต่อแม่แบบ (ตรวจถ้อยคำ/owner/NEED_REVIEW)
select t.template_code, i.sort_order, i.item_code, i.required_from,
       i.is_required, coalesce(i.doc_type,'∅') as doc_type,
       i.is_active, left(coalesce(i.note,''),40) as note_head
from public.case_templates t
join public.case_template_checklist_items i on i.template_id = t.id
where t.template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_IN','EMPLOYER_NOTIFICATION_OUT')
order by t.template_code, i.sort_order, i.item_code;

-- 2.3 SAFETY: owner ต้องอยู่ใน enum เท่านั้น (คาดหวัง 0 แถว)
select distinct i.required_from
from public.case_template_checklist_items i
join public.case_templates t on t.id = i.template_id
where t.template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_IN','EMPLOYER_NOTIFICATION_OUT')
  and i.required_from not in ('worker','employer','establishment','case','payment','internal');

-- 2.4 SAFETY: ยืนยัน "ไม่มีแม่แบบนอกนำร่อง" ถูกแตะรอบนี้
--     (updated_at เปลี่ยนเฉพาะรายการของ 5 code นำร่อง — ตรวจด้วยตาว่าไม่มี template อื่น)
--   select distinct t.template_code from public.case_templates t
--   join public.case_template_checklist_items i on i.template_id=t.id
--   where i.updated_at >= now() - interval '5 minutes'
--   order by t.template_code;   -- ควรเห็นเฉพาะ 5 code นำร่อง

-- =====================================================================
-- ⛔ ค่าเริ่มต้น = ROLLBACK (dry-run).
--   ถ้าผล SECTION 2 ถูกต้อง (owner ในกลุ่ม enum, ไม่มี template นอกนำร่อง,
--   จำนวน/ถ้อยคำ/NEED_REVIEW ครบ) → เปลี่ยนบรรทัดล่างจาก `rollback;` เป็น `commit;`
--   แล้วรัน SECTION 1 ใหม่ **บน STAGING เท่านั้น** · ❌ ห้าม production
-- =====================================================================
rollback;
