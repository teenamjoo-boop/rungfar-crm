-- =============================================================
-- STAGE 50A-3 — Contact Log / Work Timeline Write RPC Foundation (additive)
-- เป้าหมาย:
--   * ให้ "บันทึกการติดต่อ" (contact_logs) และ "ไทม์ไลน์สถานะ" (work_timeline)
--     เขียนผ่าน RPC SECURITY DEFINER ที่ตรวจตัวตน + server-stamp created_by
--     แทน direct dbPost (anon key) ที่ created_by ถูก client กำหนดเอง (spoof ได้)
--   * ตัวตน = (user_id, username) ต้องตรงแถว app_users ที่ is_active และ role ไม่ null
--
--   ❗ ไม่ revoke INSERT/UPDATE/DELETE ตรงในสเตจนี้ (foundation)
--   ❗ ไม่ลบข้อมูล / ไม่ drop/rename / ไม่เปลี่ยนชนิดคอลัมน์เดิม
--   ❗ ไม่รับ/ไม่คืน file_data / base64 / storage_path / signed_url / bucket path
--   ❗ ไม่รับ created_by จาก client — server เป็นคน stamp เสมอ
--
--   contact_logs / work_timeline มีอยู่แล้วใน live DB (predate VC) →
--     create table if not exists + add column if not exists เป็น no-op บน env เดิม
--     (ใส่ไว้เพื่อ reproducibility + กัน drift เท่านั้น)
--
-- ไม่แตะ: Edge Functions / Storage / LINE / Attendance / Meta Ads / customers / RLS policy เดิม
--
-- ⚠️ Additive / idempotent — create table if not exists, add column if not exists,
--    create or replace function, grant เท่านั้น
-- =============================================================

-- ── โครงสร้างฐาน (idempotent, no-op ถ้ามีอยู่แล้ว) ──────────────────────────────
create table if not exists public.contact_logs (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  customer_id   bigint,
  contact_type  text,
  summary       text,
  docs_received text,
  docs_missing  text,
  next_action   text,
  next_date     date,
  created_by    text
);
alter table public.contact_logs add column if not exists customer_id   bigint;
alter table public.contact_logs add column if not exists contact_type  text;
alter table public.contact_logs add column if not exists summary       text;
alter table public.contact_logs add column if not exists docs_received text;
alter table public.contact_logs add column if not exists docs_missing  text;
alter table public.contact_logs add column if not exists next_action   text;
alter table public.contact_logs add column if not exists next_date     date;
alter table public.contact_logs add column if not exists created_by    text;

create table if not exists public.work_timeline (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  customer_id bigint,
  status      text,
  note        text,
  created_by  text
);
alter table public.work_timeline add column if not exists customer_id bigint;
alter table public.work_timeline add column if not exists status      text;
alter table public.work_timeline add column if not exists note        text;
alter table public.work_timeline add column if not exists created_by  text;

-- =============================================================
-- 1) app_add_contact_log — เพิ่มบันทึกการติดต่อ (server-stamp created_by)
-- =============================================================
create or replace function public.app_add_contact_log(
  p_user_id       text,
  p_username      text,
  p_customer_id   bigint,
  p_contact_type  text,
  p_summary       text,
  p_docs_received text default null,
  p_docs_missing  text default null,
  p_next_action   text default null,
  p_next_date     date default null
)
returns table (
  id         bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full   text;
  v_role   text;
  v_active boolean := false;
  v_by     text;
begin
  -- ── ตัวตน: active user จริง ──
  select u.full_name, u.role, true
    into v_full, v_role, v_active
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
    raise exception 'customer_required' using errcode = 'P0003';
  end if;
  if coalesce(btrim(p_summary), '') = '' then
    raise exception 'summary_required' using errcode = 'P0003';
  end if;

  v_by := coalesce(nullif(btrim(coalesce(v_full, '')), ''), p_username);

  return query
  insert into public.contact_logs (
    customer_id, contact_type, summary, docs_received, docs_missing,
    next_action, next_date, created_by
  )
  values (
    p_customer_id,
    nullif(left(btrim(coalesce(p_contact_type, '')), 50), ''),
    left(btrim(p_summary), 2000),
    nullif(left(btrim(coalesce(p_docs_received, '')), 2000), ''),
    nullif(left(btrim(coalesce(p_docs_missing, '')), 2000), ''),
    nullif(left(btrim(coalesce(p_next_action, '')), 2000), ''),
    p_next_date,
    v_by
  )
  returning contact_logs.id, contact_logs.created_at;
end;
$$;

-- =============================================================
-- 2) app_add_work_timeline — เพิ่มไทม์ไลน์สถานะ (server-stamp created_by)
-- =============================================================
create or replace function public.app_add_work_timeline(
  p_user_id     text,
  p_username    text,
  p_customer_id bigint,
  p_status      text,
  p_note        text default null
)
returns table (
  id         bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full   text;
  v_role   text;
  v_active boolean := false;
  v_by     text;
begin
  select u.full_name, u.role, true
    into v_full, v_role, v_active
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
    raise exception 'customer_required' using errcode = 'P0003';
  end if;
  if coalesce(btrim(p_status), '') = '' then
    raise exception 'status_required' using errcode = 'P0003';
  end if;

  v_by := coalesce(nullif(btrim(coalesce(v_full, '')), ''), p_username);

  return query
  insert into public.work_timeline (customer_id, status, note, created_by)
  values (
    p_customer_id,
    left(btrim(p_status), 100),
    nullif(left(btrim(coalesce(p_note, '')), 2000), ''),
    v_by
  )
  returning work_timeline.id, work_timeline.created_at;
end;
$$;

-- =============================================================
-- Permissions — เปิดเฉพาะ execute RPC (❗ ไม่ revoke table INSERT ในสเตจนี้)
-- =============================================================
revoke all on function public.app_add_contact_log(text, text, bigint, text, text, text, text, text, date) from public;
grant execute on function public.app_add_contact_log(text, text, bigint, text, text, text, text, text, date) to anon, authenticated;

revoke all on function public.app_add_work_timeline(text, text, bigint, text, text) from public;
grant execute on function public.app_add_work_timeline(text, text, bigint, text, text) to anon, authenticated;
