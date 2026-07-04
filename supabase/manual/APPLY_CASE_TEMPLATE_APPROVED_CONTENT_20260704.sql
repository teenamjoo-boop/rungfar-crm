-- =====================================================================
-- STAGE 54A-9H — Apply Approved Template Content (MANUAL REVIEW REQUIRED)
--   ⚠️ ไฟล์นี้อยู่นอก supabase/migrations โดยตั้งใจ — ห้ามย้ายเข้า migrations
--   ⚠️ รันใน Supabase SQL Editor ด้วย role postgres (เจ้าของโปรเจกต์เท่านั้น)
--   ⚠️ Idempotent — รันซ้ำได้ (เป็น UPDATE ค่าเดิมทับค่าเดิม ปลอดภัย)
--   ⚠️ ROLLBACK-first (dry-run) — ค่าเริ่มต้นท้ายไฟล์เป็น ROLLBACK
--        ตรวจผล verification ก่อน แล้วค่อยเปลี่ยน ROLLBACK; → COMMIT; แล้วรันจริง
-- =====================================================================
-- เป้าหมาย: กรอก "ข้อมูลเตรียมงาน" (metadata) ของแม่แบบที่เจ้าของอนุมัติ (5 แม่แบบ)
--   (Stage 54A-9G ข้อ G + 54A-9H2 + 54A-9H3 owner clarification)
--     1) MOU_MYANMAR_NEW
--     2) MOU_LAOS_NEW
--     3) MOU_CAMBODIA_NEW
--     4) EMPLOYER_NOTIFICATION_OUT   (แหล่งหลัก new_01/P17, ตรงกับ P02)
--     5) EMPLOYER_NOTIFICATION_IN    (เจ้าของยืนยัน P01/P07 = แจ้งเข้า —
--                                     กรอกความหมายธุรกิจ; law/form/cabinet = NEED_REVIEW)
--   ⛔ (54A-9H3) CI_MYANMAR ถูก "เลื่อนออก" จากรอบนี้ — ไม่อยู่ใน SECTION 1
--       เหตุผล: P09/P14 คืองาน "ขึ้นทะเบียน/ขออนุญาตทำงานตามมติ ครม." ไม่ใช่ CI ล้วน
--       (แต่ละมติมีเงื่อนไข/เอกสาร/ระยะเวลา/ขั้นตอนต่างกัน) → ดูภาคผนวก C
--
-- วิธีเขียน: ผ่าน RPC public.app_admin_save_case_template (audited, admin-only)
--   — ไม่ UPDATE ตารางตรง เพื่อให้ audit log + สิทธิ์ ตรงกับ admin editor ใน CRM
--   — ส่ง NULL ให้ทุก field ที่ "ไม่แตะ" (RPC เก็บค่าเดิมไว้เมื่อ arg = NULL)
--
-- ❗ อัปเดตเฉพาะ 7 field metadata (migration 20260808):
--     cabinet_resolution_refs / law_refs / form_refs /
--     eligibility_note / internal_guidance / process_summary / source_note
--   คงเดิมทุกอย่าง: template identity (code/name/category/status/sort_order),
--   checklist items, is_active — ❌ ไม่แตะ
--
-- ❗ ห้ามเดา: ตามคำตอบเจ้าของ
--     - ค่าธรรมเนียม/ระยะเวลา = NEED_REVIEW → เก็บเป็นข้อความหมายเหตุ ไม่ใส่ตัวเลขมั่ว
--     - MOU_*: ไม่ใช่งานมติ ครม. → cabinet_resolution_refs = ว่าง '[]' (cab_n=0)
--     - EMPLOYER_NOTIFICATION_IN: law/form/cabinet ยัง NEED_REVIEW → ส่ง NULL (ไม่แตะ)
--       (ไฟล์ P01/P07 มีถ้อยคำ บต.53/แจ้งออก ปน — แบบ "แจ้งเข้า" ยังไม่ยืนยัน)
--
-- ❌ ไม่แตะ: customers / cases / payments / appointments / tracking /
--     app_users / login / attendance / storage / migrations / RLS / grants
--
-- แม่แบบที่ "ไม่กรอก" ในไฟล์นี้ (ยังไม่พร้อม):
--     CI_MYANMAR (54A-9H3 deferred — P09/P14 เป็นงานมติ ครม. ควรแยก template family ใหม่),
--     WORKER_DOCUMENT_FIX, PASSPORT_UPDATE, OTHER_LABOR_DOCUMENT (PARTIAL),
--     VISA_WP_RENEWAL, WP_RENEWAL (NEED_OCR — P10 ภาพสแกน),
--     VISA_RENEWAL, REPORT_90_DAYS, HEALTH_INSURANCE (NEED_SOURCE),
--     CHANGE_EMPLOYER, CHANGE_EMPLOYER_URGENT (PARTIAL — รอไฟล์/นิยาม)
-- =====================================================================


-- =====================================================================
-- SECTION 0 — PREVIEW (ก่อนแก้): ดูค่าปัจจุบันของ 5 แม่แบบ (ไม่เปลี่ยนข้อมูล)
--   รันส่วนนี้ก่อน เพื่อเทียบกับผลหลังแก้ใน SECTION 1
-- =====================================================================
select template_code,
       coalesce(eligibility_note,'∅')                        as eligibility_note,
       jsonb_array_length(cabinet_resolution_refs)           as cab_n,
       jsonb_array_length(law_refs)                          as law_n,
       jsonb_array_length(form_refs)                         as form_n,
       coalesce(left(process_summary,30),'∅')                as process_head,
       coalesce(source_note,'∅')                             as source_note,
       coalesce(updated_by_code,'∅')                         as updated_by
from public.case_templates
where template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_OUT','EMPLOYER_NOTIFICATION_IN')
order by template_code;


-- =====================================================================
-- SECTION 1 — APPLY (dry-run ด้วย ROLLBACK)
--   ก่อนรัน: แก้ v_admin_username ให้เป็น "username ของ admin ตัวจริง"
--   ระบบจะหา user id ให้อัตโนมัติ และเรียก RPC แบบ audited
-- =====================================================================
begin;

do $$
declare
  -- ⬇⬇⬇  แก้ตรงนี้: ใส่ username ของ admin ตัวจริง (ตรวจสิทธิ์ที่ฝั่ง RPC)  ⬇⬇⬇
  v_admin_username text := 'leejunkik2';
  -- ⬆⬆⬆ -------------------------------------------------------------- ⬆⬆⬆
  v_admin_id text;
  v_tid      bigint;

  -- ค่าที่ใช้ร่วมกันของงาน MoU (ทั้ง 3 สัญชาติใช้ชุดเดียวกัน — ตามคำตอบเจ้าของข้อ A)
  c_mou_law  jsonb := jsonb_build_array(
      jsonb_build_object('label','มาตรา 41 — สายบริษัทนำเข้ายื่น'),
      jsonb_build_object('label','มาตรา 46 — สายนายจ้างยื่นเอง'),
      jsonb_build_object('label','มาตรา 43 — แจ้งส่งมอบให้นายจ้าง'));
  c_mou_form jsonb := jsonb_build_array(
      jsonb_build_object('label','นจ.2 — คำร้องขอนำคนต่างด้าวมาทำงาน'),
      jsonb_build_object('label','บต.31 — คำขออนุญาตทำงานแทนฯ (สายบริษัทนำเข้า)'),
      jsonb_build_object('label','บต.33 — คำขออนุญาตทำงานแทนฯ (สายนายจ้าง)'),
      jsonb_build_object('label','บต.13 — แจ้งส่งมอบ MoU (มาตรา 43)'));
  c_mou_proc text :=
      '1) ยื่นคำร้องนำเข้า (นจ.2) → 2) อัปโหลด Name List ที่ประเทศต้นทางรับรอง → '
   || '3) ยื่นคำขอทำงานแทน (บต.31 บริษัทนำเข้า / บต.33 นายจ้าง) → 4) นัดหมายศูนย์แรกรับ → '
   || '5) ยื่น VISA + ใบรับรองแพทย์ + สัญญาจ้าง → 6) ยืนยันตัวตน รับใบอนุญาตทำงาน';
  c_mou_guide text :=
      'ต้องได้ Name List รับรองจากประเทศต้นทางก่อน · เอกสารประกอบส่วนใหญ่ยื่นทั้งนายจ้างและบริษัทนำเข้า · '
   || 'ค่าธรรมเนียม: NEED_REVIEW (เริ่ม ~100 บาท แล้วแต่เคส)';
  c_mou_src  text := 'คู่มือ MoU ม.41/ม.46/ม.43 ฉบับ มี.ค. 2568 (P03/P04/P06)';
begin
  -- ── หา admin id จาก username (ต้องเป็น role admin + active) ──
  select u.id::text into v_admin_id
  from public.app_users u
  where u.username = v_admin_username
    and lower(u.role) = 'admin'
    and coalesce(u.is_active, true) = true
  limit 1;

  if v_admin_id is null then
    raise exception 'ไม่พบผู้ใช้ admin ตามชื่อ "%": โปรดแก้ v_admin_username ให้ถูกต้องก่อนรัน', v_admin_username;
  end if;

  -- =========================================================
  -- 1) MOU_MYANMAR_NEW
  -- =========================================================
  select id into v_tid from public.case_templates where template_code = 'MOU_MYANMAR_NEW';
  if v_tid is null then raise exception 'ไม่พบแม่แบบ MOU_MYANMAR_NEW'; end if;
  perform public.app_admin_save_case_template(
    v_admin_id, v_admin_username, v_tid,
    null::text, null::text, null::text, null::text, null::text, null::text, null::integer, -- identity: ไม่แตะ
    '[]'::jsonb,                 -- cabinet_resolution_refs: MOU ไม่ใช่งานมติ ครม. → บังคับว่าง (cab_n=0)
    c_mou_law, c_mou_form,       -- law_refs, form_refs
    'นำเข้าแรงงาน MoU สัญชาติพม่า เข้ามาทำงานกับนายจ้างในประเทศ'::text,  -- eligibility_note
    c_mou_guide, c_mou_proc, c_mou_src);
  raise notice 'updated MOU_MYANMAR_NEW (id=%)', v_tid;

  -- =========================================================
  -- 2) MOU_LAOS_NEW
  -- =========================================================
  select id into v_tid from public.case_templates where template_code = 'MOU_LAOS_NEW';
  if v_tid is null then raise exception 'ไม่พบแม่แบบ MOU_LAOS_NEW'; end if;
  perform public.app_admin_save_case_template(
    v_admin_id, v_admin_username, v_tid,
    null::text, null::text, null::text, null::text, null::text, null::text, null::integer,
    '[]'::jsonb,                 -- cabinet_resolution_refs: MOU ไม่ใช่งานมติ ครม. → บังคับว่าง (cab_n=0)
    c_mou_law, c_mou_form,
    'นำเข้าแรงงาน MoU สัญชาติลาว เข้ามาทำงานกับนายจ้างในประเทศ'::text,
    c_mou_guide, c_mou_proc, c_mou_src);
  raise notice 'updated MOU_LAOS_NEW (id=%)', v_tid;

  -- =========================================================
  -- 3) MOU_CAMBODIA_NEW
  -- =========================================================
  select id into v_tid from public.case_templates where template_code = 'MOU_CAMBODIA_NEW';
  if v_tid is null then raise exception 'ไม่พบแม่แบบ MOU_CAMBODIA_NEW'; end if;
  perform public.app_admin_save_case_template(
    v_admin_id, v_admin_username, v_tid,
    null::text, null::text, null::text, null::text, null::text, null::text, null::integer,
    '[]'::jsonb,                 -- cabinet_resolution_refs: MOU ไม่ใช่งานมติ ครม. → บังคับว่าง (cab_n=0)
    c_mou_law, c_mou_form,
    'นำเข้าแรงงาน MoU สัญชาติกัมพูชา เข้ามาทำงานกับนายจ้างในประเทศ'::text,
    c_mou_guide, c_mou_proc, c_mou_src);
  raise notice 'updated MOU_CAMBODIA_NEW (id=%)', v_tid;

  -- =========================================================
  -- 4) EMPLOYER_NOTIFICATION_OUT  (แหล่งหลัก new_01/P17 — ตรงกับ P02)
  -- =========================================================
  select id into v_tid from public.case_templates where template_code = 'EMPLOYER_NOTIFICATION_OUT';
  if v_tid is null then raise exception 'ไม่พบแม่แบบ EMPLOYER_NOTIFICATION_OUT'; end if;
  perform public.app_admin_save_case_template(
    v_admin_id, v_admin_username, v_tid,
    null::text, null::text, null::text, null::text, null::text, null::text, null::integer,
    null::jsonb,                 -- cabinet_resolution_refs: ไม่มีมติ → ไม่แตะ
    jsonb_build_array(jsonb_build_object('label','มาตรา 13 วรรคหนึ่ง / มาตรา 46 วรรคสาม — ใช้แจ้งออก')),  -- law_refs
    jsonb_build_array(jsonb_build_object('label','บต.53 — แบบแจ้งคนต่างด้าวออกจากงาน')),                    -- form_refs
    'นายจ้างแจ้งคนต่างด้าวออกจากงาน (ลาออก / เลิกจ้าง / สิ้นสุดการจ้าง)'::text,  -- eligibility_note
    'เป็นงานแจ้ง (ไม่พบค่าธรรมเนียมในคู่มือ) · กรอบเวลาที่ต้องแจ้งหลังพนักงานออก: NEED_REVIEW'::text,        -- internal_guidance
    '1) เข้าระบบ เลือกเมนูบริการ → 2) ยื่นคำร้องแจ้งออก → 3) กรอกข้อมูล + แนบเอกสาร → 4) สรุปคำขอ → ยืนยัน'::text, -- process_summary
    'คู่มือแจ้งออก new_01/P17 (แหล่งหลัก) — เนื้อหาตรงกับ P02 · ฉบับ มี.ค. 2568'::text);  -- source_note
  raise notice 'updated EMPLOYER_NOTIFICATION_OUT (id=%)', v_tid;

  -- =========================================================
  -- 5) EMPLOYER_NOTIFICATION_IN  (54A-9H2: เจ้าของยืนยัน P01/P07 = แจ้งเข้า)
  --    ⚠️ ไฟล์ต้นทางมีถ้อยคำ บต.53/แจ้งออก ปนอยู่ → law/form/cabinet = NEED_REVIEW (ส่ง NULL)
  --       กรอกเฉพาะความหมายเชิงธุรกิจ (eligibility/process) + หมายเหตุให้ตรวจก่อน finalize
  -- =========================================================
  select id into v_tid from public.case_templates where template_code = 'EMPLOYER_NOTIFICATION_IN';
  if v_tid is null then raise exception 'ไม่พบแม่แบบ EMPLOYER_NOTIFICATION_IN'; end if;
  perform public.app_admin_save_case_template(
    v_admin_id, v_admin_username, v_tid,
    null::text, null::text, null::text, null::text, null::text, null::text, null::integer,
    null::jsonb,                 -- cabinet_resolution_refs: NEED_REVIEW → ไม่แตะ
    null::jsonb,                 -- law_refs: NEED_REVIEW (ไฟล์ปนบริบทแจ้งออก) → ไม่แตะ
    null::jsonb,                 -- form_refs: NEED_REVIEW (แบบ "แจ้งเข้า" ยังไม่ยืนยัน; ไฟล์แสดง บต.53 ของ "ออก") → ไม่แตะ
    'นายจ้างแจ้งคนต่างด้าวเข้าทำงาน'::text,  -- eligibility_note
    'เจ้าของยืนยันแม่แบบนี้ใช้กับ "แจ้งเข้า" · ⚠️ ไฟล์ต้นทาง (P01/P07) มีถ้อยคำ บต.53/แจ้งออก ปน — ต้องให้คนตรวจยืนยันมาตรา/แบบฟอร์มก่อน finalize · แบบฟอร์ม/ค่าธรรมเนียม = NEED_REVIEW'::text,  -- internal_guidance
    '1) เข้าระบบ เลือกเมนูบริการ → 2) ยื่นคำร้องแจ้งคนต่างด้าวเข้าทำงาน → 3) กรอกข้อมูล + แนบเอกสาร → 4) สรุปคำขอ → ยืนยัน'::text,  -- process_summary
    'P01/P07 (เจ้าของยืนยัน = แจ้งเข้า) ฉบับ มี.ค. 2568 — ⚠️ เนื้อไฟล์มี บต.53/แจ้งออก ปน ต้องตรวจก่อน finalize'::text);  -- source_note
  raise notice 'updated EMPLOYER_NOTIFICATION_IN (id=%)', v_tid;

  -- ⛔ CI_MYANMAR: ไม่อยู่ในรอบนี้ (54A-9H3 deferred) — ไม่เรียก RPC ให้ CI
  --    P09/P14 เป็นงาน "ขึ้นทะเบียน/ขออนุญาตทำงานตามมติ ครม." ไม่ใช่ CI ล้วน ·
  --    แต่ละมติมีเงื่อนไข/เอกสาร/ระยะเวลา/ขั้นตอนต่างกัน → ควรสร้าง template family ใหม่
  --    "ขึ้นทะเบียนใหม่ / ขออนุญาตทำงานตามมติ ครม." (1 มติ = 1 template) หลังตรวจ PDF ของมตินั้น
  --    (ดูภาคผนวก C ใน CASE_TEMPLATE_PDF_EXTRACTION_MAP.md)

  raise notice '=== เสร็จ 5 แม่แบบ (CI_MYANMAR เลื่อนออก) — ยังเป็น dry-run จนกว่าจะ COMMIT ===';
end $$;


-- ── VERIFICATION (ยังอยู่ในทรานแซกชัน) — ตรวจก่อน commit ──
select template_code,
       eligibility_note,
       jsonb_array_length(cabinet_resolution_refs) as cab_n,   -- คาดว่า 0 ทุกแถว (ไม่มีงานมติ ครม.)
       jsonb_array_length(law_refs)                as law_n,   -- MoU=3 · OUT=1 · IN=0
       jsonb_array_length(form_refs)               as form_n,  -- MoU=4 · OUT=1 · IN=0
       left(process_summary, 40)                   as process_head,
       source_note,
       updated_by_code
from public.case_templates
where template_code in
      ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
       'EMPLOYER_NOTIFICATION_OUT','EMPLOYER_NOTIFICATION_IN')
order by template_code;


-- ⛔ ค่าเริ่มต้น = ROLLBACK (dry-run). ตรวจผลด้านบนให้ครบ (5 แถว — ไม่มี CI_MYANMAR):
--     - cab_n = 0 ทุกแถว (MOU/IN/OUT ไม่ใช่งานมติ ครม.)
--     - law_n / form_n: MoU 3/4 · OUT 1/1 · IN 0/0 (NEED_REVIEW)
--     - EMPLOYER_NOTIFICATION_IN: eligibility/process มีค่า แต่ law/form ว่าง (ตั้งใจ — NEED_REVIEW)
--     - CI_MYANMAR: ไม่ปรากฏในผล (เลื่อนออกจากรอบนี้ — 54A-9H3)
--     - updated_by_code = username admin ที่ใส่
--   ถ้าถูกต้อง → เปลี่ยนบรรทัดล่างจาก ROLLBACK; เป็น COMMIT; แล้วรัน SECTION 1 อีกครั้ง
rollback;
