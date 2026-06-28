-- =============================================================
-- STAGE 29C — app_admin_list_line_inbox (SECURITY DEFINER, admin-only read)
-- เป้าหมาย:
--   * ให้หน้า "เอกสารจาก LINE" (admin เท่านั้น) อ่าน metadata ของ line_file_inbox
--     ได้อย่างปลอดภัย โดย "ไม่" เปิด direct SELECT ให้ anon/authenticated
--     (line_file_inbox เปิด RLS แต่ไม่มี policy → service_role เท่านั้นที่อ่านตรงได้)
--   * ใช้รูปแบบเดียวกับ RPC แอดมินเดิม (app_admin_list_audit_logs /
--     app_admin_list_security_logs): รับ p_admin_username + p_admin_password
--     แล้วตรวจสิทธิ์ admin ก่อนคืนข้อมูล
--   * ตรวจรหัสผ่านโดย "เรียกใช้ app_verify_login เดิม" → ไม่ทำซ้ำ password scheme
--
--   ❗ คืนเฉพาะ metadata (รวม storage_path เพื่อให้ Edge Function ฝั่งแอดมินสร้าง
--      signed URL ได้) — ตาราง line_file_inbox ไม่มีคอลัมน์ bytes/base64 อยู่แล้ว
--      จึงไม่มีโอกาสรั่ว file bytes ผ่าน RPC นี้
--
-- ไม่แตะ (สำคัญ):
--   * โครงสร้าง/RLS ของ line_file_inbox — อ่านอย่างเดียว ไม่ ALTER
--   * line-webhook-router / line-doc-inbox / line-ai-excel-* — ไม่เกี่ยว
--   * login/auth (app_verify_login / app_verify_session) — คงเดิม
--
-- ⚠️ Additive only — สร้าง function ใหม่เท่านั้น
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า frontend จึงจะแสดงรายการจริง
--    ก่อน apply: หน้าจะขึ้น "ยังไม่ได้ติดตั้งฟังก์ชัน — apply migration ก่อน"
-- =============================================================

create or replace function public.app_admin_list_line_inbox(
  p_admin_username text,
  p_admin_password text,
  p_status         text default null,   -- pending | approved | rejected | linked | (null/all)
  p_source_type    text default null,   -- image | pdf | excel | other | (null/all)
  p_start_date     date default null,
  p_end_date       date default null,
  p_sender         text default null,   -- ค้นหาในชื่อผู้ส่ง LINE
  p_search         text default null    -- ค้นหา filename / note / sender
)
returns setof public.line_file_inbox
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    integer := 0;
  v_admin boolean := false;
begin
  -- 1) ตรวจรหัสผ่านด้วย RPC login เดิม (password scheme เดียวกัน)
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);

  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 2) ยืนยันว่าเป็น admin จริง (DEFINER อ่าน app_users ได้แม้ RLS ปิด direct access)
  select (lower(coalesce(u.role, '')) = 'admin')
    into v_admin
  from public.app_users u
  where u.username = p_admin_username
  limit 1;

  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) คืน metadata — filter → เรียงใหม่ก่อน → จำกัด 500 แถว
  return query
  select f.*
  from public.line_file_inbox f
  where
    -- status เฉพาะค่าที่ valid เท่านั้น (ค่าอื่น/ว่าง = all)
    (p_status is null or p_status not in ('pending','approved','rejected','linked') or f.status = p_status)
    -- source_type เฉพาะค่าที่ valid เท่านั้น
    and (p_source_type is null or p_source_type not in ('image','pdf','excel','other') or f.source_type = p_source_type)
    -- ช่วงวันที่ inclusive
    and (p_start_date is null or f.created_at >=  p_start_date::timestamptz)
    and (p_end_date is null or f.created_at <  ((p_end_date + 1))::timestamptz)
    -- ชื่อผู้ส่ง LINE contains (case-insensitive)
    and (
      p_sender is null or p_sender = ''
      or f.line_display_name ilike '%' || p_sender || '%'
    )
    -- ค้นหา filename / note / sender
    and (
      p_search is null or p_search = ''
      or f.file_name         ilike '%' || p_search || '%'
      or f.note              ilike '%' || p_search || '%'
      or f.line_display_name ilike '%' || p_search || '%'
    )
  order by f.created_at desc
  limit 500;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC แอดมินเดิม)
-- แต่ฟังก์ชันบังคับตรวจ admin credential ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_admin_list_line_inbox(text, text, text, text, date, date, text, text) from public;
grant execute on function public.app_admin_list_line_inbox(text, text, text, text, date, date, text, text) to anon, authenticated;
