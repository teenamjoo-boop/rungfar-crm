-- =============================================================
-- STAGE 54A-2 — Case & Checklist Template Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * สร้าง "ข้อมูลแม่แบบงาน + เช็คลิสต์เอกสาร" ภายใน CRM สำหรับ Phase 2
--     (e-WorkPermit / case workflow ในอนาคต) — ยังไม่สร้างเคสจริงใน stage นี้
--   * ตาราง case_templates + case_template_checklist_items (ใหม่ทั้งคู่ — additive ล้วน)
--   * seed แม่แบบ "ฉบับร่างภายใน" (INTERNAL DRAFT) — แก้ไข/ปิดใช้งานได้ผ่าน admin RPC
--   * อ่าน = staff/admin ผ่าน RPC, เขียน = admin เท่านั้นผ่าน RPC (SECURITY DEFINER)
--
--   ❗ ข้อมูลนี้เป็น "เช็คลิสต์ภายในบริษัท" เท่านั้น:
--     - ไม่ใช่แบบฟอร์มราชการ, ไม่สร้าง/ไม่ปลอมเอกสารราชการใด ๆ
--     - ใช้เตือนพนักงานว่าต้องเตรียมเอกสารอะไรบ้างก่อนไปยื่นจริงเท่านั้น
--
--   ❗ ไม่แตะ: customers / documents / app_verify_login / app_verify_session /
--     app_log_login_event / security_login_logs / attendance / LINE inbox /
--     customer-doc-upload / import-export / delete approval flow
--   ❗ ไม่มี DELETE / DROP / TRUNCATE / RENAME ของ object เดิมใด ๆ
--   ❗ เขียนทุกอย่างผ่าน admin RPC เท่านั้น — ❌ ไม่ grant INSERT/UPDATE/DELETE/SELECT
--     ตรงบนตารางใหม่ให้ anon/authenticated (RPC-only ตาม pattern ปัจจุบันของโปรเจกต์)
--   ❗ soft activate/deactivate เท่านั้น — ไม่มี hard delete ใน stage นี้
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์ (create if not exists / on conflict do nothing /
--    create or replace function)
-- =============================================================

-- =============================================================
-- A1) ตารางแม่แบบงาน
-- =============================================================
create table if not exists public.case_templates (
  id                  bigserial primary key,
  template_code       text not null unique,
  template_name_th    text not null,
  template_name_en    text null,
  category            text not null,
  description         text null,
  default_case_status text not null default 'draft',
  is_active           boolean not null default true,
  sort_order          integer not null default 100,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint case_templates_category_check check (
    category in ('mou','ci','visa','work_permit','report_90',
                 'change_employer','renewal','notification','other')
  ),
  constraint case_templates_default_status_check check (
    default_case_status in ('draft','preparing_documents','ready_to_submit','submitted',
                            'waiting_result','approved','rejected','cancelled','completed')
  )
);

comment on table public.case_templates is
  'STAGE 54A-2: แม่แบบงาน Phase 2 (เช็คลิสต์ภายใน CRM เท่านั้น — ไม่ใช่เอกสารราชการ). เขียนผ่าน admin RPC เท่านั้น (app_admin_save_case_template / app_admin_set_case_template_active) — ห้าม grant เขียนตรงให้ anon/authenticated';

-- =============================================================
-- A2) ตารางรายการเช็คลิสต์ของแม่แบบ
-- =============================================================
create table if not exists public.case_template_checklist_items (
  id            bigserial primary key,
  template_id   bigint not null references public.case_templates(id) on delete cascade,
  item_code     text not null,
  item_name_th  text not null,
  item_name_en  text null,
  doc_type      text null,
  is_required   boolean not null default true,
  required_from text not null default 'worker',
  note          text null,
  sort_order    integer not null default 100,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (template_id, item_code),
  constraint case_tpl_items_required_from_check check (
    required_from in ('worker','employer','establishment','case','payment','internal')
  )
);

comment on table public.case_template_checklist_items is
  'STAGE 54A-2: รายการเช็คลิสต์ของแม่แบบงาน (ภายใน CRM เท่านั้น). เขียนผ่าน admin RPC เท่านั้น (app_admin_save_case_template_item / app_admin_set_case_template_active) — ห้าม grant เขียนตรงให้ anon/authenticated';

-- =============================================================
-- A3) Indexes
-- =============================================================
create index if not exists idx_case_templates_cat_active
  on public.case_templates (category, is_active, sort_order);

create index if not exists idx_case_tpl_items_tpl_active
  on public.case_template_checklist_items (template_id, is_active, sort_order);

-- =============================================================
-- A4) ปิดสิทธิ์ตรงทั้งหมดบนตารางใหม่ (RPC-only — pattern เดียวกับ 20260721/22/23)
--     รวม sequence ของ bigserial ด้วย (RPC เป็น SECURITY DEFINER ใช้สิทธิ์ owner เอง)
-- =============================================================
revoke all on table public.case_templates from public, anon, authenticated;
revoke all on table public.case_template_checklist_items from public, anon, authenticated;
revoke all on sequence public.case_templates_id_seq from public, anon, authenticated;
revoke all on sequence public.case_template_checklist_items_id_seq from public, anon, authenticated;

-- =============================================================
-- B) SEED — แม่แบบฉบับร่างภายใน (INTERNAL DRAFT)
--    * on conflict do nothing → รันซ้ำได้ และ "ไม่ทับ" ค่าที่ admin แก้ไปแล้ว
--    * ถ้อยคำกลาง ๆ: เอกสารแรงงาน / เอกสารนายจ้าง / หลักฐานการชำระเงิน ฯลฯ
--      ไม่ผูกรายละเอียดกฎหมาย และไม่อ้างว่า CRM ออกเอกสารราชการ
-- =============================================================
insert into public.case_templates
  (template_code, template_name_th, template_name_en, category, description, sort_order)
values
  ('MOU_MYANMAR_NEW',          'งาน MOU พม่า (นำเข้าใหม่)',        'MOU Myanmar (new)',            'mou',             'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารงาน MOU พม่า (ฉบับร่าง — แก้ไขได้)', 10),
  ('MOU_LAOS_NEW',             'งาน MOU ลาว (นำเข้าใหม่)',          'MOU Laos (new)',               'mou',             'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารงาน MOU ลาว (ฉบับร่าง — แก้ไขได้)', 20),
  ('MOU_CAMBODIA_NEW',         'งาน MOU กัมพูชา (นำเข้าใหม่)',      'MOU Cambodia (new)',           'mou',             'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารงาน MOU กัมพูชา (ฉบับร่าง — แก้ไขได้)', 30),
  ('CI_MYANMAR',               'เอกสาร CI พม่า',                    'CI Myanmar',                   'ci',              'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสาร CI (ฉบับร่าง — แก้ไขได้)', 40),
  ('VISA_WP_RENEWAL',          'ต่อวีซ่า + ใบอนุญาตทำงาน',          'Visa + work permit renewal',   'renewal',         'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารต่ออายุวีซ่าและใบอนุญาตทำงาน (ฉบับร่าง)', 50),
  ('WP_RENEWAL',               'ต่อใบอนุญาตทำงาน',                  'Work permit renewal',          'work_permit',     'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารต่อใบอนุญาตทำงาน (ฉบับร่าง)', 60),
  ('VISA_RENEWAL',             'ต่อวีซ่า',                          'Visa renewal',                 'visa',            'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารต่อวีซ่า (ฉบับร่าง)', 70),
  ('REPORT_90_DAYS',           'รายงานตัว 90 วัน',                  '90-day report',                'report_90',       'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารรายงานตัว 90 วัน (ฉบับร่าง)', 80),
  ('CHANGE_EMPLOYER',          'เปลี่ยนนายจ้าง',                    'Change employer',              'change_employer', 'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารเปลี่ยนนายจ้าง (ฉบับร่าง)', 90),
  ('CHANGE_EMPLOYER_URGENT',   'เปลี่ยนนายจ้าง (เร่งด่วน)',          'Change employer (urgent)',     'change_employer', 'แม่แบบเช็คลิสต์ภายในสำหรับงานเปลี่ยนนายจ้างแบบเร่งด่วน (ฉบับร่าง)', 100),
  ('EMPLOYER_NOTIFICATION_IN', 'แจ้งแรงงานเข้าทำงาน',               'Employer notification (in)',   'notification',    'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารแจ้งแรงงานเข้าทำงาน (ฉบับร่าง)', 110),
  ('EMPLOYER_NOTIFICATION_OUT','แจ้งแรงงานออกจากงาน',               'Employer notification (out)',  'notification',    'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารแจ้งแรงงานออกจากงาน (ฉบับร่าง)', 120),
  ('WORKER_DOCUMENT_FIX',      'แก้ไข/อัปเดตเอกสารแรงงาน',          'Worker document fix',          'other',           'แม่แบบเช็คลิสต์ภายในสำหรับติดตามการแก้ไขเอกสารแรงงาน (ฉบับร่าง)', 130),
  ('PASSPORT_UPDATE',          'อัปเดตพาสปอร์ตเล่มใหม่',            'Passport update',              'other',           'แม่แบบเช็คลิสต์ภายในสำหรับติดตามการอัปเดตพาสปอร์ตเล่มใหม่ (ฉบับร่าง)', 140),
  ('HEALTH_INSURANCE',         'ประกันสุขภาพแรงงาน',                'Health insurance',             'other',           'แม่แบบเช็คลิสต์ภายในสำหรับเตรียมเอกสารประกันสุขภาพ (ฉบับร่าง)', 150),
  ('OTHER_LABOR_DOCUMENT',     'เอกสารแรงงานอื่น ๆ',                'Other labor document',         'other',           'แม่แบบกลางสำหรับงานเอกสารแรงงานอื่น ๆ (ฉบับร่าง)', 160)
on conflict (template_code) do nothing;

-- ── เช็คลิสต์พื้นฐาน (ทุกแม่แบบ) — generic แก้ไขได้ทีหลังผ่าน admin UI ──
insert into public.case_template_checklist_items
  (template_id, item_code, item_name_th, item_name_en, doc_type, is_required, required_from, sort_order)
select t.id, s.item_code, s.name_th, s.name_en, s.doc_type, s.req, s.rfrom, s.ord
from public.case_templates t
cross join (values
  ('passport_or_ci',    'พาสปอร์ต / CI ของแรงงาน',  'Passport / CI',        'passport', true,  'worker',   10),
  ('worker_photo',      'รูปถ่ายแรงงาน',            'Worker photo',         'photo',    true,  'worker',   20),
  ('employer_documents','เอกสารนายจ้าง',            'Employer documents',   null,       true,  'employer', 30),
  ('payment_receipt',   'หลักฐานการชำระเงิน',       'Payment receipt',      'receipt',  true,  'payment',  40),
  ('appointment_date',  'วันนัด/วันยื่น',           'Appointment date',     null,       false, 'case',     80),
  ('submit_result_note','หมายเหตุผลการยื่น',        'Submission result note', null,     false, 'internal', 90)
) as s(item_code, name_th, name_en, doc_type, req, rfrom, ord)
on conflict (template_id, item_code) do nothing;

-- ── รายการเพิ่มเติม: งานต่ออายุ/รายงานตัว — ต้องมีใบอนุญาตทำงานเดิม + หน้าวีซ่า ──
insert into public.case_template_checklist_items
  (template_id, item_code, item_name_th, item_name_en, doc_type, is_required, required_from, sort_order)
select t.id, s.item_code, s.name_th, s.name_en, s.doc_type, s.req, s.rfrom, s.ord
from public.case_templates t
cross join (values
  ('work_permit', 'ใบอนุญาตทำงาน (เดิม)', 'Work permit (current)', 'work_permit', true, 'worker', 12),
  ('visa_page',   'หน้าวีซ่าล่าสุด',       'Latest visa page',      'visa',        true, 'worker', 14)
) as s(item_code, name_th, name_en, doc_type, req, rfrom, ord)
where t.template_code in ('VISA_WP_RENEWAL','WP_RENEWAL','VISA_RENEWAL','REPORT_90_DAYS','CHANGE_EMPLOYER','CHANGE_EMPLOYER_URGENT')
on conflict (template_id, item_code) do nothing;

-- ── รายการเพิ่มเติม: MOU / เปลี่ยนนายจ้าง / แจ้งเข้า-ออก — เอกสารฝั่งบริษัท ──
insert into public.case_template_checklist_items
  (template_id, item_code, item_name_th, item_name_en, doc_type, is_required, required_from, sort_order)
select t.id, s.item_code, s.name_th, s.name_en, s.doc_type, s.req, s.rfrom, s.ord
from public.case_templates t
cross join (values
  ('company_certificate','หนังสือรับรองบริษัท',  'Company certificate', null, true, 'employer', 32),
  ('power_of_attorney',  'หนังสือมอบอำนาจ',      'Power of attorney',   null, true, 'employer', 34)
) as s(item_code, name_th, name_en, doc_type, req, rfrom, ord)
where t.template_code in ('MOU_MYANMAR_NEW','MOU_LAOS_NEW','MOU_CAMBODIA_NEW',
                          'CHANGE_EMPLOYER','CHANGE_EMPLOYER_URGENT',
                          'EMPLOYER_NOTIFICATION_IN','EMPLOYER_NOTIFICATION_OUT')
on conflict (template_id, item_code) do nothing;

-- =============================================================
-- C1) app_list_case_templates — staff/admin อ่านรายการแม่แบบ + จำนวนเช็คลิสต์
-- =============================================================
create or replace function public.app_list_case_templates(
  p_user_id          text,
  p_username         text,
  p_include_inactive boolean default false
)
returns table (
  id                  bigint,
  template_code       text,
  template_name_th    text,
  template_name_en    text,
  category            text,
  description         text,
  default_case_status text,
  is_active           boolean,
  sort_order          integer,
  checklist_count     bigint,
  created_at          timestamptz,
  updated_at          timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  -- ── ตัวตน: ผู้ใช้ active (staff/admin) — predicate เดียวกับ RPC อื่นของระบบ ──
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select
    t.id, t.template_code, t.template_name_th, t.template_name_en,
    t.category, t.description, t.default_case_status,
    t.is_active, t.sort_order,
    (select count(*) from public.case_template_checklist_items i
      where i.template_id = t.id
        and (coalesce(p_include_inactive, false) or i.is_active)) as checklist_count,
    t.created_at, t.updated_at
  from public.case_templates t
  where coalesce(p_include_inactive, false) or t.is_active
  order by t.category, t.sort_order, t.template_name_th;
end;
$$;

revoke all on function public.app_list_case_templates(text, text, boolean) from public;
grant execute on function public.app_list_case_templates(text, text, boolean) to anon, authenticated;

-- =============================================================
-- C2) app_get_case_template_detail — staff/admin อ่านแม่แบบ + รายการเช็คลิสต์
-- =============================================================
create or replace function public.app_get_case_template_detail(
  p_user_id     text,
  p_username    text,
  p_template_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok       boolean := false;
  v_template jsonb;
  v_items    jsonb;
begin
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select to_jsonb(t) into v_template
  from (
    select id, template_code, template_name_th, template_name_en, category,
           description, default_case_status, is_active, sort_order, created_at, updated_at
    from public.case_templates
    where id = p_template_id
  ) t;

  if v_template is null then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.sort_order, i.item_code), '[]'::jsonb)
    into v_items
  from (
    select id, template_id, item_code, item_name_th, item_name_en, doc_type,
           is_required, required_from, note, sort_order, is_active, created_at, updated_at
    from public.case_template_checklist_items
    where template_id = p_template_id
  ) i;

  return jsonb_build_object('template', v_template, 'items', v_items);
end;
$$;

revoke all on function public.app_get_case_template_detail(text, text, bigint) from public;
grant execute on function public.app_get_case_template_detail(text, text, bigint) to anon, authenticated;

-- =============================================================
-- C3) app_admin_save_case_template — admin เท่านั้น: สร้าง/แก้ไข metadata แม่แบบ
--     * create: ต้องมี code + name_th + category
--     * update: แก้เฉพาะ field ที่ส่งมา (ไม่ null) — server-stamp updated_at เสมอ
--     * audit log ฝั่ง server แบบ best-effort (pattern เดียวกับ 20260728)
-- =============================================================
create or replace function public.app_admin_save_case_template(
  p_user_id             text,
  p_username            text,
  p_template_id         bigint default null,   -- null = สร้างใหม่
  p_template_code       text default null,
  p_template_name_th    text default null,
  p_template_name_en    text default null,
  p_category            text default null,
  p_description         text default null,
  p_default_case_status text default null,
  p_sort_order          integer default null
)
returns table (id bigint, template_code text, template_name_th text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_code      text := upper(btrim(coalesce(p_template_code, '')));
  v_cat       text := lower(btrim(coalesce(p_category, '')));
  v_status    text := lower(btrim(coalesce(p_default_case_status, '')));
  v_id        bigint;
  v_action    text;
begin
  -- ── ตัวตน + admin เท่านั้น (server-side บังคับจริง ไม่ใช่แค่ซ่อนปุ่ม) ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate ค่า enum (เฉพาะเมื่อส่งมา) ──
  if v_cat <> '' and v_cat not in ('mou','ci','visa','work_permit','report_90',
                                   'change_employer','renewal','notification','other') then
    raise exception 'invalid_category' using errcode = 'P0003';
  end if;
  if v_status <> '' and v_status not in ('draft','preparing_documents','ready_to_submit','submitted',
                                         'waiting_result','approved','rejected','cancelled','completed') then
    raise exception 'invalid_default_case_status' using errcode = 'P0003';
  end if;
  if v_code <> '' and v_code !~ '^[A-Z0-9_]{2,60}$' then
    raise exception 'invalid_template_code' using errcode = 'P0003';
  end if;

  if p_template_id is null then
    -- ── CREATE ──
    if v_code = '' or coalesce(btrim(p_template_name_th), '') = '' or v_cat = '' then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    insert into public.case_templates
      (template_code, template_name_th, template_name_en, category, description,
       default_case_status, sort_order)
    values
      (v_code, btrim(p_template_name_th), nullif(btrim(coalesce(p_template_name_en,'')),''),
       v_cat, nullif(btrim(coalesce(p_description,'')),''),
       case when v_status = '' then 'draft' else v_status end,
       coalesce(p_sort_order, 100))
    returning case_templates.id into v_id;
    v_action := 'case_template.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา ──
    update public.case_templates t
    set template_code       = case when v_code = '' then t.template_code else v_code end,
        template_name_th    = coalesce(nullif(btrim(coalesce(p_template_name_th,'')),''), t.template_name_th),
        template_name_en    = case when p_template_name_en is null then t.template_name_en
                                   else nullif(btrim(p_template_name_en),'') end,
        category            = case when v_cat = '' then t.category else v_cat end,
        description         = case when p_description is null then t.description
                                   else nullif(btrim(p_description),'') end,
        default_case_status = case when v_status = '' then t.default_case_status else v_status end,
        sort_order          = coalesce(p_sort_order, t.sort_order),
        updated_at          = now()
    where t.id = p_template_id
    returning t.id into v_id;

    if v_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    v_action := 'case_template.update';
  end if;

  -- ── audit log ฝั่ง server (best-effort — พังไม่ทำให้ save ล้ม) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_template', v_id::text,
            jsonb_build_object('template_code', v_code, 'category', v_cat, 'internal_draft', true));
  exception when others then null;
  end;

  return query
  select t.id, t.template_code, t.template_name_th
  from public.case_templates t where t.id = v_id;
end;
$$;

revoke all on function public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer
) from public;
grant execute on function public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer
) to anon, authenticated;

-- =============================================================
-- C4) app_admin_save_case_template_item — admin เท่านั้น: สร้าง/แก้ไขรายการเช็คลิสต์
-- =============================================================
create or replace function public.app_admin_save_case_template_item(
  p_user_id       text,
  p_username      text,
  p_item_id       bigint default null,   -- null = สร้างใหม่
  p_template_id   bigint default null,   -- จำเป็นตอนสร้าง
  p_item_code     text default null,
  p_item_name_th  text default null,
  p_item_name_en  text default null,
  p_doc_type      text default null,
  p_is_required   boolean default null,
  p_required_from text default null,
  p_note          text default null,
  p_sort_order    integer default null
)
returns table (id bigint, template_id bigint, item_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_code      text := lower(btrim(coalesce(p_item_code, '')));
  v_from      text := lower(btrim(coalesce(p_required_from, '')));
  v_doc       text := nullif(btrim(coalesce(p_doc_type, '')), '');
  v_id        bigint;
  v_tpl       bigint;
  v_action    text;
begin
  -- ── ตัวตน + admin เท่านั้น ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate ──
  if v_from <> '' and v_from not in ('worker','employer','establishment','case','payment','internal') then
    raise exception 'invalid_required_from' using errcode = 'P0003';
  end if;
  if v_code <> '' and v_code !~ '^[a-z0-9_]{2,60}$' then
    raise exception 'invalid_item_code' using errcode = 'P0003';
  end if;
  if v_doc is not null and length(v_doc) > 60 then
    raise exception 'invalid_doc_type' using errcode = 'P0003';
  end if;

  if p_item_id is null then
    -- ── CREATE — ต้องระบุ template ที่มีอยู่จริง + code + ชื่อไทย ──
    if p_template_id is null or v_code = '' or coalesce(btrim(p_item_name_th), '') = '' then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    select t.id into v_tpl from public.case_templates t where t.id = p_template_id;
    if v_tpl is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    insert into public.case_template_checklist_items
      (template_id, item_code, item_name_th, item_name_en, doc_type,
       is_required, required_from, note, sort_order)
    values
      (v_tpl, v_code, btrim(p_item_name_th),
       nullif(btrim(coalesce(p_item_name_en,'')),''), v_doc,
       coalesce(p_is_required, true),
       case when v_from = '' then 'worker' else v_from end,
       nullif(btrim(coalesce(p_note,'')),''),
       coalesce(p_sort_order, 100))
    returning case_template_checklist_items.id into v_id;
    v_action := 'case_template_item.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา (template_id ของ item เดิมไม่ย้าย) ──
    update public.case_template_checklist_items i
    set item_code     = case when v_code = '' then i.item_code else v_code end,
        item_name_th  = coalesce(nullif(btrim(coalesce(p_item_name_th,'')),''), i.item_name_th),
        item_name_en  = case when p_item_name_en is null then i.item_name_en
                             else nullif(btrim(p_item_name_en),'') end,
        doc_type      = case when p_doc_type is null then i.doc_type else v_doc end,
        is_required   = coalesce(p_is_required, i.is_required),
        required_from = case when v_from = '' then i.required_from else v_from end,
        note          = case when p_note is null then i.note else nullif(btrim(p_note),'') end,
        sort_order    = coalesce(p_sort_order, i.sort_order),
        updated_at    = now()
    where i.id = p_item_id
    returning i.id, i.template_id into v_id, v_tpl;

    if v_id is null then
      raise exception 'item_not_found' using errcode = 'P0002';
    end if;
    v_action := 'case_template_item.update';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_template_item', v_id::text,
            jsonb_build_object('template_id', v_tpl, 'item_code', v_code, 'internal_draft', true));
  exception when others then null;
  end;

  return query
  select i.id, i.template_id, i.item_code
  from public.case_template_checklist_items i where i.id = v_id;
end;
$$;

revoke all on function public.app_admin_save_case_template_item(
  text, text, bigint, bigint, text, text, text, text, boolean, text, text, integer
) from public;
grant execute on function public.app_admin_save_case_template_item(
  text, text, bigint, bigint, text, text, text, text, boolean, text, text, integer
) to anon, authenticated;

-- =============================================================
-- C5) app_admin_set_case_template_active — admin เท่านั้น: soft เปิด/ปิดใช้งาน
--     p_target = 'template' | 'item' — ❌ ไม่มี hard delete ใน stage นี้
-- =============================================================
create or replace function public.app_admin_set_case_template_active(
  p_user_id   text,
  p_username  text,
  p_target    text,
  p_id        bigint,
  p_is_active boolean
)
returns table (id bigint, target text, is_active boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_target    text := lower(btrim(coalesce(p_target, '')));
  v_id        bigint;
begin
  -- ── ตัวตน + admin เท่านั้น ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_target not in ('template', 'item') or p_id is null or p_is_active is null then
    raise exception 'invalid_arguments' using errcode = 'P0003';
  end if;

  if v_target = 'template' then
    update public.case_templates t
    set is_active = p_is_active, updated_at = now()
    where t.id = p_id
    returning t.id into v_id;
  else
    update public.case_template_checklist_items i
    set is_active = p_is_active, updated_at = now()
    where i.id = p_id
    returning i.id into v_id;
  end if;

  if v_id is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role,
            case when v_target = 'template' then 'case_template.set_active' else 'case_template_item.set_active' end,
            case when v_target = 'template' then 'case_template' else 'case_template_item' end,
            v_id::text,
            jsonb_build_object('is_active', p_is_active, 'soft_toggle', true));
  exception when others then null;
  end;

  return query select v_id, v_target, p_is_active;
end;
$$;

revoke all on function public.app_admin_set_case_template_active(text, text, text, bigint, boolean) from public;
grant execute on function public.app_admin_set_case_template_active(text, text, text, bigint, boolean) to anon, authenticated;
