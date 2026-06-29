-- =============================================================
-- STAGE 44A — documents doc_status + doc_note (additive) + RPC updates
-- เป้าหมาย:
--   * เพิ่มฟิลด์สถานะเอกสาร (doc_status) + หมายเหตุ (doc_note) ใน public.documents
--     เพื่อให้ "คลังเอกสาร" รองรับการรีวิวเอกสารเบื้องต้น (Phase 1)
--     และ Phase 2 ใช้ตาราง documents เดิมต่อได้
--   * อัปเดต RPC app_list_documents + app_update_document_metadata ให้รองรับ
--     doc_status / doc_note (metadata เท่านั้น)
--
-- ค่าสถานะที่อนุญาต (doc_status):
--   received   = ได้รับแล้ว
--   reviewing  = รอตรวจ
--   approved   = ผ่าน
--   needs_fix  = ต้องแก้
--   used       = ใช้ยื่นแล้ว
--   expired    = หมดอายุ
--   null/blank = ไม่ระบุ
--
--   ❗ ยังคง metadata-only — ❌ ไม่คืน file_data / base64 / storage_path ดิบ
--      คืน has_storage (boolean) แทน
--
-- ⚠️ Additive only สำหรับคอลัมน์ — ADD COLUMN IF NOT EXISTS, ไม่ DROP คอลัมน์,
--    ไม่ NOT NULL, ไม่ backfill, ไม่แตะแถวเดิม
-- ⚠️ ฟังก์ชัน: drop signature เดิมก่อน create ใหม่ (กัน overload ซ้อน/ambiguous)
--    — ไม่กระทบข้อมูล (function ไม่ใช่ data)
-- ⚠️ ต้อง apply migration นี้ก่อน ฟีเจอร์สถานะ/หมายเหตุในคลังเอกสารจึงจะทำงาน
-- =============================================================

-- ── 1) เพิ่มคอลัมน์ (additive, nullable) ──────────────────────────────────────
alter table public.documents
  add column if not exists doc_status text;
alter table public.documents
  add column if not exists doc_note text;

-- ── 2) Indexes ────────────────────────────────────────────────────────────────
create index if not exists idx_documents_doc_status
  on public.documents (doc_status);
create index if not exists idx_documents_doc_expiry
  on public.documents (doc_expiry);

-- =============================================================
-- 3) app_list_documents — เพิ่ม p_doc_status filter + คืน doc_status/doc_note
--    (drop signature เดิมก่อน เพราะ argument list เปลี่ยน)
-- =============================================================
drop function if exists public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, integer, integer
);

create or replace function public.app_list_documents(
  p_user_id     text,
  p_username    text,
  p_search      text default null,
  p_doc_type    text default null,
  p_source      text default null,
  p_uploaded_by text default null,
  p_customer_id text default null,
  p_date_from   date default null,
  p_date_to     date default null,
  p_expiring    boolean default null,
  p_doc_status  text default null,    -- กรองสถานะเอกสาร: null/''/'all' = ไม่กรอง,
                                      -- '__unset__' = เฉพาะที่ยังไม่ระบุ, ค่าอื่น = exact match
  p_limit       integer default 25,
  p_offset      integer default 0
)
returns table (
  id            text,
  customer_id   text,
  customer_name text,
  passport_no   text,
  alien_id      text,
  employer_id   text,
  employer_name text,
  doc_type      text,
  doc_name      text,
  file_type     text,
  mime_type     text,
  file_size     bigint,
  uploaded_by   text,
  created_at    timestamptz,
  source        text,
  doc_expiry    date,
  doc_status    text,
  doc_note      text,
  storage_bucket text,
  has_storage   boolean,
  total_count   bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    boolean := false;
  v_limit integer := coalesce(p_limit, 25);
  v_offset integer := coalesce(p_offset, 0);
begin
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) ──
  select true
    into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── clamp pagination ──
  if v_limit is null or v_limit < 1 then
    v_limit := 25;
  elsif v_limit > 100 then
    v_limit := 100;
  end if;
  if v_offset is null or v_offset < 0 then
    v_offset := 0;
  end if;

  -- ── คืน metadata เท่านั้น (❌ ไม่มี file_data, ❌ ไม่มี storage_path ดิบ) ──
  return query
  select
    d.id::text                                    as id,
    d.customer_id::text                           as customer_id,
    c.name                                        as customer_name,
    c.passport_no                                 as passport_no,
    c.alien_id                                    as alien_id,
    c.employer_id::text                           as employer_id,
    e.name                                        as employer_name,
    d.doc_type                                    as doc_type,
    d.doc_name                                    as doc_name,
    d.file_type                                   as file_type,
    d.mime_type                                   as mime_type,
    d.file_size::bigint                           as file_size,
    d.uploaded_by                                 as uploaded_by,
    d.created_at                                  as created_at,
    d.source                                      as source,
    d.doc_expiry                                  as doc_expiry,
    d.doc_status                                  as doc_status,
    d.doc_note                                    as doc_note,
    d.storage_bucket                              as storage_bucket,
    (d.storage_path is not null)                  as has_storage,
    count(*) over ()                              as total_count
  from public.documents d
  left join public.customers c on c.id = d.customer_id
  left join public.employers e on e.id = c.employer_id
  where
    (p_doc_type    is null or p_doc_type    = '' or d.doc_type    = p_doc_type)
    and (p_source      is null or p_source      = '' or d.source      = p_source)
    and (p_uploaded_by is null or p_uploaded_by = '' or d.uploaded_by = p_uploaded_by)
    and (p_customer_id is null or p_customer_id = '' or d.customer_id::text = p_customer_id)
    and (p_date_from is null or d.created_at >= p_date_from::timestamptz)
    and (p_date_to   is null or d.created_at <  ((p_date_to + 1))::timestamptz)
    and (p_expiring is null or p_expiring = false or d.doc_expiry is not null)
    -- doc_status: null/''/'all' = ไม่กรอง, '__unset__' = ยังไม่ระบุ, อื่น = exact
    and (
      p_doc_status is null or p_doc_status = '' or p_doc_status = 'all'
      or (p_doc_status = '__unset__' and (d.doc_status is null or d.doc_status = ''))
      or d.doc_status = p_doc_status
    )
    and (
      p_search is null or p_search = ''
      or d.doc_name    ilike '%' || p_search || '%'
      or c.name        ilike '%' || p_search || '%'
      or c.passport_no ilike '%' || p_search || '%'
      or c.alien_id    ilike '%' || p_search || '%'
    )
  order by d.created_at desc nulls last
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer
) from public;
grant execute on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer
) to anon, authenticated;

-- =============================================================
-- 4) app_update_document_metadata — เพิ่ม p_doc_status / p_doc_note (ท้าย param)
--    (drop signature เดิมก่อน เพราะ argument list เปลี่ยน)
-- =============================================================
drop function if exists public.app_update_document_metadata(
  text, text, text, text, text, text, date
);

create or replace function public.app_update_document_metadata(
  p_user_id     text,
  p_username    text,
  p_document_id text,
  p_doc_name    text default null,
  p_doc_type    text default null,
  p_source      text default null,
  p_doc_expiry  date default null,
  p_doc_status  text default null,    -- เพิ่ม Stage 44A — '' = ล้าง, null = คงเดิม
  p_doc_note    text default null     -- เพิ่ม Stage 44A — '' = ล้าง, null = คงเดิม (จำกัด 1000 ตัวอักษร)
)
returns table (
  id            text,
  customer_id   text,
  customer_name text,
  passport_no   text,
  alien_id      text,
  employer_id   text,
  employer_name text,
  doc_type      text,
  doc_name      text,
  file_type     text,
  mime_type     text,
  file_size     bigint,
  uploaded_by   text,
  created_at    timestamptz,
  source        text,
  doc_expiry    date,
  doc_status    text,
  doc_note      text,
  storage_bucket text,
  has_storage   boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok      boolean := false;
  v_found   boolean := false;
begin
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) ──
  select true
    into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── ตรวจ doc_status ว่าอยู่ในชุดที่อนุญาต (ถ้ามีค่า) ──
  if p_doc_status is not null
     and btrim(p_doc_status) <> ''
     and btrim(p_doc_status) not in
       ('received','reviewing','approved','needs_fix','used','expired') then
    raise exception 'invalid_doc_status' using errcode = 'P0003';
  end if;

  -- ── ตรวจว่าเอกสารมีอยู่จริง ──
  select true
    into v_found
  from public.documents d
  where d.id::text = p_document_id
  limit 1;

  if not coalesce(v_found, false) then
    raise exception 'document_not_found' using errcode = 'P0002';
  end if;

  -- ── อัปเดตเฉพาะ metadata ปลอดภัย (doc_name, doc_type, source, doc_expiry,
  --    doc_status, doc_note) — ❌ ไม่แตะ file_data/storage_path/storage_bucket/
  --    file_size/mime_type/file_type/thumbnail_path/customer_id/uploaded_by/created_at/id
  update public.documents d
  set
    doc_name   = coalesce(nullif(btrim(p_doc_name), ''), d.doc_name),
    doc_type   = coalesce(nullif(btrim(p_doc_type), ''), d.doc_type),
    source     = nullif(btrim(p_source), ''),    -- ค่าว่าง → null
    doc_expiry = p_doc_expiry,                    -- null → ล้าง
    doc_status = case
                   when p_doc_status is null then d.doc_status            -- คงเดิม
                   when btrim(p_doc_status) = '' then null                 -- ล้าง (ไม่ระบุ)
                   else btrim(p_doc_status)                                -- ตั้งค่า
                 end,
    doc_note   = case
                   when p_doc_note is null then d.doc_note                 -- คงเดิม
                   when btrim(p_doc_note) = '' then null                   -- ล้าง
                   else left(p_doc_note, 1000)                             -- จำกัด 1000 ตัวอักษร
                 end
  where d.id::text = p_document_id;

  -- ── คืน metadata ของแถวที่อัปเดต (❌ ไม่มี file_data, ❌ ไม่มี storage_path ดิบ) ──
  return query
  select
    d.id::text                                    as id,
    d.customer_id::text                           as customer_id,
    c.name                                        as customer_name,
    c.passport_no                                 as passport_no,
    c.alien_id                                    as alien_id,
    c.employer_id::text                           as employer_id,
    e.name                                        as employer_name,
    d.doc_type                                    as doc_type,
    d.doc_name                                    as doc_name,
    d.file_type                                   as file_type,
    d.mime_type                                   as mime_type,
    d.file_size::bigint                           as file_size,
    d.uploaded_by                                 as uploaded_by,
    d.created_at                                  as created_at,
    d.source                                      as source,
    d.doc_expiry                                  as doc_expiry,
    d.doc_status                                  as doc_status,
    d.doc_note                                    as doc_note,
    d.storage_bucket                              as storage_bucket,
    (d.storage_path is not null)                  as has_storage
  from public.documents d
  left join public.customers c on c.id = d.customer_id
  left join public.employers e on e.id = c.employer_id
  where d.id::text = p_document_id
  limit 1;
end;
$$;

revoke all on function public.app_update_document_metadata(
  text, text, text, text, text, text, date, text, text
) from public;
grant execute on function public.app_update_document_metadata(
  text, text, text, text, text, text, date, text, text
) to anon, authenticated;
