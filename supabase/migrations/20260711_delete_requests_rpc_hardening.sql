-- =============================================================
-- STAGE 46A-4 — Delete Request RPC Hardening (ย้าย client-trust → SECURITY DEFINER)
-- เป้าหมาย:
--   * เดิม flow คำขอลบใช้ direct PostgREST + RLS (anon key) — client-trust
--     (submitDeleteRequest = dbPost, list/badge = dbGet, approve/reject = dbPatch)
--   * ย้ายทั้งหมดไปหลัง RPC SECURITY DEFINER 3 ตัว แล้ว "ปิด" สิทธิ์ direct
--     select/insert/update/delete บน public.delete_requests จาก anon/authenticated
--   * ใช้ตารางเดิม public.delete_requests (จาก 20260625_delete_requests.sql)
--     ❌ ไม่สร้างตารางใหม่ / ไม่ recreate / ไม่สร้าง parallel system
--
--   โมเดลตัวตน "เหมือน app_list_documents / app_list_line_inbox":
--     (user_id, username) ต้องตรงกับแถวใน app_users ที่ is_active=true และ role ไม่ null
--
--   ❗ ไม่มี RPC ใดลบข้อมูลจริง — review = UPDATE สถานะคำขอเท่านั้น
--   ❗ ไม่คืน file_data / base64 / storage_path / signed URL / bucket path
--     (ตาราง delete_requests ไม่มีคอลัมน์เหล่านี้อยู่แล้ว — detail เป็นสรุปปลอดภัย)
--   ❗ READ/UPSERT บน delete_requests เท่านั้น — ❌ ไม่แตะ customers/documents/storage
--
-- ไม่แตะ:
--   * โครงสร้าง/RLS policy ของ delete_requests (คงไว้) — เปลี่ยนเฉพาะ table GRANT
--   * customers / documents / storage / Edge Functions / LINE / Attendance / Meta Ads
--
-- ⚠️ Additive (สร้าง function) + ปรับ privilege (revoke table grant) — ไม่ DROP ตาราง
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า "คำขอลบ" รุ่นใหม่จึงจะทำงาน (เรียกผ่าน RPC)
-- =============================================================

-- =============================================================
-- 1) app_create_delete_request — สร้างคำขอลบ (status='pending') เท่านั้น
-- =============================================================
create or replace function public.app_create_delete_request(
  p_user_id     text,
  p_username    text,
  p_request_type text,
  p_entity_type text,
  p_entity_id   text,
  p_entity_name text  default null,
  p_reason      text  default null,
  p_detail      jsonb default '{}'::jsonb
)
returns table (
  id                bigint,
  created_at        timestamptz,
  requested_by_code text,
  requested_by_name text,
  requested_by_role text,
  request_type      text,
  entity_type       text,
  entity_id         text,
  entity_name       text,
  detail            jsonb,
  reason            text,
  status            text,
  reviewed_by_code  text,
  reviewed_by_name  text,
  reviewed_at       timestamptz,
  review_note       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_role      text;
  v_reason    text := nullif(btrim(coalesce(p_reason, '')), '');
  v_eid       text := nullif(btrim(coalesce(p_entity_id, '')), '');
  v_existing  bigint;
begin
  -- ── ตัวตน: ผู้ใช้ที่ active (admin หรือ staff) — predicate เดียวกับ RPC อื่น ──
  select u.full_name, u.role
    into v_full_name, v_role
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate request_type / entity_type ──
  if p_request_type not in ('customer_delete','customer_bulk_delete','document_delete') then
    raise exception 'invalid_request_type' using errcode = 'P0003';
  end if;
  if p_entity_type not in ('customer','document') then
    raise exception 'invalid_entity_type' using errcode = 'P0003';
  end if;

  -- ── validate ความยาว reason (กันยาวผิดปกติ) — cap ไม่เกิน 1000 ──
  if v_reason is not null and char_length(v_reason) > 1000 then
    v_reason := left(v_reason, 1000);
  end if;

  -- ── กันคำขอ pending ซ้ำ (เฉพาะ entity เดี่ยวที่มี entity_id) → คืนแถวเดิมแบบ idempotent ──
  if v_eid is not null then
    select d.id into v_existing
    from public.delete_requests d
    where d.status = 'pending'
      and d.request_type = p_request_type
      and d.entity_type  = p_entity_type
      and d.entity_id    = v_eid
    order by d.created_at desc
    limit 1;

    if v_existing is not null then
      return query
      select d.id, d.created_at, d.requested_by_code, d.requested_by_name, d.requested_by_role,
             d.request_type, d.entity_type, d.entity_id, d.entity_name, d.detail, d.reason,
             d.status, d.reviewed_by_code, d.reviewed_by_name, d.reviewed_at, d.review_note
      from public.delete_requests d
      where d.id = v_existing;
      return;
    end if;
  end if;

  -- ── insert คำขอใหม่ (status='pending' เท่านั้น) — ❌ ไม่ลบอะไรทั้งสิ้น ──
  return query
  insert into public.delete_requests (
    requested_by_code, requested_by_name, requested_by_role,
    request_type, entity_type, entity_id, entity_name, detail, reason, status
  )
  values (
    p_username,
    coalesce(nullif(btrim(coalesce(v_full_name,'')), ''), p_username),
    v_role,
    p_request_type,
    p_entity_type,
    v_eid,
    nullif(btrim(coalesce(p_entity_name,'')), ''),
    coalesce(p_detail, '{}'::jsonb),
    v_reason,
    'pending'
  )
  returning
    delete_requests.id, delete_requests.created_at, delete_requests.requested_by_code,
    delete_requests.requested_by_name, delete_requests.requested_by_role, delete_requests.request_type,
    delete_requests.entity_type, delete_requests.entity_id, delete_requests.entity_name,
    delete_requests.detail, delete_requests.reason, delete_requests.status,
    delete_requests.reviewed_by_code, delete_requests.reviewed_by_name,
    delete_requests.reviewed_at, delete_requests.review_note;
end;
$$;

-- =============================================================
-- 2) app_list_delete_requests — อ่านรายการ (admin=ทั้งหมด, staff=เฉพาะของตน)
-- =============================================================
create or replace function public.app_list_delete_requests(
  p_user_id  text,
  p_username text,
  p_status   text    default 'pending',
  p_limit    integer default 50,
  p_offset   integer default 0
)
returns table (
  id                bigint,
  created_at        timestamptz,
  requested_by_code text,
  requested_by_name text,
  requested_by_role text,
  request_type      text,
  entity_type       text,
  entity_id         text,
  entity_name       text,
  detail            jsonb,
  reason            text,
  status            text,
  reviewed_by_code  text,
  reviewed_by_name  text,
  reviewed_at       timestamptz,
  review_note       text,
  total_count       bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text;
  v_is_admin boolean;
  v_status   text := lower(btrim(coalesce(p_status, 'pending')));
  v_limit    integer := coalesce(p_limit, 50);
  v_offset   integer := coalesce(p_offset, 0);
begin
  -- ── ตัวตน ──
  select u.role into v_role
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;
  v_is_admin := (v_role = 'admin');

  -- ── normalize/validate status filter ──
  if v_status = '' then v_status := 'pending'; end if;
  if v_status not in ('pending','approved','rejected','cancelled','all') then
    raise exception 'invalid_status_filter' using errcode = 'P0003';
  end if;

  -- ── clamp pagination ──
  if v_limit is null or v_limit < 1 then v_limit := 50;
  elsif v_limit > 100 then v_limit := 100; end if;
  if v_offset is null or v_offset < 0 then v_offset := 0; end if;

  -- ── อ่าน metadata เท่านั้น + total_count (count(*) over () หลังกรอง ก่อน paginate) ──
  --    staff เห็นเฉพาะคำขอที่ตนสร้าง (requested_by_code = username), admin เห็นทั้งหมด
  return query
  select
    d.id, d.created_at, d.requested_by_code, d.requested_by_name, d.requested_by_role,
    d.request_type, d.entity_type, d.entity_id, d.entity_name, d.detail, d.reason,
    d.status, d.reviewed_by_code, d.reviewed_by_name, d.reviewed_at, d.review_note,
    count(*) over ()::bigint as total_count
  from public.delete_requests d
  where
    (v_is_admin or d.requested_by_code = p_username)
    and (v_status = 'all' or d.status = v_status)
  order by d.created_at desc nulls last
  limit v_limit
  offset v_offset;
end;
$$;

-- =============================================================
-- 3) app_review_delete_request — อนุมัติ/ปฏิเสธ (UPDATE สถานะเท่านั้น, admin only)
--    ❗ ไม่ลบ customer/document ❗ ไม่เรียก DELETE ❗ ไม่แตะ storage
-- =============================================================
create or replace function public.app_review_delete_request(
  p_user_id     text,
  p_username    text,
  p_request_id  bigint,
  p_status      text,
  p_review_note text default null
)
returns table (
  id                bigint,
  created_at        timestamptz,
  requested_by_code text,
  requested_by_name text,
  requested_by_role text,
  request_type      text,
  entity_type       text,
  entity_id         text,
  entity_name       text,
  detail            jsonb,
  reason            text,
  status            text,
  reviewed_by_code  text,
  reviewed_by_name  text,
  reviewed_at       timestamptz,
  review_note       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_role      text;
  v_note      text := nullif(btrim(coalesce(p_review_note, '')), '');
  v_found     boolean := false;
begin
  -- ── ตัวตน + admin only ──
  select u.full_name, u.role
    into v_full_name, v_role
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or v_role <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── allowed status: approved / rejected เท่านั้น ──
  if p_status not in ('approved','rejected') then
    raise exception 'invalid_review_status' using errcode = 'P0003';
  end if;

  if v_note is not null and char_length(v_note) > 1000 then
    v_note := left(v_note, 1000);
  end if;

  -- ── ต้องมีคำขออยู่จริง ──
  select true into v_found
  from public.delete_requests d where d.id = p_request_id limit 1;
  if not coalesce(v_found, false) then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;

  -- ── UPDATE สถานะ/ฟิลด์ review เท่านั้น — ❌ ไม่ DELETE ตารางใด ๆ ──
  return query
  update public.delete_requests d
  set
    status           = p_status,
    reviewed_by_code = p_username,
    reviewed_by_name = coalesce(nullif(btrim(coalesce(v_full_name,'')), ''), p_username),
    reviewed_at      = now(),
    review_note      = v_note
  where d.id = p_request_id
  returning
    d.id, d.created_at, d.requested_by_code, d.requested_by_name, d.requested_by_role,
    d.request_type, d.entity_type, d.entity_id, d.entity_name, d.detail, d.reason,
    d.status, d.reviewed_by_code, d.reviewed_by_name, d.reviewed_at, d.review_note;
end;
$$;

-- =============================================================
-- 4) Privileges — ปิด direct table access, เปิดเฉพาะ RPC
-- =============================================================
-- ปิด direct select/insert/update/delete บน delete_requests จาก client
--   (ทุกการเข้าถึงต้องผ่าน RPC SECURITY DEFINER ด้านบนเท่านั้น)
--   RLS policy เดิมคงไว้ (ไม่ DROP) — ถึงมี policy แต่ไม่มี table privilege ก็เข้าตรงไม่ได้
revoke select, insert, update, delete on table public.delete_requests from anon;
revoke select, insert, update, delete on table public.delete_requests from authenticated;

-- สิทธิ์เรียก RPC: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจตัวตนภายในเสมอ)
revoke all on function public.app_create_delete_request(text, text, text, text, text, text, text, jsonb) from public;
grant execute on function public.app_create_delete_request(text, text, text, text, text, text, text, jsonb) to anon, authenticated;

revoke all on function public.app_list_delete_requests(text, text, text, integer, integer) from public;
grant execute on function public.app_list_delete_requests(text, text, text, integer, integer) to anon, authenticated;

revoke all on function public.app_review_delete_request(text, text, bigint, text, text) from public;
grant execute on function public.app_review_delete_request(text, text, bigint, text, text) to anon, authenticated;
