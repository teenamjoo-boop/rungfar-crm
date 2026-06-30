-- =============================================================
-- STAGE 47A-2 — New Device / Suspicious Login Flags (alert-only, read-only)
-- เป้าหมาย:
--   * ให้ app_log_login_event "คำนวณ" is_new_device / is_suspicious ตอนเขียน log
--     เพื่อให้การ์ดสรุป "อุปกรณ์ใหม่ / น่าสงสัย" ในหน้า ประวัติการใช้งาน มีความหมายจริง
--   * เป็น alert-only / read-only สำหรับแอดมินรีวิวเท่านั้น:
--       ❌ ไม่บล็อก login  ❌ ไม่ลบ/แก้ข้อมูลลูกค้า  ❌ ไม่ revoke session  ❌ ไม่แจ้ง LINE
--       ✅ แค่ mark flag ในแถว log
--
--   คงพฤติกรรม Stage 47A-1 ทุกอย่าง:
--     SECURITY DEFINER, set search_path = public, signature เดิม,
--     success/logout ต้องเป็น active user จริง (server stamp identity),
--     failed ไม่ leak ว่ามี user, best-effort IP, insert ผ่าน jsonb_populate_record
--     (coerce ชนิดตรงคอลัมน์ live), ไม่มี direct insert จาก browser
--
--   เกณฑ์ (ง่าย/ปลอดภัย):
--     is_new_device (เฉพาะ success):
--       - มี device_fingerprint และ "ไม่เคย" มี success login เดิมของ user เดียวกัน
--         (user_id หรือ username) ที่ fingerprint เดียวกัน → true, ถ้าเคยเห็นแล้ว → false
--       - ไม่มี fingerprint → false ; failed/logout → false
--     is_suspicious:
--       - failed  : true เมื่อ failed ของ username นี้ (รวมครั้งนี้) ≥ 3 ครั้งใน 30 นาที
--       - success : true เมื่อ is_new_device=true หรือ มี failed ของ username นี้ ≥ 3 ครั้ง
--                   ใน 30 นาทีก่อนหน้า
--       - logout  : false
--     ใส่ค่า boolean เสมอ (true/false) ไม่ใส่ null (คอลัมน์ live อาจ NOT NULL)
--
-- ไม่แตะ:
--   * โครงสร้างตาราง (ไม่ drop/rename/alter type), ไม่ลบ row, ไม่แก้ข้อมูลเดิม
--   * app_log_audit_event, app_admin_list_security_logs/_audit_logs (อ่านเหมือนเดิม)
--   * customer/document/delete_requests, storage, Edge Functions, LINE, Attendance, Meta Ads
--
-- ⚠️ Additive: create index if not exists + create or replace function (return type เดิม
--    → ไม่ต้อง drop) — idempotent, รันซ้ำได้
-- =============================================================

-- ── ดัชนีช่วย query แบบ additive (กันสแกนทั้งตารางตอนคำนวณ flag) ──
create index if not exists idx_sll_fingerprint_status
  on public.security_login_logs (device_fingerprint, login_status);
create index if not exists idx_sll_username_time
  on public.security_login_logs (username, login_time desc);

-- ── เผื่อ default ยังไม่ถูกตั้ง (idempotent, ไม่กระทบแถวเดิม) ──
alter table public.security_login_logs alter column is_new_device set default false;
alter table public.security_login_logs alter column is_suspicious set default false;

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
  v_fp     text := nullif(left(btrim(coalesce(p_device_fingerprint, '')), 80), '');
  v_full   text;
  v_role   text;
  v_branch text;
  v_active boolean := false;
  v_ip     text;
  v_new    boolean := false;   -- is_new_device (default false — failed/logout/ไม่มี fp)
  v_susp   boolean := false;   -- is_suspicious (default false)
  v_recent_fails integer := 0; -- จำนวน failed ของ username นี้ใน 30 นาทีล่าสุด (ก่อน insert)
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
  begin
    v_ip := nullif(btrim(split_part(
              coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''),
              ',', 1)), '');
  exception when others then
    v_ip := null;
  end;

  -- ── คำนวณ flag (ใช้ "แถวที่มีอยู่ก่อน insert" เท่านั้น — ไม่รวมแถวปัจจุบัน) ──
  if v_status = 'success' then
    -- is_new_device: มี fingerprint และไม่เคยมี success login เดิมของ user เดียวกัน+fp เดียวกัน
    if v_fp is not null then
      if exists (
        select 1
        from public.security_login_logs s
        where s.login_status = 'success'
          and s.device_fingerprint = v_fp
          and ( (v_uid is not null and s.user_id = v_uid::bigint)
                or (v_uname is not null and s.username = v_uname) )
      ) then
        v_new := false;   -- เคยเห็น device นี้แล้ว
      else
        v_new := true;    -- อุปกรณ์ใหม่
      end if;
    else
      v_new := false;     -- ไม่มี fingerprint → ไม่ถือเป็นอุปกรณ์ใหม่ (stage นี้)
    end if;

    -- failed ของ username นี้ใน 30 นาทีก่อนหน้า (ก่อน success นี้)
    select count(*) into v_recent_fails
    from public.security_login_logs s
    where s.login_status = 'failed'
      and v_uname is not null and s.username = v_uname
      and s.login_time >= now() - interval '30 minutes';

    v_susp := v_new or (coalesce(v_recent_fails, 0) >= 3);

  elsif v_status = 'failed' then
    -- failed ก่อนหน้าของ username นี้ใน 30 นาที — รวมครั้งนี้ → ≥ 3 = น่าสงสัย
    select count(*) into v_recent_fails
    from public.security_login_logs s
    where s.login_status = 'failed'
      and v_uname is not null and s.username = v_uname
      and s.login_time >= now() - interval '30 minutes';

    v_susp := (coalesce(v_recent_fails, 0) + 1) >= 3;
    v_new  := false;

  else  -- logout
    v_new  := false;
    v_susp := false;
  end if;

  -- ── insert ผ่าน jsonb_populate_record → coerce ค่าให้ตรงชนิดจริงของคอลัมน์ (live user_id เป็น bigint) ──
  --    login_time ใช้ default now(); id เป็น identity จึงไม่ใส่; flag ใส่ boolean เสมอ (ไม่ null)
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
    'device_fingerprint', v_fp,
    'user_agent',         nullif(left(btrim(coalesce(p_user_agent, '')), 500), ''),
    'ip_address',         v_ip,
    'is_new_device',      v_new,
    'is_suspicious',      v_susp
  )) r
  returning
    security_login_logs.id, security_login_logs.login_time,
    security_login_logs.username, security_login_logs.login_status,
    security_login_logs.device_type, security_login_logs.browser_name;
end;
$$;

-- สิทธิ์เรียก RPC: re-assert (เผื่อรันไฟล์นี้แยก) — create or replace คงสิทธิ์เดิมอยู่แล้ว
revoke all on function public.app_log_login_event(text, text, text, text, text, text, text, text) from public;
grant execute on function public.app_log_login_event(text, text, text, text, text, text, text, text) to anon, authenticated;
