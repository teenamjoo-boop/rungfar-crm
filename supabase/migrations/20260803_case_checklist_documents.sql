-- =============================================================
-- STAGE 54A-4 — Case Checklist Instance + Link Documents (Phase 2, additive)
-- เป้าหมาย:
--   * คัดลอกเช็คลิสต์จากแม่แบบ (case_template_checklist_items) เข้าเคสจริง
--     เป็นแถว case_checklist_items ของเคสนั้น ๆ
--   * staff/admin อัปเดตสถานะ/หมายเหตุรายการเช็คลิสต์ได้
--   * "ลิงก์" เอกสารเดิมใน public.documents เข้ารายการเช็คลิสต์ (case_documents)
--     — เก็บเฉพาะ id + metadata ❌ ไม่เก็บ/ไม่คืน file_data / base64 / storage_path /
--     storage_bucket / signed URL ใด ๆ
--   * unlink = ลบเฉพาะแถวลิงก์ — ❌ ไม่ลบแถว documents / ไม่แตะไฟล์ Storage
--
--   ❗ เช็คลิสต์นี้ใช้ติดตามงานภายในบริษัทเท่านั้น — ไม่ใช่แบบฟอร์มราชการ
--     ไม่สร้าง/ไม่ปลอมเอกสารราชการ และไม่ automate เว็บราชการ e-WorkPermit
--   ❗ ไม่มีทางอัปโหลดไฟล์ใหม่ใน stage นี้ — ลิงก์เอกสารเดิมเท่านั้น
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE inbox/
--     customer-doc-upload/customer-doc-sign/import-export/delete approval/Meta/Storage
--   ❗ เขียนทุกอย่างผ่าน RPC เท่านั้น — ❌ ไม่ grant สิทธิ์ตรงบนตารางใหม่
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A1) เช็คลิสต์จริงของเคส (คัดลอกจากแม่แบบตอน init)
-- =============================================================
create table if not exists public.case_checklist_items (
  id               bigserial primary key,
  case_id          bigint not null references public.cases(id) on delete cascade,
  template_item_id bigint null references public.case_template_checklist_items(id) on delete set null,
  item_code        text not null,
  item_title_th    text not null,
  item_title_en    text null,
  doc_type         text null,
  required_from    text null,
  is_required      boolean not null default true,
  checklist_status text not null default 'missing',
  sort_order       integer not null default 100,
  note             text null,
  checked_by_code  text null,
  checked_at       timestamptz null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint case_chk_status_check check (
    checklist_status in ('missing','received','reviewing','approved',
                         'needs_fix','waived','not_required')
  )
);

comment on table public.case_checklist_items is
  'STAGE 54A-4: เช็คลิสต์จริงของเคส (คัดลอกจากแม่แบบ) — ใช้ติดตามงานภายในบริษัทเท่านั้น ไม่ใช่แบบฟอร์มราชการ. เขียนผ่าน RPC เท่านั้น (app_init_case_checklist / app_update_case_checklist_item)';

create index if not exists idx_case_chk_case_sort
  on public.case_checklist_items (case_id, sort_order);
create index if not exists idx_case_chk_case_status
  on public.case_checklist_items (case_id, checklist_status);
create index if not exists idx_case_chk_tpl_item
  on public.case_checklist_items (template_item_id);
-- กัน init ซ้ำ: 1 template item = 1 แถวต่อเคส
create unique index if not exists uq_case_chk_case_tplitem
  on public.case_checklist_items (case_id, template_item_id)
  where template_item_id is not null;
-- item_code ต่อเคสไม่ซ้ำ (แม่แบบบังคับ unique(template_id,item_code) อยู่แล้ว → ปลอดภัย)
create unique index if not exists uq_case_chk_case_code
  on public.case_checklist_items (case_id, item_code);

-- =============================================================
-- A2) ลิงก์เอกสารเดิมเข้าเช็คลิสต์ — เก็บ id + note เท่านั้น (ไม่มี path/bytes)
-- =============================================================
create table if not exists public.case_documents (
  id                     bigserial primary key,
  case_id                bigint not null references public.cases(id) on delete cascade,
  case_checklist_item_id bigint null references public.case_checklist_items(id) on delete cascade,
  document_id            bigint not null references public.documents(id) on delete cascade,
  link_note              text null,
  linked_by_code         text null,
  created_at             timestamptz not null default now()
);

comment on table public.case_documents is
  'STAGE 54A-4: ลิงก์เอกสารเดิม (public.documents) เข้าเช็คลิสต์ของเคส — เก็บเฉพาะ id/metadata ❌ ห้ามเก็บ file_data/base64/storage_path/signed URL. unlink = ลบแถวลิงก์เท่านั้น ไม่ลบเอกสารจริง';

create index if not exists idx_case_docs_case
  on public.case_documents (case_id, created_at desc);
create index if not exists idx_case_docs_chk_item
  on public.case_documents (case_checklist_item_id);
create index if not exists idx_case_docs_doc
  on public.case_documents (document_id);
create unique index if not exists uq_case_docs_link
  on public.case_documents (case_id, case_checklist_item_id, document_id);
-- กันซ้ำกรณีลิงก์ระดับเคส (ไม่ผูก item — เผื่ออนาคต; stage นี้ RPC บังคับต้องมี item)
create unique index if not exists uq_case_docs_caselevel
  on public.case_documents (case_id, document_id)
  where case_checklist_item_id is null;

-- =============================================================
-- A3) ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2/54A-3)
-- =============================================================
revoke all on table public.case_checklist_items from public, anon, authenticated;
revoke all on table public.case_documents from public, anon, authenticated;
revoke all on sequence public.case_checklist_items_id_seq from public, anon, authenticated;
revoke all on sequence public.case_documents_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_init_case_checklist — คัดลอกเช็คลิสต์จากแม่แบบเข้าเคส (รันซ้ำได้ ไม่ duplicate)
-- =============================================================
create or replace function public.app_init_case_checklist(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (case_id bigint, existing_count integer, created_count integer, total_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_case      record;
  v_existing  integer := 0;
  v_created   integer := 0;
  v_total     integer := 0;
begin
  -- ── ตัวตน: staff/admin active ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select cs.id, cs.template_id into v_case
  from public.cases cs where cs.id = p_case_id;
  if v_case.id is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;
  if v_case.template_id is null then
    raise exception 'case_has_no_template' using errcode = 'P0003';
  end if;

  select count(*)::integer into v_existing
  from public.case_checklist_items i where i.case_id = p_case_id;

  -- ── คัดลอกเฉพาะรายการ active ของแม่แบบ — on conflict do nothing = idempotent ──
  insert into public.case_checklist_items
    (case_id, template_item_id, item_code, item_title_th, item_title_en,
     doc_type, required_from, is_required, sort_order)
  select p_case_id, t.id, t.item_code, t.item_name_th, t.item_name_en,
         t.doc_type, t.required_from, t.is_required, t.sort_order
  from public.case_template_checklist_items t
  where t.template_id = v_case.template_id
    and t.is_active = true
  on conflict do nothing;
  get diagnostics v_created = row_count;

  select count(*)::integer into v_total
  from public.case_checklist_items i where i.case_id = p_case_id;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.checklist.init', 'case', p_case_id::text,
            jsonb_build_object('existing', v_existing, 'created', v_created, 'internal_only', true));
  exception when others then null;
  end;

  return query select p_case_id, v_existing, v_created, v_total;
end;
$$;

revoke all on function public.app_init_case_checklist(text, text, bigint) from public;
grant execute on function public.app_init_case_checklist(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B2) app_list_case_checklist — รายการเช็คลิสต์ + เอกสารที่ลิงก์ (metadata เท่านั้น)
--     ❌ ไม่คืน storage_path / storage_bucket / file_data / base64 / signed URL
--     has_storage เป็น boolean (pattern เดียวกับ app_list_documents 40C)
-- =============================================================
create or replace function public.app_list_case_checklist(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  id               bigint,
  case_id          bigint,
  template_item_id bigint,
  item_code        text,
  item_title_th    text,
  item_title_en    text,
  doc_type         text,
  required_from    text,
  is_required      boolean,
  checklist_status text,
  sort_order       integer,
  note             text,
  checked_by_code  text,
  checked_at       timestamptz,
  created_at       timestamptz,
  updated_at       timestamptz,
  linked_count     bigint,
  linked_docs      jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  return query
  select
    i.id, i.case_id, i.template_item_id, i.item_code, i.item_title_th, i.item_title_en,
    i.doc_type, i.required_from, i.is_required, i.checklist_status, i.sort_order,
    i.note, i.checked_by_code, i.checked_at, i.created_at, i.updated_at,
    coalesce(ld.cnt, 0) as linked_count,
    coalesce(ld.docs, '[]'::jsonb) as linked_docs
  from public.case_checklist_items i
  left join lateral (
    select count(*) as cnt,
           jsonb_agg(jsonb_build_object(
             'link_id',        l.id,
             'document_id',    d.id,
             'link_note',      l.link_note,
             'linked_by_code', l.linked_by_code,
             'linked_at',      l.created_at,
             'doc_type',       d.doc_type,
             'doc_name',       d.doc_name,
             'file_type',      d.file_type,
             'mime_type',      d.mime_type,
             'file_size',      d.file_size,
             'uploaded_by',    d.uploaded_by,
             'created_at',     d.created_at,
             'source',         d.source,
             'doc_status',     d.doc_status,
             'doc_note',       d.doc_note,
             'doc_expiry',     d.doc_expiry,
             'has_storage',    (d.storage_path is not null)
           ) order by l.created_at) as docs
    from public.case_documents l
    join public.documents d on d.id = l.document_id
    where l.case_checklist_item_id = i.id
  ) ld on true
  where i.case_id = p_case_id
  order by i.sort_order, i.item_code;
end;
$$;

revoke all on function public.app_list_case_checklist(text, text, bigint) from public;
grant execute on function public.app_list_case_checklist(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B3) app_update_case_checklist_item — staff/admin อัปเดตสถานะ/หมายเหตุ/บังคับ
--     สถานะที่ไม่ใช่ missing → ประทับ checked_by_code + checked_at
-- =============================================================
create or replace function public.app_update_case_checklist_item(
  p_user_id          text,
  p_username         text,
  p_item_id          bigint,
  p_checklist_status text default null,
  p_note             text default null,
  p_is_required      boolean default null
)
returns table (id bigint, case_id bigint, checklist_status text, updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_status    text := lower(btrim(coalesce(p_checklist_status, '')));
  v_id        bigint;
  v_case      bigint;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_status <> '' and v_status not in ('missing','received','reviewing','approved',
                                         'needs_fix','waived','not_required') then
    raise exception 'invalid_checklist_status' using errcode = 'P0003';
  end if;

  update public.case_checklist_items i
  set checklist_status = case when v_status = '' then i.checklist_status else v_status end,
      note             = case when p_note is null then i.note else nullif(btrim(p_note),'') end,
      is_required      = coalesce(p_is_required, i.is_required),
      checked_by_code  = case when v_status <> '' and v_status <> 'missing'
                              then p_username else i.checked_by_code end,
      checked_at       = case when v_status <> '' and v_status <> 'missing'
                              then now() else i.checked_at end,
      updated_at       = now()
  where i.id = p_item_id
  returning i.id, i.case_id into v_id, v_case;

  if v_id is null then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.checklist.update', 'case_checklist_item', v_id::text,
            jsonb_build_object('case_id', v_case, 'status', nullif(v_status,''), 'internal_only', true));
  exception when others then null;
  end;

  return query
  select i.id, i.case_id, i.checklist_status, i.updated_at
  from public.case_checklist_items i where i.id = v_id;
end;
$$;

revoke all on function public.app_update_case_checklist_item(text, text, bigint, text, text, boolean) from public;
grant execute on function public.app_update_case_checklist_item(text, text, bigint, text, text, boolean) to anon, authenticated;

-- =============================================================
-- B4) app_link_case_document — ลิงก์เอกสารเดิมเข้ารายการเช็คลิสต์ (idempotent)
--     เอกสารต้อง "เป็นของลูกค้าเจ้าของเคส" หรือ "เป็นเอกสารของเคสนี้เอง" เท่านั้น:
--       A) documents.customer_id = cases.customer_id
--       B) owner_type='customer' and owner_id = cases.customer_id (dual-write 54A-1B)
--       C) owner_type='case'     and owner_id = case id (รองรับอนาคต)
--     ❌ ห้ามลิงก์เอกสารของลูกค้าอื่นเข้าเคสผิดคน
-- =============================================================
create or replace function public.app_link_case_document(
  p_user_id                text,
  p_username               text,
  p_case_id                bigint,
  p_case_checklist_item_id bigint,
  p_document_id            bigint,
  p_link_note              text default null
)
returns table (id bigint, case_id bigint, case_checklist_item_id bigint, document_id bigint, already_linked boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_case      record;
  v_item      bigint;
  v_doc       bigint;
  v_link      bigint;
  v_existing  boolean := false;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select cs.id, cs.customer_id into v_case
  from public.cases cs where cs.id = p_case_id;
  if v_case.id is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  -- ── รายการเช็คลิสต์ต้องเป็นของเคสนี้จริง ──
  select i.id into v_item
  from public.case_checklist_items i
  where i.id = p_case_checklist_item_id and i.case_id = p_case_id;
  if v_item is null then
    raise exception 'item_not_in_case' using errcode = 'P0003';
  end if;

  -- ── ตรวจความเป็นเจ้าของเอกสาร (กันลิงก์เอกสารลูกค้าอื่นเข้าเคสผิดคน) ──
  select d.id into v_doc
  from public.documents d
  where d.id = p_document_id
    and (
      d.customer_id = v_case.customer_id
      or (d.owner_type = 'customer' and d.owner_id = v_case.customer_id)
      or (d.owner_type = 'case'     and d.owner_id = v_case.id)
    );
  if v_doc is null then
    raise exception 'document_not_allowed' using errcode = 'P0003';
  end if;

  -- ── insert แบบ idempotent — ลิงก์ซ้ำ = คืนแถวเดิม (already_linked=true) ──
  insert into public.case_documents
    (case_id, case_checklist_item_id, document_id, link_note, linked_by_code)
  values
    (p_case_id, v_item, v_doc, nullif(btrim(coalesce(p_link_note,'')),''), p_username)
  on conflict do nothing
  returning case_documents.id into v_link;

  if v_link is null then
    v_existing := true;
    select l.id into v_link
    from public.case_documents l
    where l.case_id = p_case_id
      and l.case_checklist_item_id = v_item
      and l.document_id = v_doc
    limit 1;
  else
    -- ── ลิงก์ใหม่สำเร็จ: รายการที่ยัง missing → ขยับเป็น received อัตโนมัติ ──
    update public.case_checklist_items i
    set checklist_status = 'received',
        checked_by_code  = p_username,
        checked_at       = now(),
        updated_at       = now()
    where i.id = v_item and i.checklist_status = 'missing';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.document.link', 'case_document', v_link::text,
            jsonb_build_object('case_id', p_case_id, 'item_id', v_item,
                               'document_id', v_doc, 'already_linked', v_existing, 'internal_only', true));
  exception when others then null;
  end;

  return query select v_link, p_case_id, v_item, v_doc, v_existing;
end;
$$;

revoke all on function public.app_link_case_document(text, text, bigint, bigint, bigint, text) from public;
grant execute on function public.app_link_case_document(text, text, bigint, bigint, bigint, text) to anon, authenticated;

-- =============================================================
-- B5) app_unlink_case_document — ลบเฉพาะแถวลิงก์
--     ❌ ไม่ลบแถว public.documents / ไม่แตะไฟล์ Storage — เอกสารจริงอยู่ครบ
-- =============================================================
create or replace function public.app_unlink_case_document(
  p_user_id  text,
  p_username text,
  p_link_id  bigint
)
returns table (link_id bigint, ok boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_link      record;
begin
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  delete from public.case_documents l
  where l.id = p_link_id
  returning l.id, l.case_id, l.document_id into v_link;

  if v_link.id is null then
    raise exception 'link_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.document.unlink', 'case_document', v_link.id::text,
            jsonb_build_object('case_id', v_link.case_id, 'document_id', v_link.document_id,
                               'document_kept', true, 'internal_only', true));
  exception when others then null;
  end;

  return query select p_link_id, true;
end;
$$;

revoke all on function public.app_unlink_case_document(text, text, bigint) from public;
grant execute on function public.app_unlink_case_document(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B6) app_case_checklist_summary — นับสถานะเช็คลิสต์ของเคส (สำหรับ card/summary)
--     complete_required = รายการบังคับที่ "จบแล้ว" (approved/waived/not_required)
-- =============================================================
create or replace function public.app_case_checklist_summary(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  total_items              bigint,
  required_items           bigint,
  missing                  bigint,
  received                 bigint,
  reviewing                bigint,
  approved                 bigint,
  needs_fix                bigint,
  waived                   bigint,
  not_required             bigint,
  linked_documents         bigint,
  complete_required_count  bigint,
  required_remaining_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  return query
  select
    count(*)                                                            as total_items,
    count(*) filter (where i.is_required)                               as required_items,
    count(*) filter (where i.checklist_status = 'missing')              as missing,
    count(*) filter (where i.checklist_status = 'received')             as received,
    count(*) filter (where i.checklist_status = 'reviewing')            as reviewing,
    count(*) filter (where i.checklist_status = 'approved')             as approved,
    count(*) filter (where i.checklist_status = 'needs_fix')            as needs_fix,
    count(*) filter (where i.checklist_status = 'waived')               as waived,
    count(*) filter (where i.checklist_status = 'not_required')         as not_required,
    (select count(*) from public.case_documents l where l.case_id = p_case_id) as linked_documents,
    count(*) filter (where i.is_required
                     and i.checklist_status in ('approved','waived','not_required')) as complete_required_count,
    count(*) filter (where i.is_required
                     and i.checklist_status not in ('approved','waived','not_required')) as required_remaining_count
  from public.case_checklist_items i
  where i.case_id = p_case_id;
end;
$$;

revoke all on function public.app_case_checklist_summary(text, text, bigint) from public;
grant execute on function public.app_case_checklist_summary(text, text, bigint) to anon, authenticated;
