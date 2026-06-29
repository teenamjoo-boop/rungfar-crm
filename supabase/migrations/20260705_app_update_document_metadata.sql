-- =============================================================
-- STAGE 43B — app_update_document_metadata (SECURITY DEFINER, METADATA-ONLY UPDATE)
-- เป้าหมาย:
--   * RPC ให้ staff + admin ที่ล็อกอินอยู่ "แก้ไข metadata เอกสาร" จากหน้า
--     "คลังเอกสาร" (Document Center) ได้อย่างปลอดภัย
--   * แก้ได้เฉพาะ 4 ฟิลด์ปลอดภัย: doc_name, doc_type, source, doc_expiry
--
--   ❗ อัปเดตเฉพาะ metadata — ❌ ไม่แตะ file_data / storage_path / storage_bucket
--      / file_size / mime_type / file_type / thumbnail_path / customer_id /
--      uploaded_by / created_at / id
--   ❗ คืนเฉพาะ metadata — ❌ ไม่คืน file_data / base64 / storage_path
--      คืน has_storage (boolean) แทน — แบบเดียวกับ app_list_documents
--
--   โมเดลตัวตน "เหมือน app_list_documents / app_list_line_inbox":
--       (user_id, username) ต้องตรงกับแถวใน app_users ที่
--       is_active=true และ role ไม่เป็น null → staff/admin ที่ active ใช้ได้
--
-- semantics ของการอัปเดต (frontend ส่งค่าทั้ง 4 เสมอจากฟอร์ม):
--   * doc_name : ถ้าค่าว่าง/null → คงเดิม (กันชื่อถูกล้างโดยไม่ตั้งใจ)
--   * doc_type : ถ้าค่าว่าง/null → คงเดิม
--   * source   : เซ็ตตามที่ส่งมา (ค่าว่าง → null = "ไม่ระบุ") — ล้างได้
--   * doc_expiry: เซ็ตตามที่ส่งมา (null → ล้างวันหมดอายุ) — ล้างได้
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS ของ documents (อัปเดตเฉพาะ 4 คอลัมน์ metadata)
--   * customer-doc-sign / customer-doc-upload / customer-photo-* /
--     line-doc-inbox* / webhook / attendance / import / login-session
--   * Storage objects / signed URL logic
--
-- ⚠️ Additive only — สร้าง function ใหม่เท่านั้น
-- ⚠️ ต้อง apply migration นี้ก่อน ปุ่ม "แก้ไข" ในคลังเอกสารจึงจะทำงาน
-- =============================================================

create or replace function public.app_update_document_metadata(
  p_user_id     text,
  p_username    text,
  p_document_id text,                  -- เทียบแบบ text เพื่อเลี่ยงปัญหาชนิดข้อมูล id
  p_doc_name    text default null,
  p_doc_type    text default null,
  p_source      text default null,
  p_doc_expiry  date default null
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
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) — predicate เดียวกับ app_list_documents ──
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

  -- ── ตรวจว่าเอกสารมีอยู่จริง (กัน update เงียบ ๆ ไม่โดนแถวใด) ──
  select true
    into v_found
  from public.documents d
  where d.id::text = p_document_id
  limit 1;

  if not coalesce(v_found, false) then
    raise exception 'document_not_found' using errcode = 'P0002';
  end if;

  -- ── อัปเดตเฉพาะ 4 คอลัมน์ metadata ปลอดภัย ──
  --    ❌ ไม่แตะ file_data / storage_path / storage_bucket / file_size /
  --       mime_type / file_type / thumbnail_path / customer_id / uploaded_by / created_at / id
  update public.documents d
  set
    doc_name   = coalesce(nullif(btrim(p_doc_name), ''), d.doc_name),
    doc_type   = coalesce(nullif(btrim(p_doc_type), ''), d.doc_type),
    source     = nullif(btrim(p_source), ''),   -- ค่าว่าง → null ("ไม่ระบุ")
    doc_expiry = p_doc_expiry                   -- null → ล้างวันหมดอายุ
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
    d.storage_bucket                              as storage_bucket,
    (d.storage_path is not null)                  as has_storage
  from public.documents d
  left join public.customers c on c.id = d.customer_id
  left join public.employers e on e.id = c.employer_id
  where d.id::text = p_document_id
  limit 1;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC อื่นของ CRM)
-- ฟังก์ชันบังคับตรวจ (user_id, username, is_active) ภายในก่อนอัปเดตเสมอ
revoke all on function public.app_update_document_metadata(
  text, text, text, text, text, text, date
) from public;
grant execute on function public.app_update_document_metadata(
  text, text, text, text, text, text, date
) to anon, authenticated;
