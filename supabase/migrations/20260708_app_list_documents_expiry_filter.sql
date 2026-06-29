-- =============================================================
-- STAGE 45B — app_list_documents: เพิ่ม p_expiry_filter (drilldown วันหมดอายุ)
-- เป้าหมาย:
--   * ให้การ์ดสรุป "ใกล้หมดอายุ 7 วัน / 30 วัน / หมดอายุ" ในหน้า "คลังเอกสาร"
--     คลิกแล้วกรองรายการได้จริง (เดิม "ใกล้หมดอายุ 30 วัน" เป็น count-only
--     เพราะ list RPC ยังไม่มีการกรองช่วง doc_expiry)
--   * เพิ่ม parameter ใหม่ "ท้ายสุด": p_expiry_filter text default null
--     เพื่อคงความเข้ากันได้ย้อนหลังกับ call เดิมทุกแบบ
--
--   ค่าที่อนุญาตของ p_expiry_filter:
--     null / '' / 'all'  = ไม่กรองวันหมดอายุ
--     'expired'          = doc_expiry < current_date OR doc_status = 'expired'
--     'expiring_7'       = doc_expiry ระหว่าง current_date .. current_date + 7
--     'expiring_30'      = doc_expiry ระหว่าง current_date .. current_date + 30
--     'has_expiry'       = doc_expiry is not null
--   ค่าอื่นนอกเหนือนี้ → raise exception 'invalid_expiry_filter'
--
--   พฤติกรรมสำคัญ:
--     * คง parameter เดิมครบ + ลำดับเดิม (p_doc_status / p_expiring ทำงานเหมือนเดิม)
--     * ถ้าส่งทั้ง p_expiring (boolean เก่า) และ p_expiry_filter พร้อมกัน →
--       p_expiry_filter เฉพาะเจาะจงกว่า "ชนะ" (ข้าม predicate ของ p_expiring)
--     * total_count (count(*) over ()) นับหลังกรองทุกเงื่อนไข ก่อน paginate → ถูกต้อง
--     * date_from/date_to ยังกรองบน created_at เหมือนเดิม (ไม่ใช่ doc_expiry)
--
--   ❗ ยังคง metadata-only — ❌ ไม่คืน file_data / base64 / storage_path ดิบ
--      คืน has_storage (boolean) แทน — เหมือน Stage 40C/44A ทุกประการ
--   ❗ READ-ONLY — SELECT เท่านั้น, ❌ ไม่มี INSERT/UPDATE/DELETE
--   ❗ โมเดลตัวตนเดิม: (user_id, username) + is_active + role is not null
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS ของ documents / customers / employers (อ่านอย่างเดียว)
--   * app_document_summary (ตัวนับ chip ยังมาจากที่เดิม ไม่เปลี่ยน)
--   * app_update_document_metadata
--   * customer-doc-sign / upload / customer-photo-* / line-doc-inbox* /
--     webhook / attendance / import / login-session / storage
--
-- ⚠️ ฟังก์ชัน: drop signature เดิม (จาก Stage 44A) ก่อน create ใหม่
--    เพราะ argument list เปลี่ยน (เพิ่ม p_expiry_filter ท้ายสุด)
--    — ไม่กระทบข้อมูล (function ไม่ใช่ data)
-- ⚠️ ต้อง apply migration นี้ก่อน chip drilldown วันหมดอายุจึงจะกรองรายการได้
-- =============================================================

-- ── drop signature เดิม (Stage 44A: ...boolean, text, integer, integer) ──
drop function if exists public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer
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
  p_expiry_filter text default null     -- ใหม่ Stage 45B: ดู allowed values ด้านบน
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
  v_ok      boolean := false;
  v_limit   integer := coalesce(p_limit, 25);
  v_offset  integer := coalesce(p_offset, 0);
  v_expiry  text    := lower(btrim(coalesce(p_expiry_filter, '')));
begin
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) — predicate เดียวกับ Stage 40C/44A ──
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

  -- ── ตรวจ p_expiry_filter ว่าอยู่ในชุดที่อนุญาต (ถ้ามีค่า) ──
  --    '' = ไม่กรอง (ผ่าน), ค่าผิด → raise (สไตล์เดียวกับ invalid_doc_status)
  if v_expiry not in ('', 'all', 'expired', 'expiring_7', 'expiring_30', 'has_expiry') then
    raise exception 'invalid_expiry_filter' using errcode = 'P0003';
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
  --    count(*) over () → total หลังกรองทุกเงื่อนไข ก่อน paginate
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
    -- date range บน created_at (ไม่ใช่ doc_expiry)
    and (p_date_from is null or d.created_at >= p_date_from::timestamptz)
    and (p_date_to   is null or d.created_at <  ((p_date_to + 1))::timestamptz)
    -- p_expiring (legacy boolean) — ใช้ก็ต่อเมื่อ p_expiry_filter ไม่ทำงาน (filter เฉพาะเจาะจงชนะ)
    and (
      v_expiry not in ('', 'all')
      or p_expiring is null or p_expiring = false or d.doc_expiry is not null
    )
    -- p_expiry_filter (Stage 45B) — เฉพาะเจาะจงกว่า p_expiring
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
    -- doc_status: null/''/'all' = ไม่กรอง, '__unset__' = ยังไม่ระบุ, อื่น = exact
    and (
      p_doc_status is null or p_doc_status = '' or p_doc_status = 'all'
      or (p_doc_status = '__unset__' and (d.doc_status is null or d.doc_status = ''))
      or d.doc_status = p_doc_status
    )
    -- search: doc_name / customer name / passport / alien_id (ilike, parameterized)
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

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC อื่นของ CRM)
-- ฟังก์ชันบังคับตรวจ (user_id, username, is_active) ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer, text
) from public;
grant execute on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, text, integer, integer, text
) to anon, authenticated;
