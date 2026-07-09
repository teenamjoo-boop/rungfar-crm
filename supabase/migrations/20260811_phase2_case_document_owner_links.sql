-- =============================================================
-- STAGE 58K-A — Phase 2: Case Document Owner-Link Attribution
--   (additive, RPC-only) — checklist link รู้ "เจ้าของเอกสาร" + รองรับ Name List
--
-- เป้าหมาย (scope แคบ — เฉพาะ owner attribution ของลิงก์เช็กลิสต์):
--   * เพิ่มคอลัมน์ attribution (nullable) ใน public.case_documents —
--     ลิงก์เดิมทุกแถวยังถูกต้อง (คอลัมน์ใหม่เป็น null = legacy link)
--   * ขยาย allowlist ของ app_link_case_document แบบ additive:
--       - แรงงานรองใน Name List (case_workers active ของเคสเดียวกัน — 58H)
--       - เอกสารนายจ้างของเคส (owner_type='employer' + owner_id = cases.employer_id)
--       - หลักฐานชำระเงินของเคส (อ้าง case_payments.proof_document_id เดิม — ไม่แทนที่)
--       - หลักฐานภายใน/ของเคส (owner_type='case' เดิม)
--     ❗ สถานประกอบการ = ยังไม่เปิด (cases ไม่มี establishment_id — สัญญา §C/§F เลื่อน)
--   * ขยาย linked_docs ของ app_list_case_checklist แบบ additive (เพิ่ม key ใหม่เท่านั้น)
--
--   ผูกกับแผน/ผลตรวจ:
--     - 58K-RESET-1 audit → decision B) SAFE_TO_DESIGN_58K_BACKEND_MIGRATION_NEXT
--     - 20260803_case_checklist_documents.sql  (นิยามเดิมที่ replace ที่นี่)
--     - 20260731_documents_owner_generalization.sql  (documents.owner_type/owner_id)
--     - 20260810_phase2_case_workers_foundation.sql  (case_workers / Name List)
--
--   ❗ นโยบายความปลอดภัย (รักษา pattern เดิม 54A-2..7 / 58H ทุกข้อ):
--     - RPC-only: ตาราง case_documents ถูก revoke ตรงอยู่แล้ว (20260803) — ไม่เปิด grant ใหม่
--     - SECURITY DEFINER + set search_path = public + identity predicate เดิม
--     - รู้ document_id อย่างเดียว "ลิงก์ไม่ได้" — เอกสารต้องเป็นของ
--       ลูกค้าหลักของเคส / แรงงาน active ใน Name List ของเคส / นายจ้างของเคส /
--       เคสเอง / หลักฐานชำระเงินของเคสเดียวกัน เท่านั้น
--     - Metadata-only: ❌ ไม่คืน file_data / base64 / storage_path / signed URL
--     - unlink (app_unlink_case_document) ไม่แตะ — semantics เดิมทุกประการ
--     - Additive + Idempotent: add column if not exists / guarded constraint /
--       drop old signature ก่อน create ใหม่ (pattern 45B / 54A-1B) — รันซ้ำได้ทั้งไฟล์
--     - Audit best-effort: audit_logs เดิม + เติม attribution ใน detail
--
--   ❗ ไม่แตะ: Storage / Edge Function / RLS / login / LINE / attendance / Meta /
--     import-export / delete safety / app_create_case / app_init_case_checklist /
--     app_unlink_case_document / case_payments.proof_document_id (ช่องทางเดิมคงอยู่)
--   ❗ ไม่มี official document generation / ไม่มี e-WorkPermit automation —
--     เช็กลิสต์นี้ติดตามงานภายในบริษัทเท่านั้น
--
-- ⚠️ DO NOT APPLY ที่นี่ — ร่างเพื่อรีวิว → apply บน staging ก่อนเสมอ หลัง backup + อนุมัติ
-- =============================================================

-- =============================================================
-- A) คอลัมน์ attribution ใหม่บน public.case_documents (nullable ทั้งหมด — additive)
--    * linked_owner_type: เจ้าของที่ "ตั้งใจ" ให้เอกสารนี้ตอบ (ตาม required_from ของ item)
--    * linked_owner_id:   id ของเจ้าของตามชนิด (customer id / employer id / case id ฯลฯ)
--    * linked_case_worker_id: แถว case_workers (58H) เมื่อเป็นเอกสารของแรงงานใน Name List
--      — FK on delete set null: ถ้าแถวแรงงานหายไป (cascade จากเคส) ลิงก์เอกสารไม่พังตาม
--    * แถว legacy (ค่า null ทั้งสาม) = ลิงก์แบบเดิม — ทำงานเหมือนเดิมทุกประการ
-- =============================================================
alter table public.case_documents
  add column if not exists linked_owner_type text null;

alter table public.case_documents
  add column if not exists linked_owner_id bigint null;

alter table public.case_documents
  add column if not exists linked_case_worker_id bigint null;

-- FK ไป case_workers — guarded (idempotent) + ไม่กระทบแถวเดิม (ค่า null ผ่าน FK เสมอ)
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname  = 'case_documents_linked_case_worker_fk'
      and conrelid = 'public.case_documents'::regclass
  ) then
    alter table public.case_documents
      add constraint case_documents_linked_case_worker_fk
      foreign key (linked_case_worker_id) references public.case_workers(id)
      on delete set null;
  end if;
end$$;

-- CHECK ค่า linked_owner_type — null ได้เสมอ (legacy) → non-breaking
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname  = 'case_documents_linked_owner_type_check'
      and conrelid = 'public.case_documents'::regclass
  ) then
    alter table public.case_documents
      add constraint case_documents_linked_owner_type_check
      check (
        linked_owner_type is null
        or linked_owner_type in ('customer','worker','employer','establishment',
                                 'case','payment','internal')
      );
  end if;
end$$;

comment on column public.case_documents.linked_owner_type is
  'STAGE 58K-A: เจ้าของเอกสารที่ลิงก์นี้ตอบ (customer/worker/employer/establishment/case/payment/internal). null = ลิงก์ legacy ก่อน 58K — ใช้กติกาเดิม (ลูกค้าหลัก/เคส)';
comment on column public.case_documents.linked_owner_id is
  'STAGE 58K-A: id ของเจ้าของตาม linked_owner_type (customer id / employer id / case id). null = legacy';
comment on column public.case_documents.linked_case_worker_id is
  'STAGE 58K-A: แถว public.case_workers (58H) เมื่อเอกสารเป็นของแรงงานใน Name List — attribution รายแรงงาน. null = legacy/ไม่ระบุแรงงาน';

-- ── ดัชนีใหม่ (ของเดิม idx_case_docs_case / _chk_item / _doc มีแล้วใน 20260803) ──
create index if not exists idx_case_docs_linked_owner
  on public.case_documents (linked_owner_type, linked_owner_id);
create index if not exists idx_case_docs_linked_worker
  on public.case_documents (linked_case_worker_id)
  where linked_case_worker_id is not null;

-- =============================================================
-- B1) app_link_case_document — ขยาย allowlist + attribution (แทนที่นิยาม 20260803 B4)
--     * ลาก signature ใหม่: พารามิเตอร์เดิม 6 ตัวครบ ลำดับเดิม + 3 ตัวใหม่ default null ท้ายสุด
--       → ต้อง drop signature เดิมก่อน (กัน PostgREST เจอ overload กำกวม — pattern 45B/54A-1B)
--       → frontend เดิมที่เรียกด้วยพารามิเตอร์เดิมทำงานเหมือนเดิมทุกประการ (แขนง legacy)
--
--     กติกาความเป็นเจ้าของ (document ต้องผ่านข้อใดข้อหนึ่ง — ตามแขนงที่ขอ):
--       [legacy — ไม่ส่ง p_linked_* เลย] กติกาเดิม 20260803 เป๊ะ:
--         d.customer_id = cases.customer_id
--         or (d.owner_type='customer' and d.owner_id = cases.customer_id)
--         or (d.owner_type='case'     and d.owner_id = cases.id)
--       [worker/customer + p_linked_case_worker_id] แรงงานใน Name List:
--         แถว case_workers ต้องเป็นของเคสนี้ + is_active — เอกสารต้องเป็นของ
--         customer_id ของแรงงานคนนั้น (legacy customer_id หรือ owner_type='customer')
--       [worker/customer โดยไม่ระบุแรงงาน] = แรงงานหลักเดิม (cases.customer_id)
--       [employer] เคสต้องมี employer_id — เอกสารต้อง owner_type='employer'
--         and owner_id = cases.employer_id เท่านั้น (นายจ้างเคสอื่นลิงก์ไม่ได้)
--       [case / internal] owner_type='case' and owner_id = cases.id
--         (หลักฐานภายใน = เอกสารของเคสเอง — ไม่เปิด visibility กว้างกว่านี้)
--       [payment] เอกสารของเคสเอง หรือเอกสารที่เป็น proof_document_id ของ
--         case_payments แถวใดแถวหนึ่ง "ของเคสเดียวกัน" (อ้างช่องทางเดิม 20260805 —
--         ไม่แทนที่/ไม่แก้ proof_document_id)
--       [establishment] ❌ ยังไม่เปิด — cases ไม่มี establishment_id (สัญญา §C/§F)
--         → raise owner_link_not_supported (frontend 57L guard แสดงอ่านอย่างเดียวอยู่แล้ว)
--
--     idempotency: unique (case_id, case_checklist_item_id, document_id) เดิมคุมอยู่ —
--       ลิงก์ซ้ำคืน already_linked=true และ "ไม่แก้ไข" attribution ของแถวเดิม
--     พฤติกรรมเดิมคงไว้: ลิงก์ใหม่สำเร็จ → item ที่ยัง missing ขยับเป็น received
-- =============================================================
drop function if exists public.app_link_case_document(text, text, bigint, bigint, bigint, text);

create or replace function public.app_link_case_document(
  p_user_id                text,
  p_username               text,
  p_case_id                bigint,
  p_case_checklist_item_id bigint,
  p_document_id            bigint,
  p_link_note              text default null,
  p_linked_owner_type      text default null,   -- ใหม่ 58K-A
  p_linked_owner_id        bigint default null, -- ใหม่ 58K-A (ผู้เรียกส่งได้ แต่ server คำนวณ/ตรวจเองเสมอ)
  p_linked_case_worker_id  bigint default null  -- ใหม่ 58K-A (Name List worker attribution)
)
returns table (id bigint, case_id bigint, case_checklist_item_id bigint, document_id bigint, already_linked boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role       text;
  v_full_name  text;
  v_case       record;
  v_item       bigint;
  v_doc        bigint;
  v_link       bigint;
  v_existing   boolean := false;
  v_ltype      text := lower(btrim(coalesce(p_linked_owner_type, '')));
  v_worker     record;
  v_owner_id   bigint := null;  -- ค่า attribution ที่ server ตัดสิน (ไม่เชื่อ p_linked_owner_id ดิบ)
  v_worker_id  bigint := null;
begin
  -- ── ตัวตน: staff/admin active (predicate เดียวกับ 54A-3/4/6/7 และ 58H) ──
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

  -- ── ตรวจค่า linked_owner_type — '' = legacy (ไม่ระบุ), ค่าผิด → raise ──
  if v_ltype not in ('', 'customer', 'worker', 'employer', 'establishment',
                     'case', 'payment', 'internal') then
    raise exception 'invalid_owner_link_type' using errcode = 'P0003';
  end if;

  -- ── สถานประกอบการ: ยังไม่มี binding เคส↔สถานประกอบการ → ยังไม่เปิด (เลื่อน 58L+) ──
  if v_ltype = 'establishment' then
    raise exception 'owner_link_not_supported' using errcode = 'P0003';
  end if;

  select cs.id, cs.customer_id, cs.employer_id into v_case
  from public.cases cs where cs.id = p_case_id;
  if v_case.id is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  -- ── รายการเช็คลิสต์ต้องเป็นของเคสนี้จริง (เหมือนเดิม) ──
  select i.id into v_item
  from public.case_checklist_items i
  where i.id = p_case_checklist_item_id and i.case_id = p_case_id;
  if v_item is null then
    raise exception 'item_not_in_case' using errcode = 'P0003';
  end if;

  -- ── แขนงแรงงานใน Name List: ตรวจแถว case_workers ก่อน (ต้องเป็นของเคสนี้ + active) ──
  if p_linked_case_worker_id is not null then
    if v_ltype not in ('', 'customer', 'worker') then
      -- ระบุแรงงานพร้อมชนิดเจ้าของอื่น = คำขอขัดแย้งกันเอง
      raise exception 'invalid_owner_link_type' using errcode = 'P0003';
    end if;
    select w.id, w.customer_id, w.is_active into v_worker
    from public.case_workers w
    where w.id = p_linked_case_worker_id and w.case_id = p_case_id;
    if v_worker.id is null then
      raise exception 'case_worker_not_in_case' using errcode = 'P0003';
    end if;
    if not v_worker.is_active then
      raise exception 'case_worker_inactive' using errcode = 'P0003';
    end if;
  end if;

  -- ── ตรวจความเป็นเจ้าของเอกสาร (ห้ามลิงก์เพียงเพราะรู้ document_id) ──
  if p_linked_case_worker_id is not null then
    -- [worker ราย Name List] เอกสารต้องเป็นของ customer ของแรงงานคนนั้นเท่านั้น
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and (
        d.customer_id = v_worker.customer_id
        or (d.owner_type = 'customer' and d.owner_id = v_worker.customer_id)
      );
    v_owner_id  := v_worker.customer_id;
    v_worker_id := v_worker.id;
    if v_ltype = '' then v_ltype := 'worker'; end if;

  elsif v_ltype in ('customer', 'worker') then
    -- [แรงงานหลักเดิม] cases.customer_id ยังเป็น authoritative
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and (
        d.customer_id = v_case.customer_id
        or (d.owner_type = 'customer' and d.owner_id = v_case.customer_id)
      );
    v_owner_id := v_case.customer_id;

  elsif v_ltype = 'employer' then
    -- [นายจ้างของเคสนี้เท่านั้น] — เคสไม่ผูกนายจ้าง = ลิงก์ไม่ได้
    if v_case.employer_id is null then
      raise exception 'case_has_no_employer' using errcode = 'P0003';
    end if;
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and d.owner_type = 'employer' and d.owner_id = v_case.employer_id;
    v_owner_id := v_case.employer_id;

  elsif v_ltype in ('case', 'internal') then
    -- [เอกสาร/หลักฐานภายในของเคสเอง]
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and d.owner_type = 'case' and d.owner_id = v_case.id;
    v_owner_id := v_case.id;

  elsif v_ltype = 'payment' then
    -- [หลักฐานชำระเงิน] เอกสารของเคสเอง หรือ proof ของ case_payments เคสเดียวกัน
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and (
        (d.owner_type = 'case' and d.owner_id = v_case.id)
        or exists (
          select 1 from public.case_payments cp
          where cp.case_id = v_case.id and cp.proof_document_id = d.id
        )
      );
    v_owner_id := v_case.id;

  else
    -- [legacy — ไม่ส่ง p_linked_* เลย] กติกาเดิม 20260803 ทุกประการ, attribution คง null
    select d.id into v_doc
    from public.documents d
    where d.id = p_document_id
      and (
        d.customer_id = v_case.customer_id
        or (d.owner_type = 'customer' and d.owner_id = v_case.customer_id)
        or (d.owner_type = 'case'     and d.owner_id = v_case.id)
      );
  end if;

  if v_doc is null then
    raise exception 'document_not_allowed' using errcode = 'P0003';
  end if;

  -- ── insert แบบ idempotent — ลิงก์ซ้ำ = คืนแถวเดิม (ไม่แก้ attribution เดิม) ──
  insert into public.case_documents
    (case_id, case_checklist_item_id, document_id, link_note, linked_by_code,
     linked_owner_type, linked_owner_id, linked_case_worker_id)
  values
    (p_case_id, v_item, v_doc, nullif(btrim(coalesce(p_link_note,'')),''), p_username,
     nullif(v_ltype,''), v_owner_id, v_worker_id)
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
    -- ── ลิงก์ใหม่สำเร็จ: รายการที่ยัง missing → ขยับเป็น received (เหมือนเดิม) ──
    update public.case_checklist_items i
    set checklist_status = 'received',
        checked_by_code  = p_username,
        checked_at       = now(),
        updated_at       = now()
    where i.id = v_item and i.checklist_status = 'missing';
  end if;

  -- ── audit log ฝั่ง server (best-effort — เติม attribution ใน detail) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.document.link', 'case_document', v_link::text,
            jsonb_build_object('case_id', p_case_id, 'item_id', v_item,
                               'document_id', v_doc, 'already_linked', v_existing,
                               'linked_owner_type', nullif(v_ltype,''),
                               'linked_owner_id', v_owner_id,
                               'linked_case_worker_id', v_worker_id,
                               'internal_only', true));
  exception when others then null;
  end;

  return query select v_link, p_case_id, v_item, v_doc, v_existing;
end;
$$;

revoke all on function public.app_link_case_document(
  text, text, bigint, bigint, bigint, text, text, bigint, bigint
) from public;
grant execute on function public.app_link_case_document(
  text, text, bigint, bigint, bigint, text, text, bigint, bigint
) to anon, authenticated;

-- =============================================================
-- B2) app_list_case_checklist — เติม key attribution ใน linked_docs (additive)
--     * signature เดิมทุกประการ (create or replace ตรง ๆ — ไม่มี overload ใหม่)
--     * key เดิมใน linked_docs ครบ ชื่อเดิม ลำดับความหมายเดิม — เพิ่ม 3 key ใหม่เท่านั้น
--     * ยังคง metadata-only — ❌ ไม่มี storage_path / bucket path ดิบ / base64 / URL
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
             'has_storage',    (d.storage_path is not null),
             -- ── ใหม่ 58K-A (additive keys — legacy link = null ทั้งสาม) ──
             'linked_owner_type',     l.linked_owner_type,
             'linked_owner_id',       l.linked_owner_id,
             'linked_case_worker_id', l.linked_case_worker_id
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
-- C) VERIFICATION QUERIES  [รันบน staging หลัง apply — comment ล้วน ห้ามรันอัตโนมัติ]
--    เก็บผลไว้เทียบใน runbook log (pattern 58G §5–§6)
-- =============================================================
-- C.1 คอลัมน์ใหม่ครบ 3 คอลัมน์ (nullable ทุกตัว):
--   select column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema='public' and table_name='case_documents'
--     and column_name in ('linked_owner_type','linked_owner_id','linked_case_worker_id')
--   order by column_name;
--
-- C.2 constraint ใหม่ครบ (FK + CHECK):
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint where conrelid='public.case_documents'::regclass
--     and conname in ('case_documents_linked_case_worker_fk',
--                     'case_documents_linked_owner_type_check');
--
-- C.3 ดัชนีใหม่ครบ:
--   select indexname from pg_indexes
--   where schemaname='public' and tablename='case_documents'
--     and indexname in ('idx_case_docs_linked_owner','idx_case_docs_linked_worker');
--
-- C.4 signature ใหม่ถูกต้อง + ตัวเก่า (6 args) ต้องหายไป (กัน overload กำกวม):
--   select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.proname='app_link_case_document';
--     -- ต้องได้ "แถวเดียว" args ลงท้าย ... p_linked_case_worker_id bigint, prosecdef=true
--
-- C.5 สิทธิ์ execute ครบ anon/authenticated (ทั้งสอง function):
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'EXECUTE')
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   cross join (values ('anon'),('authenticated')) r(rolname)
--   where n.nspname='public'
--     and p.proname in ('app_link_case_document','app_list_case_checklist');
--
-- C.6 SMOKE TEST (staging เท่านั้น — ใช้ id/username จริงบน staging):
--   -- เตรียม: <uid>/<uname> = staff active, <case_id> = เคสทดสอบที่มี checklist,
--   --   <item_id> = case_checklist_items ของเคสนั้น, <doc_primary> = เอกสารของ
--   --   cases.customer_id, <cw_b>/<doc_b> = case_workers แถว active ของแรงงานรอง
--   --   และเอกสารของ customer นั้น, <doc_other> = เอกสารของลูกค้าที่ไม่เกี่ยวกับเคส
--   -- 1) เข้ากันได้ย้อนหลัง (แขนง legacy — ไม่ส่ง p_linked_*):
--   --    select * from public.app_link_case_document('<uid>','<uname>',<case_id>,<item_id>,<doc_primary>);
--   --      → ลิงก์ได้, already_linked=false, attribution ทั้งสามใน case_documents = null
--   -- 2) เอกสารลูกค้าอื่น (legacy) → ต้อง raise document_not_allowed:
--   --    select * from public.app_link_case_document('<uid>','<uname>',<case_id>,<item_id>,<doc_other>);
--   -- 3) แรงงานรอง active ใน Name List → ลิงก์ได้ + attribution ครบ:
--   --    select * from public.app_link_case_document('<uid>','<uname>',<case_id>,<item_id>,<doc_b>,
--   --                null,'worker',null,<cw_b>);
--   --      → ตรวจ: select linked_owner_type, linked_owner_id, linked_case_worker_id
--   --              from case_documents where id=<link_id>;  -- 'worker', <cust_b>, <cw_b>
--   -- 4) แรงงานรองที่ถูกปิด (is_active=false ผ่าน app_set_case_worker_active)
--   --    → ต้อง raise case_worker_inactive
--   -- 5) case_worker ของ "เคสอื่น" → ต้อง raise case_worker_not_in_case
--   -- 6) เอกสารนายจ้าง: เคสที่มี employer_id + เอกสาร owner_type='employer'
--   --    ของนายจ้างนั้น → ลิงก์ได้ ('employer', <employer_id>):
--   --    select * from public.app_link_case_document('<uid>','<uname>',<case_id>,<item_id>,<doc_emp>,
--   --                null,'employer');
--   --    เอกสารของนายจ้าง "รายอื่น" → ต้อง raise document_not_allowed
--   --    เคสที่ไม่มี employer_id → ต้อง raise case_has_no_employer
--   -- 7) เอกสารของเคสเอง (owner_type='case') → แขนง 'case' และ 'internal' ลิงก์ได้
--   -- 8) 'payment': เอกสารที่เป็น proof_document_id ของ case_payments เคสเดียวกัน
--   --    → ลิงก์ได้; เอกสาร proof ของเคสอื่น → document_not_allowed
--   -- 9) 'establishment' → ต้อง raise owner_link_not_supported (ยังไม่เปิดใน 58K)
--   -- 10) ลิงก์ซ้ำ (item+doc เดิม) → already_linked=true และ attribution แถวเดิมไม่เปลี่ยน
--   -- 11) audit log: select action, detail from audit_logs
--   --     where action='case.document.link' order by created_at desc limit 5;
--   --       → detail ต้องมี linked_owner_type/linked_owner_id/linked_case_worker_id
--   -- 12) app_list_case_checklist: linked_docs ของ item ต้องมี key ใหม่ 3 ตัว
--   --     และ key เดิมครบทุกตัว (frontend เดิมไม่พัง)
--
-- C.7 ROLLBACK (staging เท่านั้น — เฉพาะเมื่อยังไม่มีข้อมูล attribution ใช้จริง):
--   -- ทางเลือกปลอดภัย: replace สอง function กลับเป็นนิยามใน 20260803 (B4/B2 เดิม)
--   --   (คอลัมน์/ดัชนีใหม่ปล่อยไว้ได้ — nullable ทั้งหมด ไม่กระทบพฤติกรรมเดิม)
--   -- ถอนเต็มรูป (ถ้าจำเป็นจริง ๆ):
--   --   drop index if exists idx_case_docs_linked_owner;
--   --   drop index if exists idx_case_docs_linked_worker;
--   --   alter table public.case_documents drop constraint if exists case_documents_linked_owner_type_check;
--   --   alter table public.case_documents drop constraint if exists case_documents_linked_case_worker_fk;
--   --   alter table public.case_documents drop column if exists linked_case_worker_id;
--   --   alter table public.case_documents drop column if exists linked_owner_id;
--   --   alter table public.case_documents drop column if exists linked_owner_type;
--   --   (แล้ว re-apply 20260803 B4/B2 เพื่อคืน signature 6 args เดิม)
-- =============================================================
-- END STAGE 58K-A — additive, idempotent, RPC-only. DO NOT APPLY here — staging first.
-- =============================================================
