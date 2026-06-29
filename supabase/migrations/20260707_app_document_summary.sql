-- =============================================================
-- STAGE 45A — app_document_summary (SECURITY DEFINER, READ-ONLY COUNTS)
-- เป้าหมาย:
--   * RPC สรุปจำนวนเอกสารที่ต้องดำเนินการ สำหรับหน้า "คลังเอกสาร"
--     (รอตรวจ / ต้องแก้ / ใกล้หมดอายุ / หมดอายุ / ใช้ยื่นแล้ว / ไม่ระบุ)
--   * ใช้เตรียม Phase 2 โดยยังไม่สร้างระบบ case/workflow เต็มรูปแบบ
--
--   ❗ READ-ONLY — SELECT count() เท่านั้น, ❌ ไม่มี INSERT/UPDATE/DELETE
--   ❗ คืนเฉพาะตัวเลขสรุป — ❌ ไม่คืน file_data / storage_path / signed URL / bytes
--   ❗ นับเฉพาะแถวใน public.documents — ไม่ join file data
--
--   โมเดลตัวตน "เหมือน app_list_documents":
--       (user_id, username) ต้องตรงกับแถวใน app_users ที่
--       is_active=true และ role ไม่เป็น null → staff/admin ที่ active ใช้ได้
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS ของ documents (อ่านอย่างเดียว)
--   * customer-doc-sign / upload / customer-photo-* / line-doc-inbox* /
--     webhook / attendance / import / login-session / storage
--
-- ⚠️ Additive only — สร้าง function ใหม่เท่านั้น (read-only)
-- ⚠️ ต้อง apply migration นี้ก่อน การ์ดสรุปในคลังเอกสารจึงจะทำงาน
-- =============================================================

create or replace function public.app_document_summary(
  p_user_id  text,
  p_username text
)
returns table (
  total_documents        bigint,
  status_unset           bigint,
  status_received        bigint,
  status_reviewing       bigint,
  status_approved        bigint,
  status_needs_fix       bigint,
  status_used            bigint,
  status_expired         bigint,
  expired_count          bigint,
  expiring_7_days_count  bigint,
  expiring_30_days_count bigint,
  has_action_count       bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  -- ── นับสรุป (read-only, นับใน query เดียว ด้วย conditional aggregation) ──
  return query
  select
    count(*)::bigint                                                          as total_documents,
    count(*) filter (where d.doc_status is null or btrim(d.doc_status) = '')::bigint as status_unset,
    count(*) filter (where d.doc_status = 'received')::bigint                 as status_received,
    count(*) filter (where d.doc_status = 'reviewing')::bigint               as status_reviewing,
    count(*) filter (where d.doc_status = 'approved')::bigint                as status_approved,
    count(*) filter (where d.doc_status = 'needs_fix')::bigint               as status_needs_fix,
    count(*) filter (where d.doc_status = 'used')::bigint                    as status_used,
    count(*) filter (where d.doc_status = 'expired')::bigint                 as status_expired,
    -- expired_count: วันหมดอายุก่อนวันนี้
    count(*) filter (where d.doc_expiry is not null and d.doc_expiry < current_date)::bigint
      as expired_count,
    -- expiring ภายใน 7 วัน (รวมวันนี้ถึง +7)
    count(*) filter (where d.doc_expiry is not null
      and d.doc_expiry >= current_date and d.doc_expiry <= current_date + 7)::bigint
      as expiring_7_days_count,
    -- expiring ภายใน 30 วัน (รวมวันนี้ถึง +30)
    count(*) filter (where d.doc_expiry is not null
      and d.doc_expiry >= current_date and d.doc_expiry <= current_date + 30)::bigint
      as expiring_30_days_count,
    -- has_action: รอตรวจ/ต้องแก้ OR หมดอายุแล้ว OR ใกล้หมดอายุ (≤30 วัน)
    count(*) filter (where
      d.doc_status in ('reviewing','needs_fix')
      or (d.doc_expiry is not null and d.doc_expiry < current_date)
      or (d.doc_expiry is not null and d.doc_expiry >= current_date and d.doc_expiry <= current_date + 30)
    )::bigint as has_action_count
  from public.documents d;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC อื่นของ CRM)
-- ฟังก์ชันบังคับตรวจ (user_id, username, is_active) ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_document_summary(text, text) from public;
grant execute on function public.app_document_summary(text, text) to anon, authenticated;
