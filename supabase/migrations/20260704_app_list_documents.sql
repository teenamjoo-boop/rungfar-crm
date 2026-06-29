-- =============================================================
-- STAGE 40C — app_list_documents (SECURITY DEFINER, READ-ONLY)
-- เป้าหมาย:
--   * RPC อ่านอย่างเดียวสำหรับหน้า "Document Center"
--     ให้ staff + admin ที่ล็อกอินอยู่ เปิดดูรายการเอกสาร (metadata) ได้
--   * โมเดลตัวตน "เหมือน app_verify_session / app_list_line_inbox":
--       (user_id, username) ต้องตรงกับแถวใน app_users ที่
--       is_active=true และ role ไม่เป็น null
--     → ระดับความเชื่อถือ "เท่ากับ" staff workflow ทั้งระบบ (guardSession)
--
--   ❗ คืนเฉพาะ metadata เท่านั้น — ❌ ไม่คืน file_data / base64 bytes
--   ❗ ไม่คืน storage_path ดิบ — คืนเป็น has_storage (boolean) แทน
--      เหตุผล: viewer (customer-doc-sign) ออก signed URL จาก document_id
--      เท่านั้น และดึง storage_path ฝั่ง server เอง — frontend ไม่เคย
--      (และต้องไม่) ส่ง path เพื่อ sign → ไม่มีเหตุให้คืน path ออกมา
--
-- ⚠️ ข้อจำกัดด้านความปลอดภัย (เหมือน app_list_line_inbox):
--   ระบบ login เป็น custom session — พิสูจน์ตัวตนด้วย (user_id, username)
--   + is_active เท่านั้น ไม่มี secret token ฝั่ง client → RPC นี้เชื่อถือ
--   "เท่ากับ" ส่วนอื่นของ staff workflow ทั้งหมด ไม่มากกว่า
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS ของ documents / customers / employers (อ่านอย่างเดียว)
--   * customer-doc-sign / customer-doc-upload / customer-photo-* /
--     line-doc-inbox* / webhook / attendance / import / login-session
--
-- ⚠️ Additive only — สร้าง function ใหม่เท่านั้น (read-only, ไม่มี write)
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า Document Center จึงจะอ่านรายการได้
-- =============================================================

create or replace function public.app_list_documents(
  p_user_id     text,
  p_username    text,
  p_search      text default null,    -- ค้นหา doc_name / customer name / passport / alien_id
  p_doc_type    text default null,    -- กรองตามประเภทเอกสาร (exact match)
  p_source      text default null,    -- กรองตามแหล่งที่มา (exact match)
  p_uploaded_by text default null,    -- กรองตามผู้อัปโหลด (exact match)
  p_customer_id text default null,    -- กรองเฉพาะลูกค้ารายเดียว (optional)
  p_date_from   date default null,    -- created_at >= date_from
  p_date_to     date default null,    -- created_at < date_to + 1
  p_expiring    boolean default null, -- true = เฉพาะที่มี doc_expiry (กรองง่าย ๆ)
  p_limit       integer default 25,   -- default 25, clamp 1..100
  p_offset      integer default 0     -- default 0, clamp >= 0
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
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) — predicate เดียวกับ app_verify_session ──
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

  -- ── clamp pagination (กัน abuse / ค่าผิดปกติ) ──
  if v_limit is null or v_limit < 1 then
    v_limit := 25;
  elsif v_limit > 100 then
    v_limit := 100;
  end if;
  if v_offset is null or v_offset < 0 then
    v_offset := 0;
  end if;

  -- ── คืน metadata เท่านั้น (❌ ไม่มี file_data, ❌ ไม่มี storage_path ดิบ) ──
  --    total_count ใช้ window function count(*) over () → คืน total ก่อน paginate
  --    ในทุกแถว (tradeoff: นับทั้ง result set ใน query เดียว ไม่ต้องยิงสองครั้ง)
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
    d.storage_bucket                              as storage_bucket,
    (d.storage_path is not null)                  as has_storage,
    count(*) over ()                              as total_count
  from public.documents d
  left join public.customers c on c.id = d.customer_id
  left join public.employers e on e.id = c.employer_id
  where
    -- doc_type / source / uploaded_by — exact match (parameterized, ไม่มี SQL injection)
    (p_doc_type    is null or p_doc_type    = '' or d.doc_type    = p_doc_type)
    and (p_source      is null or p_source      = '' or d.source      = p_source)
    and (p_uploaded_by is null or p_uploaded_by = '' or d.uploaded_by = p_uploaded_by)
    -- customer_id optional (เทียบแบบ text เพื่อเลี่ยงปัญหาชนิดข้อมูล id)
    and (p_customer_id is null or p_customer_id = '' or d.customer_id::text = p_customer_id)
    -- date range บน created_at
    and (p_date_from is null or d.created_at >= p_date_from::timestamptz)
    and (p_date_to   is null or d.created_at <  ((p_date_to + 1))::timestamptz)
    -- expiry filter (ง่าย): true = เฉพาะที่มีวันหมดอายุ
    and (p_expiring is null or p_expiring = false or d.doc_expiry is not null)
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
  text, text, text, text, text, text, text, date, date, boolean, integer, integer
) from public;
grant execute on function public.app_list_documents(
  text, text, text, text, text, text, text, date, date, boolean, integer, integer
) to anon, authenticated;
