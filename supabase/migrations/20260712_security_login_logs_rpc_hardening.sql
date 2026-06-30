-- =============================================================
-- STAGE 47A-1 — Security/Login Log Write RPC Hardening
-- เป้าหมาย:
--   * ย้าย "การเขียน log" จาก direct REST INSERT (client-trust, anon key)
--     ไปไว้หลัง RPC SECURITY DEFINER แล้วปิด direct INSERT ของ
--     public.security_login_logs และ public.audit_logs
--   * เพิ่ม logout logging (login_status='logout')
--   * เก็บ IP จริงฝั่ง server แบบ best-effort (x-forwarded-for) — ไม่เชื่อ client
--   * ❌ ยังไม่ทำ new-device/suspicious detection เต็มรูปแบบ (คงไว้ null)
--   * ❌ ไม่ทำ session management/revocation ใน stage นี้
--
--   อ่าน log ยังผ่าน RPC เดิม:
--     app_admin_list_security_logs / app_admin_list_audit_logs (ไม่แตะ)
--   login/auth ยังใช้ app_verify_login / app_verify_session (ไม่แตะ)
--
-- ไม่แตะ:
--   * customer/document/delete_requests flows, storage, Edge Functions,
--     LINE, Attendance, Meta Ads
--   * โครงสร้างคอลัมน์เดิม (ไม่ drop/rename), ไม่ลบ row
--
--   ❗ ไม่คืน/ไม่เก็บ file_data / base64 / storage_path / signed URL / bucket path
--   ❗ client เขียน log ตรงไม่ได้อีกต่อไป — ผ่าน RPC เท่านั้น (server เป็นคน stamp ตัวตน)
--
-- ⚠️ create table IF NOT EXISTS + ADD COLUMN IF NOT EXISTS = idempotent / กัน drift
--    (ตารางจริงมีอยู่แล้วใน live DB; บล็อกนี้เป็น no-op สำหรับ env เดิม + ใช้สร้าง env ใหม่)
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า login จึงจะบันทึก log ผ่าน RPC ได้
-- =============================================================

-- =============================================================
-- A) Version base schema (idempotent) — security_login_logs
-- =============================================================
create table if not exists public.security_login_logs (
  id                bigint generated always as identity primary key,
  login_time        timestamptz not null default now(),
  user_id           bigint,        -- ตรงกับ live DB (อ้างถึง app_users.id ที่เป็น bigint)
  username          text,
  full_name         text,
  role              text,
  branch_id         text,
  login_status      text not null,
  fail_reason       text,
  device_type       text,
  browser_name      text,
  device_fingerprint text,
  user_agent        text,
  ip_address        text,
  is_new_device     boolean not null default false,  -- live DB เป็น NOT NULL → ใส่ false ใน stage นี้
  is_suspicious     boolean not null default false   -- (ยังไม่ทำ detection จริง)
);

-- เติมคอลัมน์ที่อาจขาด (nullable เท่านั้น) — กัน drift, ไม่กระทบ insert/row เดิม
alter table public.security_login_logs add column if not exists login_time        timestamptz default now();
alter table public.security_login_logs add column if not exists user_id           bigint;
alter table public.security_login_logs add column if not exists username          text;
alter table public.security_login_logs add column if not exists full_name         text;
alter table public.security_login_logs add column if not exists role              text;
alter table public.security_login_logs add column if not exists branch_id         text;
alter table public.security_login_logs add column if not exists fail_reason       text;
alter table public.security_login_logs add column if not exists device_type       text;
alter table public.security_login_logs add column if not exists browser_name      text;
alter table public.security_login_logs add column if not exists device_fingerprint text;
alter table public.security_login_logs add column if not exists user_agent        text;
alter table public.security_login_logs add column if not exists ip_address        text;
alter table public.security_login_logs add column if not exists is_new_device     boolean;
alter table public.security_login_logs add column if not exists is_suspicious     boolean;

-- live DB อาจมี is_new_device / is_suspicious เป็น NOT NULL — ตั้ง default false ให้ insert ปลอดภัย
--   (เฉพาะ SET DEFAULT — ❌ ไม่ drop/rename column, ❌ ไม่แก้ข้อมูลแถวเดิม, ❌ ไม่ลบ row)
alter table public.security_login_logs alter column is_new_device set default false;
alter table public.security_login_logs alter column is_suspicious set default false;

-- =============================================================
-- B) app_log_login_event — เขียน login/logout/failed log (server stamp ตัวตน+IP)
-- =============================================================
-- drop ก่อน create เพราะ return columns เปลี่ยน (เพิ่ม browser_name) — create or replace
-- เปลี่ยน return type ไม่ได้; drop เฉพาะ function ไม่กระทบข้อมูล/ตาราง
drop function if exists public.app_log_login_event(text, text, text, text, text, text, text, text);

create or replace function public.app_log_login_event(
  p_user_id            text default null,
  p_username           text default null,
  p_login_status       text default null,
  p_fail_reason        text default null,
  p_device_type        text default null,
  p_browser_name       text default null,
  p_device_fingerprint text default null,
  p_user_agent         text default null
)
returns table (
  id           bigint,
  login_time   timestamptz,
  username     text,
  login_status text,
  device_type  text,
  browser_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(btrim(coalesce(p_login_status, '')));
  v_dev    text := lower(btrim(coalesce(p_device_type, '')));
  v_uid    text := nullif(btrim(coalesce(p_user_id, '')), '');
  v_uname  text := nullif(btrim(coalesce(p_username, '')), '');
  v_full   text;
  v_role   text;
  v_branch text;
  v_active boolean := false;
  v_ip     text;
begin
  -- ── validate login_status ──
  if v_status not in ('success','failed','logout') then
    raise exception 'invalid_login_status' using errcode = 'P0003';
  end if;

  -- ── device_type: เก็บเฉพาะค่าที่ valid (กัน junk) ──
  if v_dev not in ('desktop','mobile','tablet') then
    v_dev := null;
  end if;

  -- ── ตัวตน: success/logout ต้องเป็น active user จริง (server populate identity) ──
  --    failed: ❌ ไม่ lookup/ไม่ populate identity (กัน client spoof + กัน leak ว่ามี user)
  if v_status in ('success','logout') then
    -- user_id ต้องเป็นเลขล้วน — app_users.id เป็น bigint → กัน cast error ก่อนเทียบ
    if v_uid is null or v_uid !~ '^[0-9]+$' then
      raise exception 'unauthorized' using errcode = 'P0001';
    end if;
    select u.full_name, u.role, u.branch_id::text, true
      into v_full, v_role, v_branch, v_active
    from public.app_users u
    where u.id = v_uid::bigint
      and u.username = v_uname
      and coalesce(u.is_active, true) = true
      and u.role is not null
    limit 1;

    if not coalesce(v_active, false) then
      raise exception 'unauthorized' using errcode = 'P0001';
    end if;
  end if;

  -- ── IP จริงฝั่ง server (best-effort) — x-forwarded-for ตัวแรกในรายการ ──
  --    ❌ ไม่เชื่อค่า IP จาก client; ถ้าอ่านไม่ได้ → null
  begin
    v_ip := nullif(btrim(split_part(
              coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''),
              ',', 1)), '');
  exception when others then
    v_ip := null;
  end;

  -- ── insert ผ่าน jsonb_populate_record → coerce ค่าให้ "ตรงชนิดจริงของคอลัมน์" อัตโนมัติ ──
  --    แก้ปัญหา type mismatch: live DB มี user_id (และอาจรวม branch_id) เป็น bigint
  --    การส่งเป็น text แล้วให้ populate_record แปลงตามชนิดคอลัมน์ = ปลอดภัยทุกชนิด
  --    (เลียนแบบพฤติกรรม PostgREST เดิม) — login_time ใช้ default now(); id เป็น identity จึงไม่ใส่
  return query
  insert into public.security_login_logs (
    user_id, username, full_name, role, branch_id, login_status,
    fail_reason, device_type, browser_name, device_fingerprint, user_agent,
    ip_address, is_new_device, is_suspicious
  )
  select
    r.user_id, r.username, r.full_name, r.role, r.branch_id, r.login_status,
    r.fail_reason, r.device_type, r.browser_name, r.device_fingerprint, r.user_agent,
    r.ip_address, r.is_new_device, r.is_suspicious
  from jsonb_populate_record(null::public.security_login_logs, jsonb_build_object(
    'user_id',            case when v_status in ('success','logout') then v_uid   else null::text end,
    'username',           v_uname,
    'full_name',          case when v_status in ('success','logout') then v_full  else null::text end,
    'role',               case when v_status in ('success','logout') then v_role  else null::text end,
    'branch_id',          case when v_status in ('success','logout') then v_branch else null::text end,
    'login_status',       v_status,
    'fail_reason',        nullif(btrim(coalesce(p_fail_reason, '')), ''),
    'device_type',        v_dev,
    'browser_name',       nullif(left(btrim(coalesce(p_browser_name, '')), 60), ''),
    'device_fingerprint', nullif(left(btrim(coalesce(p_device_fingerprint, '')), 80), ''),
    'user_agent',         nullif(left(btrim(coalesce(p_user_agent, '')), 500), ''),
    'ip_address',         v_ip,
    'is_new_device',      false,   -- live DB เป็น NOT NULL → ใส่ false (ยังไม่คำนวณใน stage นี้)
    'is_suspicious',      false    -- live DB เป็น NOT NULL → ใส่ false (ยังไม่คำนวณใน stage นี้)
  )) r
  returning
    security_login_logs.id, security_login_logs.login_time,
    security_login_logs.username, security_login_logs.login_status,
    security_login_logs.device_type, security_login_logs.browser_name;
end;
$$;

-- =============================================================
-- C) app_log_audit_event — เขียน audit log (server stamp actor)
-- =============================================================
create or replace function public.app_log_audit_event(
  p_user_id     text,
  p_username    text,
  p_action      text,
  p_entity_type text  default null,
  p_entity_id   text  default null,
  p_detail      jsonb default '{}'::jsonb
)
returns table (
  id         bigint,
  created_at timestamptz,
  action     text,
  actor_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full   text;
  v_role   text;
  v_active boolean := false;
  v_action text := btrim(coalesce(p_action, ''));
  v_etype  text := nullif(btrim(coalesce(p_entity_type, '')), '');
begin
  -- ── ตัวตน: ต้องเป็น active user จริง (เหมือน RPC อื่นของระบบ) ──
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

  -- ── validate action / entity_type length (กัน junk/overflow) ──
  if char_length(v_action) < 1 or char_length(v_action) > 100 then
    raise exception 'invalid_action' using errcode = 'P0003';
  end if;
  if v_etype is not null and char_length(v_etype) > 50 then
    v_etype := left(v_etype, 50);
  end if;

  -- ── insert (actor มาจาก server ไม่ใช่ client) ──
  return query
  insert into public.audit_logs (
    actor_code, actor_name, actor_role, action, entity_type, entity_id, detail
  )
  values (
    p_username,
    coalesce(nullif(btrim(coalesce(v_full, '')), ''), p_username),
    v_role,
    v_action,
    v_etype,
    nullif(btrim(coalesce(p_entity_id, '')), ''),
    coalesce(p_detail, '{}'::jsonb)
  )
  returning
    audit_logs.id, audit_logs.created_at, audit_logs.action, audit_logs.actor_code;
end;
$$;

-- =============================================================
-- D) Privileges — ปิด direct INSERT, เปิดเฉพาะ RPC
-- =============================================================
-- client เขียน log ตรงไม่ได้อีกต่อไป (ทุกการเขียนผ่าน RPC SECURITY DEFINER เท่านั้น)
--   ไม่ revoke SELECT (อ่านผ่าน DEFINER RPC อยู่แล้ว) / ไม่ DROP policy เดิม
revoke insert on table public.security_login_logs from anon, authenticated;
revoke insert on table public.audit_logs           from anon, authenticated;

-- สิทธิ์เรียก RPC: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจตัวตนภายในตามชนิด event)
revoke all on function public.app_log_login_event(text, text, text, text, text, text, text, text) from public;
grant execute on function public.app_log_login_event(text, text, text, text, text, text, text, text) to anon, authenticated;

revoke all on function public.app_log_audit_event(text, text, text, text, text, jsonb) from public;
grant execute on function public.app_log_audit_event(text, text, text, text, text, jsonb) to anon, authenticated;
