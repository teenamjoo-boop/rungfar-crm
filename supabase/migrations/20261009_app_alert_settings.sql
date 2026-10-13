-- =============================================================
-- STAGE ALERT-SETTINGS-DB — ค่าแจ้งเตือนล่วงหน้า (วัน) เก็บในฐานข้อมูลที่เดียว — additive
-- ปัญหาเดิม:
--   หน้า "ตั้งค่าแจ้งเตือน" เก็บค่าใน localStorage ของเบราว์เซอร์แต่ละเครื่อง
--   → คอมแต่ละเครื่องเตือนไม่เท่ากัน และหน้าลิงก์ลูกค้า (employer-share-view) อ่านค่าไม่ได้
-- ทำ:
--   A) ตาราง public.app_alert_settings (1 แถวเท่านั้น id=1) — RLS เปิด 0 policy, anon/authenticated ไม่มีสิทธิ์ตรง
--      service_role อ่านได้ (Edge Function ส่งค่าให้หน้าลิงก์ลูกค้า)
--   B) app_get_alert_settings  — ผู้ใช้ที่ active ทุกคนอ่านได้
--   C) app_save_alert_settings — admin เท่านั้น (หน้า ตั้งค่าแจ้งเตือน อยู่ในส่วนผู้ดูแลระบบ) + audit
--   ค่าเริ่มต้น = ค่าที่เจ้าของตั้งไว้ในหน้า ตั้งค่าแจ้งเตือน ณ 2026-10-09: พาสปอร์ต 30, VISA 30, WP 60, 90 วัน 7, MOU 60
-- ❗ ไม่แตะตารางธุรกิจเดิม / ไม่มี DELETE / DROP
-- ⚠️ Idempotent — รันซ้ำได้ (แถวค่าเริ่มต้นใส่ครั้งแรกเท่านั้น ไม่ทับค่าที่แก้แล้ว)
-- =============================================================

create table if not exists public.app_alert_settings (
  id              smallint    primary key default 1 check (id = 1),
  passport        integer     not null default 30 check (passport between 1 and 3650),
  visa            integer     not null default 30 check (visa     between 1 and 3650),
  wp              integer     not null default 60 check (wp       between 1 and 3650),
  next90          integer     not null default 7  check (next90   between 1 and 3650),
  mou             integer     not null default 60 check (mou      between 1 and 3650),
  updated_at      timestamptz not null default now(),
  updated_by_code text
);

alter table public.app_alert_settings enable row level security;
revoke all on table public.app_alert_settings from public, anon, authenticated;
-- Edge Function employer-share-view อ่านค่านี้ด้วย service role (โปรเจกต์นี้ต้อง grant ระบุชัด)
grant select on table public.app_alert_settings to service_role;

insert into public.app_alert_settings (id, passport, visa, wp, next90, mou)
values (1, 30, 30, 60, 7, 60)
on conflict (id) do nothing;

-- =============================================================
-- B) app_get_alert_settings
-- =============================================================
create or replace function public.app_get_alert_settings(
  p_user_id  text,
  p_username text
)
returns table (
  passport integer, visa integer, wp integer, next90 integer, mou integer,
  updated_at timestamptz, updated_by_code text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_ok boolean := false;
begin
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  return query
  select s.passport, s.visa, s.wp, s.next90, s.mou, s.updated_at, s.updated_by_code
  from public.app_alert_settings s
  where s.id = 1;
end;
$$;

revoke all on function public.app_get_alert_settings(text, text) from public;
grant execute on function public.app_get_alert_settings(text, text) to anon, authenticated;

-- =============================================================
-- C) app_save_alert_settings — admin เท่านั้น
-- =============================================================
create or replace function public.app_save_alert_settings(
  p_user_id  text,
  p_username text,
  p_passport integer,
  p_visa     integer,
  p_wp       integer,
  p_next90   integer,
  p_mou      integer
)
returns table (
  passport integer, visa integer, wp integer, next90 integer, mou integer,
  updated_at timestamptz, updated_by_code text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_role      text;
  v_full_name text;
  v_ok        boolean := false;
begin
  select u.role, u.full_name, true into v_role, v_full_name, v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_ok, false) or v_role <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_passport is null or p_visa is null or p_wp is null or p_next90 is null or p_mou is null
     or least(p_passport, p_visa, p_wp, p_next90, p_mou) < 1
     or greatest(p_passport, p_visa, p_wp, p_next90, p_mou) > 3650 then
    raise exception 'invalid_value' using errcode = 'P0003';
  end if;

  insert into public.app_alert_settings as s (id, passport, visa, wp, next90, mou, updated_at, updated_by_code)
  values (1, p_passport, p_visa, p_wp, p_next90, p_mou, now(), p_username)
  on conflict (id) do update
     set passport = excluded.passport, visa = excluded.visa, wp = excluded.wp,
         next90 = excluded.next90, mou = excluded.mou,
         updated_at = excluded.updated_at, updated_by_code = excluded.updated_by_code;

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'settings.alert.save', 'settings', '1',
            jsonb_build_object('passport', p_passport, 'visa', p_visa, 'wp', p_wp,
                               'next90', p_next90, 'mou', p_mou, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select s.passport, s.visa, s.wp, s.next90, s.mou, s.updated_at, s.updated_by_code
  from public.app_alert_settings s
  where s.id = 1;
end;
$$;

revoke all on function public.app_save_alert_settings(text, text, integer, integer, integer, integer, integer) from public;
grant execute on function public.app_save_alert_settings(text, text, integer, integer, integer, integer, integer) to anon, authenticated;
