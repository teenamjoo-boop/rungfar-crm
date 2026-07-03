-- =============================================================
-- STAGE 54A-9A — Case Template Metadata Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * เพิ่ม "ข้อมูลเตรียมงาน" ให้แม่แบบงาน (case_templates) เพื่อเก็บอ้างอิงเชิง
--     กฎ/ขั้นตอนที่พนักงานใช้เตรียมงานก่อนไปยื่นจริงในระบบราชการ
--   * โครงสร้างพื้นฐานเท่านั้น (foundation) — ยังไม่กรอกข้อมูลกฎหมายจริง
--     ❗ ไม่ seed มติ ครม./มาตรา ปลอม — ปล่อยว่าง/ null หรือ draft placeholder เท่านั้น
--
--   ❗ additive ล้วน: เพิ่มคอลัมน์ให้ public.case_templates เท่านั้น
--     - ไม่ลบ/ไม่เปลี่ยนชื่อคอลัมน์เดิม, ไม่ UPDATE/DELETE/TRUNCATE ข้อมูลเดิม
--     - ไม่แตะ case_template_checklist_items หรือ object อื่น
--   ❗ ไม่แตะ: customers / documents / app_verify_login / app_verify_session /
--     app_log_login_event / security_login_logs / attendance / LINE inbox /
--     customer-doc-upload / import-export / delete approval / storage policies /
--     case payments/appointments/tracking
--   ❗ RPC-only ตาม pattern เดิม — ❌ ไม่ grant เขียน/อ่านตรงบนตารางให้ anon/authenticated
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
--    (add column if not exists / guarded add constraint / create or replace /
--     drop function if exists ก่อนสร้างใหม่เฉพาะตัวที่ signature/return เปลี่ยน)
-- =============================================================

-- =============================================================
-- A) เพิ่มคอลัมน์ metadata (additive, idempotent)
--    jsonb refs: default '[]' + not null → แถวเดิมได้ค่า default อัตโนมัติ
--    text notes: nullable — ว่างได้ ไม่บังคับกรอก
-- =============================================================
alter table public.case_templates
  add column if not exists cabinet_resolution_refs jsonb not null default '[]'::jsonb;
alter table public.case_templates
  add column if not exists law_refs jsonb not null default '[]'::jsonb;
alter table public.case_templates
  add column if not exists form_refs jsonb not null default '[]'::jsonb;
alter table public.case_templates
  add column if not exists eligibility_note text null;
alter table public.case_templates
  add column if not exists internal_guidance text null;
alter table public.case_templates
  add column if not exists process_summary text null;
alter table public.case_templates
  add column if not exists source_note text null;
alter table public.case_templates
  add column if not exists updated_by_code text null;

comment on column public.case_templates.cabinet_resolution_refs is
  'STAGE 54A-9A: อ้างอิงมติ ครม./มติที่เกี่ยวข้อง (ภายใน) — jsonb array เช่น [{"label":"...","date":"YYYY-MM-DD","note":"..."}]';
comment on column public.case_templates.law_refs is
  'STAGE 54A-9A: อ้างอิงมาตรา/กฎ/เงื่อนไข (ภายใน) — jsonb array เช่น [{"section":"มาตรา ...","label":"...","note":"..."}]';
comment on column public.case_templates.form_refs is
  'STAGE 54A-9A: แบบฟอร์มที่เกี่ยวข้อง (ภายใน) — jsonb array เช่น [{"code":"...","name":"...","note":"..."}]';
comment on column public.case_templates.eligibility_note is
  'STAGE 54A-9A: ใช้กับกรณีใด (short note)';
comment on column public.case_templates.internal_guidance is
  'STAGE 54A-9A: หมายเหตุเตรียมงานสำหรับพนักงาน (staff-facing)';
comment on column public.case_templates.process_summary is
  'STAGE 54A-9A: สรุปขั้นตอนโดยย่อ (plain language)';
comment on column public.case_templates.source_note is
  'STAGE 54A-9A: หมายเหตุภายในว่าข้อมูลนี้มาจากไหน เช่น "รอเติมจากคู่มือ PDF"';
comment on column public.case_templates.updated_by_code is
  'STAGE 54A-9A: username ผู้แก้ไขล่าสุด (server-stamped จาก admin RPC)';

-- =============================================================
-- A2) CHECK: บังคับให้ jsonb refs เป็น array เสมอ (guarded add — idempotent)
-- =============================================================
do $$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'case_templates_cabinet_refs_is_array'
                   and conrelid = 'public.case_templates'::regclass) then
    alter table public.case_templates
      add constraint case_templates_cabinet_refs_is_array
      check (jsonb_typeof(cabinet_resolution_refs) = 'array');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'case_templates_law_refs_is_array'
                   and conrelid = 'public.case_templates'::regclass) then
    alter table public.case_templates
      add constraint case_templates_law_refs_is_array
      check (jsonb_typeof(law_refs) = 'array');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'case_templates_form_refs_is_array'
                   and conrelid = 'public.case_templates'::regclass) then
    alter table public.case_templates
      add constraint case_templates_form_refs_is_array
      check (jsonb_typeof(form_refs) = 'array');
  end if;
end $$;

-- =============================================================
-- B) app_list_case_templates — เพิ่ม field metadata ในผลลัพธ์
--    return type เปลี่ยน (เพิ่มคอลัมน์) → ต้อง drop ก่อนสร้างใหม่
--    identity/role predicate + grant คงเดิมทุกประการ
-- =============================================================
drop function if exists public.app_list_case_templates(text, text, boolean);

create or replace function public.app_list_case_templates(
  p_user_id          text,
  p_username         text,
  p_include_inactive boolean default false
)
returns table (
  id                      bigint,
  template_code           text,
  template_name_th        text,
  template_name_en        text,
  category                text,
  description             text,
  default_case_status     text,
  is_active               boolean,
  sort_order              integer,
  checklist_count         bigint,
  cabinet_resolution_refs jsonb,
  law_refs                jsonb,
  form_refs               jsonb,
  eligibility_note        text,
  internal_guidance       text,
  process_summary         text,
  source_note             text,
  created_at              timestamptz,
  updated_at              timestamptz
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
    t.cabinet_resolution_refs, t.law_refs, t.form_refs,
    t.eligibility_note, t.internal_guidance, t.process_summary, t.source_note,
    t.created_at, t.updated_at
  from public.case_templates t
  where coalesce(p_include_inactive, false) or t.is_active
  order by t.category, t.sort_order, t.template_name_th;
end;
$$;

revoke all on function public.app_list_case_templates(text, text, boolean) from public;
grant execute on function public.app_list_case_templates(text, text, boolean) to anon, authenticated;

-- =============================================================
-- C) app_get_case_template_detail — เพิ่ม metadata ใน template object
--    return type (jsonb) ไม่เปลี่ยน → create or replace ได้เลย
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
           description, default_case_status, is_active, sort_order,
           cabinet_resolution_refs, law_refs, form_refs,
           eligibility_note, internal_guidance, process_summary, source_note,
           updated_by_code, created_at, updated_at
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
-- D) app_admin_save_case_template — เพิ่มพารามิเตอร์ metadata (admin เท่านั้น)
--    signature เปลี่ยน (เพิ่ม arg) → drop signature เดิมก่อน แล้วสร้างใหม่
--    identity/admin check + audit log pattern คงเดิม
--    * refs (jsonb): ถ้า null = ไม่แก้ / ถ้าส่งมา = ต้องเป็น array
--    * notes (text): null = ไม่แก้ / '' = ล้างเป็น null (pattern เดียวกับ description)
--    * updated_by_code = server-stamp = p_username
-- =============================================================
drop function if exists public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer
);

create or replace function public.app_admin_save_case_template(
  p_user_id                 text,
  p_username                text,
  p_template_id             bigint default null,   -- null = สร้างใหม่
  p_template_code           text default null,
  p_template_name_th        text default null,
  p_template_name_en        text default null,
  p_category                text default null,
  p_description             text default null,
  p_default_case_status     text default null,
  p_sort_order              integer default null,
  p_cabinet_resolution_refs jsonb default null,
  p_law_refs                jsonb default null,
  p_form_refs               jsonb default null,
  p_eligibility_note        text default null,
  p_internal_guidance       text default null,
  p_process_summary         text default null,
  p_source_note             text default null
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
  -- ── ตัวตน + admin เท่านั้น (server-side บังคับจริง) ──
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

  -- ── validate jsonb refs: ถ้าส่งมา ต้องเป็น array เท่านั้น ──
  if p_cabinet_resolution_refs is not null and jsonb_typeof(p_cabinet_resolution_refs) <> 'array' then
    raise exception 'invalid_cabinet_resolution_refs' using errcode = 'P0003';
  end if;
  if p_law_refs is not null and jsonb_typeof(p_law_refs) <> 'array' then
    raise exception 'invalid_law_refs' using errcode = 'P0003';
  end if;
  if p_form_refs is not null and jsonb_typeof(p_form_refs) <> 'array' then
    raise exception 'invalid_form_refs' using errcode = 'P0003';
  end if;

  if p_template_id is null then
    -- ── CREATE ──
    if v_code = '' or coalesce(btrim(p_template_name_th), '') = '' or v_cat = '' then
      raise exception 'missing_required_fields' using errcode = 'P0003';
    end if;
    insert into public.case_templates
      (template_code, template_name_th, template_name_en, category, description,
       default_case_status, sort_order,
       cabinet_resolution_refs, law_refs, form_refs,
       eligibility_note, internal_guidance, process_summary, source_note, updated_by_code)
    values
      (v_code, btrim(p_template_name_th), nullif(btrim(coalesce(p_template_name_en,'')),''),
       v_cat, nullif(btrim(coalesce(p_description,'')),''),
       case when v_status = '' then 'draft' else v_status end,
       coalesce(p_sort_order, 100),
       coalesce(p_cabinet_resolution_refs, '[]'::jsonb),
       coalesce(p_law_refs, '[]'::jsonb),
       coalesce(p_form_refs, '[]'::jsonb),
       nullif(btrim(coalesce(p_eligibility_note,'')),''),
       nullif(btrim(coalesce(p_internal_guidance,'')),''),
       nullif(btrim(coalesce(p_process_summary,'')),''),
       nullif(btrim(coalesce(p_source_note,'')),''),
       p_username)
    returning case_templates.id into v_id;
    v_action := 'case_template.create';
  else
    -- ── UPDATE — แก้เฉพาะ field ที่ส่งมา ──
    update public.case_templates t
    set template_code           = case when v_code = '' then t.template_code else v_code end,
        template_name_th        = coalesce(nullif(btrim(coalesce(p_template_name_th,'')),''), t.template_name_th),
        template_name_en        = case when p_template_name_en is null then t.template_name_en
                                       else nullif(btrim(p_template_name_en),'') end,
        category                = case when v_cat = '' then t.category else v_cat end,
        description             = case when p_description is null then t.description
                                       else nullif(btrim(p_description),'') end,
        default_case_status     = case when v_status = '' then t.default_case_status else v_status end,
        sort_order              = coalesce(p_sort_order, t.sort_order),
        cabinet_resolution_refs = coalesce(p_cabinet_resolution_refs, t.cabinet_resolution_refs),
        law_refs                = coalesce(p_law_refs, t.law_refs),
        form_refs               = coalesce(p_form_refs, t.form_refs),
        eligibility_note        = case when p_eligibility_note is null then t.eligibility_note
                                       else nullif(btrim(p_eligibility_note),'') end,
        internal_guidance       = case when p_internal_guidance is null then t.internal_guidance
                                       else nullif(btrim(p_internal_guidance),'') end,
        process_summary         = case when p_process_summary is null then t.process_summary
                                       else nullif(btrim(p_process_summary),'') end,
        source_note             = case when p_source_note is null then t.source_note
                                       else nullif(btrim(p_source_note),'') end,
        updated_by_code         = p_username,
        updated_at              = now()
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
  text, text, bigint, text, text, text, text, text, text, integer,
  jsonb, jsonb, jsonb, text, text, text, text
) from public;
grant execute on function public.app_admin_save_case_template(
  text, text, bigint, text, text, text, text, text, text, integer,
  jsonb, jsonb, jsonb, text, text, text, text
) to anon, authenticated;
