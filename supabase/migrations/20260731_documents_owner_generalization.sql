-- =============================================================
-- STAGE 54A-1B — documents owner generalization (backend only, additive)
-- เป้าหมาย:
--   * เตรียม public.documents ให้ Phase 2 แนบเอกสารกับเจ้าของได้ 4 ชนิด:
--       customer | employer | establishment | case
--     โดย "เอกสารลูกค้าเดิมทำงานเหมือนเดิมทุกประการ" (backward-compatible)
--
--   สิ่งที่ทำ (additive ล้วน):
--     A) เพิ่มคอลัมน์ owner_type (not null default 'customer') + owner_id (bigint null)
--     B) CHECK constraint จำกัดค่า owner_type (guarded DO block — idempotent)
--     C) index (owner_type, owner_id, created_at desc)
--     D) replace app_list_documents — เพิ่ม p_owner_type / p_owner_id "ท้ายสุด"
--        (พารามิเตอร์เดิมครบ ลำดับเดิม พฤติกรรมเดิม — frontend เดิมไม่ต้องแก้)
--
--   ❗ ไม่ backfill แถวเดิมใน stage นี้:
--     แถวเดิมได้ owner_type='customer' จาก DEFAULT อัตโนมัติ, owner_id คง null
--     ทางอ่านถือว่า owner_id ≡ customer_id สำหรับ owner_type='customer'
--     (backfill เป็น stage แยกภายหลัง ถ้าจำเป็น — ไม่แตะแถวเดิมที่นี่)
--
--   ❗ ไม่มี DELETE / UPDATE / DROP COLUMN / TRUNCATE / RENAME
--   ❗ ไม่แตะ RLS / ไม่เปิด grant ตารางใด ๆ (มีแค่ revoke+grant ของ function ที่ replace ตามแบบเดิม)
--   ❗ ไม่แตะ Storage bucket / customer-doc-sign / line-doc-inbox-admin /
--     app_document_summary / app_update_document_metadata / delete approval
--   ❗ metadata-only เหมือนเดิม — ❌ ไม่คืน file_data / base64 / storage_path ดิบ
--
-- ⚠️ ลำดับ deploy สำคัญ: ต้อง apply migration นี้ "ก่อน" deploy
--    customer-doc-upload เวอร์ชันใหม่ (function ใหม่ insert คอลัมน์ owner_*)
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A) คอลัมน์ใหม่ (additive, ไม่แตะแถวเดิม — DEFAULT เติม owner_type ให้แถวเก่าเอง)
-- =============================================================
alter table public.documents
  add column if not exists owner_type text not null default 'customer';

alter table public.documents
  add column if not exists owner_id bigint;

-- =============================================================
-- B) CHECK constraint — จำกัดค่า owner_type (guard กันรันซ้ำ)
--    ปลอดภัยกับข้อมูลเดิม: คอลัมน์เพิ่งเพิ่ม ทุกแถวมีค่า 'customer' จาก default
-- =============================================================
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname  = 'documents_owner_type_check'
      and conrelid = 'public.documents'::regclass
  ) then
    alter table public.documents
      add constraint documents_owner_type_check
      check (owner_type in ('customer', 'employer', 'establishment', 'case'));
  end if;
end$$;

-- =============================================================
-- C) Index สำหรับ query ตามเจ้าของ (Phase 2 list ต่อ employer/case)
-- =============================================================
create index if not exists idx_documents_owner
  on public.documents (owner_type, owner_id, created_at desc);

-- =============================================================
-- D) app_list_documents — เพิ่ม p_owner_type / p_owner_id (ท้ายสุด, optional)
--    * พารามิเตอร์เดิม 14 ตัวครบ ลำดับเดิม default เดิม → call เดิมทุกแบบทำงานเหมือนเดิม
--    * p_customer_id เดิม: ขยายให้ครอบคลุมแถวใหม่ที่ dual-write owner_id ด้วย
--        d.customer_id = X  OR  (d.owner_type='customer' AND d.owner_id = X)
--    * p_owner_type/p_owner_id ใหม่: กรองตามเจ้าของ — กรณี 'customer' ให้เทียบ
--      ทั้ง owner_id และ customer_id (แถว legacy owner_id เป็น null)
--    * drop signature เดิม (14 args) ก่อน create ใหม่ (16 args) — pattern เดียวกับ 45B
-- =============================================================
drop function if exists public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer, text
);

create or replace function public.app_list_documents(
  p_user_id       text,
  p_username      text,
  p_search        text default null,
  p_doc_type      text default null,
  p_source        text default null,
  p_uploaded_by   text default null,
  p_customer_id   text default null,
  p_date_from     date default null,
  p_date_to       date default null,
  p_expiring      boolean default null, -- legacy: true = เฉพาะที่มี doc_expiry
  p_doc_status    text default null,    -- null/''/'all' = ไม่กรอง, '__unset__' = ยังไม่ระบุ, อื่น = exact
  p_limit         integer default 25,
  p_offset        integer default 0,
  p_expiry_filter text default null,    -- Stage 45B: all/expired/expiring_7/expiring_30/has_expiry
  p_owner_type    text default null,    -- ใหม่ 54A-1B: customer/employer/establishment/case
  p_owner_id      bigint default null   -- ใหม่ 54A-1B: id ของเจ้าของตาม p_owner_type
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
  owner_type    text,
  owner_id      bigint,
  total_count   bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok      boolean := false;
  v_limit   integer := coalesce(p_limit, 25);
  v_offset  integer := coalesce(p_offset, 0);
  v_expiry  text    := lower(btrim(coalesce(p_expiry_filter, '')));
  v_owner   text    := lower(btrim(coalesce(p_owner_type, '')));
begin
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) — predicate เดียวกับ Stage 40C/44A/45B ──
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

  -- ── ตรวจ p_expiry_filter (เหมือน Stage 45B ทุกประการ) ──
  if v_expiry not in ('', 'all', 'expired', 'expiring_7', 'expiring_30', 'has_expiry') then
    raise exception 'invalid_expiry_filter' using errcode = 'P0003';
  end if;

  -- ── ตรวจ p_owner_type (ใหม่ 54A-1B) — '' = ไม่กรอง, ค่าผิด → raise ──
  if v_owner not in ('', 'customer', 'employer', 'establishment', 'case') then
    raise exception 'invalid_owner_type' using errcode = 'P0003';
  end if;

  -- ── clamp pagination (เหมือนเดิม) ──
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
    d.owner_type                                  as owner_type,
    d.owner_id                                    as owner_id,
    count(*) over ()                              as total_count
  from public.documents d
  left join public.customers c on c.id = d.customer_id
  left join public.employers e on e.id = c.employer_id
  where
    (p_doc_type    is null or p_doc_type    = '' or d.doc_type    = p_doc_type)
    and (p_source      is null or p_source      = '' or d.source      = p_source)
    and (p_uploaded_by is null or p_uploaded_by = '' or d.uploaded_by = p_uploaded_by)
    -- p_customer_id เดิม + ขยายครอบคลุมแถว dual-write (owner_id = ลูกค้า แต่ customer_id อาจ null ในอนาคต)
    and (
      p_customer_id is null or p_customer_id = ''
      or d.customer_id::text = p_customer_id
      or (d.owner_type = 'customer' and d.owner_id::text = p_customer_id)
    )
    -- p_owner_type / p_owner_id (ใหม่ 54A-1B) — ไม่ส่ง = ไม่กรอง (พฤติกรรมเดิม)
    and (
      v_owner = ''
      or (
        d.owner_type = v_owner
        and (
          p_owner_id is null
          or d.owner_id = p_owner_id
          -- แถว legacy ของลูกค้า: owner_id null → เทียบ customer_id แทน
          or (v_owner = 'customer' and d.customer_id = p_owner_id)
        )
      )
    )
    -- date range บน created_at (เหมือนเดิม)
    and (p_date_from is null or d.created_at >= p_date_from::timestamptz)
    and (p_date_to   is null or d.created_at <  ((p_date_to + 1))::timestamptz)
    -- p_expiring (legacy boolean) — เหมือน Stage 45B
    and (
      v_expiry not in ('', 'all')
      or p_expiring is null or p_expiring = false or d.doc_expiry is not null
    )
    -- p_expiry_filter — เหมือน Stage 45B
    and (
      v_expiry = '' or v_expiry = 'all'
      or (v_expiry = 'expired'
            and (d.doc_expiry < current_date or d.doc_status = 'expired'))
      or (v_expiry = 'expiring_7'
            and d.doc_expiry is not null
            and d.doc_expiry >= current_date and d.doc_expiry <= current_date + 7)
      or (v_expiry = 'expiring_30'
            and d.doc_expiry is not null
            and d.doc_expiry >= current_date and d.doc_expiry <= current_date + 30)
      or (v_expiry = 'has_expiry' and d.doc_expiry is not null)
    )
    -- doc_status — เหมือนเดิม
    and (
      p_doc_status is null or p_doc_status = '' or p_doc_status = 'all'
      or (p_doc_status = '__unset__' and (d.doc_status is null or d.doc_status = ''))
      or d.doc_status = p_doc_status
    )
    -- search — เหมือนเดิม
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

-- สิทธิ์เรียกใช้: เหมือน RPC เดิม (revoke public + grant anon/authenticated)
-- — ไม่ใช่การ "เปิด grant ใหม่" ของตารางใด ๆ; function ตรวจตัวตนภายในเสมอ
revoke all on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer, text, text, bigint
) from public;
grant execute on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer, text, text, bigint
) to anon, authenticated;
