-- =============================================================
-- STAGE 50A-9 — Customer Photo Fallback RPC (SECURITY DEFINER, additive)
-- เป้าหมาย:
--   * เปิด "ทางสำรองสุดท้าย" ให้บันทึกรูปลูกค้าแบบ base64/dataURL ลง customers.photo
--     ผ่าน RPC ที่ตรวจตัวตน — ใช้ก็ต่อเมื่อ Storage Edge Function อัปโหลดไม่สำเร็จ
--   * เป็นตัวปลดล็อกสุดท้ายก่อนจะ revoke UPDATE ตรงของ customers ใน stage ถัดไป
--     (ตอนนี้ path 4979 เดิมใช้ dbPatch ตรง → หลัง revoke UPDATE จะพัง; ย้ายมาผ่าน RPC แทน)
--
-- plain-language:
--   photo fallback = ทางสำรองเก็บรูป เมื่ออัปโหลดเข้า Storage (ทางปกติ) ล้มเหลว
--   RPC = ประตูปลอดภัยฝั่ง server (ตรวจตัวตนก่อนเขียนเสมอ)
--
--   ❗ อัปเดตเฉพาะคอลัมน์ customers.photo ของ id ที่ระบุเท่านั้น
--   ❗ ไม่รับ/ไม่เขียน file_data / base64(ชื่อคอลัมน์) / storage_path / signed_url /
--      raw_bucket_path / bucket_path / photo_storage_path / photo_storage_bucket
--   ❗ ไม่คืน path/ไฟล์ใด ๆ — คืนแค่ id + updated_at
--   ❗ ไม่ลบข้อมูล / ไม่ DROP/TRUNCATE / ไม่ ALTER โครงสร้างตาราง
--   ❗ ไม่ revoke สิทธิ์ใด ๆ ในไฟล์นี้ (การ revoke อยู่ในไฟล์ 20260721 แยกต่างหาก)
--
-- ไม่แตะ: Edge Functions / Storage bucket rules / LINE / Attendance / Meta Ads / customer DELETE
--
-- ⚠️ Additive / idempotent — create or replace function + grant เท่านั้น
-- =============================================================

create or replace function public.app_set_customer_photo_fallback(
  p_user_id     text,
  p_username    text,
  p_customer_id bigint,
  p_photo       text
)
returns table (
  id         bigint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text;
  v_active   boolean := false;
  v_set      text := '';
  v_rowcount integer := 0;
begin
  -- ── ตัวตน: active user จริง (predicate เดียวกับ RPC อื่นของระบบ) ──
  select u.role, true
    into v_role, v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_customer_id is null then
    raise exception 'customer_id_required' using errcode = 'P0003';
  end if;

  -- ── UPDATE เฉพาะ customers.photo (base64/dataURL สำรอง) ──
  --    server-stamp updated_at / updated_by_code ถ้ามีคอลัมน์ (ต่อท้าย SET แบบไดนามิก)
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_at') then
    v_set := v_set || ', updated_at = now()';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_by_code') then
    v_set := v_set || ', updated_by_code = ' || quote_literal(p_username);
  end if;

  -- p_photo เข้าทาง bind $1 เท่านั้น (กัน injection) — เขียนลงคอลัมน์ photo อย่างเดียว
  execute 'update public.customers set photo = $1' || v_set || ' where id = $2'
    using p_photo, p_customer_id;
  get diagnostics v_rowcount = row_count;

  if v_rowcount = 0 then
    raise exception 'customer_not_found' using errcode = 'P0002';
  end if;

  -- ── คืน metadata ปลอดภัยเท่านั้น (❌ ไม่มี photo/path/file) ──
  return query
  select c.id, c.updated_at
  from public.customers c
  where c.id = p_customer_id;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจตัวตนภายในก่อนเขียนเสมอ)
revoke all on function public.app_set_customer_photo_fallback(text, text, bigint, text) from public;
grant execute on function public.app_set_customer_photo_fallback(text, text, bigint, text) to anon, authenticated;
