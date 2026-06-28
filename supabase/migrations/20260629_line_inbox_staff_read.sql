-- =============================================================
-- STAGE 29G — app_list_line_inbox (SECURITY DEFINER, staff + admin read)
-- เป้าหมาย:
--   * เปลี่ยน "เอกสารจาก LINE" ให้พนักงาน (staff) และแอดมิน (admin) ที่ล็อกอินอยู่
--     เปิดดู/ตรวจไฟล์ได้ — ไม่ต้องใส่รหัสผ่านแอดมินอีก
--   * โมเดลตัวตนใช้ "เหมือน app_verify_session": (user_id, username) ต้องตรงกับ
--     แถวใน app_users ที่ is_active=true และ role ไม่เป็น null
--     → ระดับความเชื่อถือ "เท่ากับ" workflow ของ staff ทั้งระบบ (guardSession)
--       ไม่มี password/token แยกต่างหาก (ดูหมายเหตุข้อจำกัดด้านล่าง)
--
--   ❗ คืนเฉพาะ metadata (รวม storage_path เพื่อให้ Edge Function สร้าง signed URL ได้)
--      ตาราง line_file_inbox ไม่มีคอลัมน์ bytes/base64 → ไม่มีโอกาสรั่ว file bytes
--
-- ⚠️ ข้อจำกัดด้านความปลอดภัย (ตามที่ผู้ใช้รับทราบ):
--   ระบบ login ของ CRM เป็น custom session — app_verify_session พิสูจน์ตัวตนด้วย
--   (user_id, username) + is_active เท่านั้น ไม่มี secret token ฝั่ง client
--   ดังนั้น RPC นี้เชื่อถือ "เท่ากับ" ส่วนอื่นของ staff workflow ทั้งหมด ไม่มากกว่า
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS ของ line_file_inbox (อ่านอย่างเดียว ไม่ ALTER)
--   * app_admin_list_line_inbox เดิม (คงไว้ — ไม่ลบ, ไม่เรียกใช้แล้วจาก frontend)
--   * line-webhook-router / line-doc-inbox (worker) / line-ai-excel-* / attendance
--
-- ⚠️ Additive only — สร้าง function ใหม่เท่านั้น
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า staff จึงจะอ่านรายการได้
-- =============================================================

create or replace function public.app_list_line_inbox(
  p_user_id     text,
  p_username    text,
  p_status      text default null,   -- pending | approved | rejected | linked | (null/all)
  p_source_type text default null,   -- image | pdf | excel | other | (null/all)
  p_start_date  date default null,
  p_end_date    date default null,
  p_sender      text default null,   -- ค้นหาในชื่อผู้ส่ง LINE
  p_search      text default null    -- ค้นหา filename / note / sender
)
returns setof public.line_file_inbox
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  -- ── คืน metadata — filter → เรียงใหม่ → จำกัด 500 แถว (เหมือน admin RPC) ──
  return query
  select f.*
  from public.line_file_inbox f
  where
    (p_status is null or p_status not in ('pending','approved','rejected','linked') or f.status = p_status)
    and (p_source_type is null or p_source_type not in ('image','pdf','excel','other') or f.source_type = p_source_type)
    and (p_start_date is null or f.created_at >= p_start_date::timestamptz)
    and (p_end_date is null or f.created_at < ((p_end_date + 1))::timestamptz)
    and (
      p_sender is null or p_sender = ''
      or f.line_display_name ilike '%' || p_sender || '%'
    )
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

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC อื่นของ CRM)
-- ฟังก์ชันบังคับตรวจ (user_id, username, is_active) ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_list_line_inbox(text, text, text, text, date, date, text, text) from public;
grant execute on function public.app_list_line_inbox(text, text, text, text, date, date, text, text) to anon, authenticated;
