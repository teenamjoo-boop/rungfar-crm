-- =============================================================
-- STAGE 23 — User active/disabled enforcement (ปิด/เปิดใช้งานบัญชี)
-- เป้าหมาย:
--   * Admin ปิด/เปิดใช้งานบัญชี staff ได้ (disable ไม่ใช่ลบถาวร)
--   * บัญชีที่ถูกปิด (is_active=false) ต้อง login ไม่ได้ และ session เดิมถูกเตะออก
--   * กันแอดมินปิดบัญชีตัวเอง + กันปิด admin คนสุดท้าย
--
-- หมายเหตุสถานะปัจจุบัน (ตรวจแล้ว):
--   * public.app_users.is_active มีอยู่แล้ว (migration 20260608_app_users_rls_harden.sql)
--   * public.app_verify_session บังคับ is_active=true อยู่แล้ว → session revalidation ใช้ได้ทันที
--   ดังนั้น migration นี้ "เพิ่ม" เฉพาะ:
--     1) คอลัมน์ disable metadata (optional, additive)
--     2) RPC app_admin_set_user_active (SECURITY DEFINER) สำหรับ toggle is_active
--        — เพราะ app_admin_update_user เดิมไม่มีพารามิเตอร์ is_active และ RLS
--          ปิด direct write ตาราง app_users ไว้
--
-- ⚠️ Additive only — ไม่ ALTER destructive, ไม่ DROP/RENAME คอลัมน์, ไม่แตะ RPC เดิม
-- ⚠️ RPC คืนเฉพาะฟิลด์ปลอดภัย (ไม่มี password) ผ่าน to_jsonb ของ subquery ที่เลือกคอลัมน์เอง
-- =============================================================

-- 1) คอลัมน์ disable metadata (additive, idempotent) -------------------------
alter table if exists public.app_users
  add column if not exists is_active        boolean not null default true, -- มีอยู่แล้วจาก 20260608 — assert ซ้ำปลอดภัย
  add column if not exists disabled_at       timestamptz,
  add column if not exists disabled_by_code  text,
  add column if not exists disabled_reason   text;

-- 2) RPC: เปิด/ปิดใช้งานบัญชี (admin-only, ตรวจรหัสผ่าน admin ภายใน) -----------
--   * ตรวจ credential admin ด้วย app_verify_login (scheme เดียวกับ RPC แอดมินเดิม)
--   * กันปิดบัญชีตัวเอง (cannot_disable_self)
--   * กันปิด admin คนสุดท้าย (last_admin)
--   * คืน jsonb ของ user (ฟิลด์ปลอดภัย ไม่มี password) หรือ raise exception
create or replace function public.app_admin_set_user_active(
  p_admin_username text,
  p_admin_password text,
  p_user_id        bigint,
  p_is_active      boolean,
  p_reason         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok            integer := 0;
  v_admin         boolean := false;
  v_target_role   text;
  v_other_admins  integer := 0;
  v_result        jsonb;
begin
  -- 1) ตรวจรหัสผ่าน admin (RPC login เดิม)
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);
  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 2) ยืนยันผู้เรียกเป็น admin จริง
  select (lower(coalesce(u.role, '')) = 'admin') into v_admin
  from public.app_users u where u.username = p_admin_username limit 1;
  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) safety: ปิดใช้งานเท่านั้นที่ต้องเช็ค self / last-admin
  if p_is_active is not true then
    -- 3a) ห้ามปิดบัญชีตัวเอง
    if exists (select 1 from public.app_users u where u.id = p_user_id and u.username = p_admin_username) then
      raise exception 'cannot_disable_self' using errcode = 'P0001';
    end if;
    -- 3b) ห้ามปิด admin คนสุดท้ายที่ยัง active
    select role into v_target_role from public.app_users where id = p_user_id;
    if lower(coalesce(v_target_role, '')) = 'admin' then
      select count(*) into v_other_admins
      from public.app_users
      where lower(coalesce(role, '')) = 'admin'
        and coalesce(is_active, true) = true
        and id <> p_user_id;
      if coalesce(v_other_admins, 0) < 1 then
        raise exception 'last_admin' using errcode = 'P0001';
      end if;
    end if;
  end if;

  -- 4) อัปเดตสถานะ + disable metadata (เปิดใช้งาน → ล้าง metadata)
  update public.app_users
     set is_active        = coalesce(p_is_active, true),
         disabled_at       = case when p_is_active is true then null else now() end,
         disabled_by_code  = case when p_is_active is true then null else p_admin_username end,
         disabled_reason   = case when p_is_active is true then null else p_reason end
   where id = p_user_id;

  if not found then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;

  -- 5) คืนเฉพาะฟิลด์ปลอดภัย (ไม่มี password)
  select to_jsonb(t) into v_result from (
    select
      u.id,
      u.username,
      u.full_name,
      case when u.role = 'admin' then 'admin' else 'staff' end as role,
      u.branch_id,
      coalesce(u.is_active, true) as is_active,
      u.disabled_at,
      u.disabled_by_code,
      u.disabled_reason
    from public.app_users u
    where u.id = p_user_id
    limit 1
  ) t;

  return v_result;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจ admin credential ภายในเสมอ)
revoke all on function public.app_admin_set_user_active(text, text, bigint, boolean, text) from public;
grant execute on function public.app_admin_set_user_active(text, text, bigint, boolean, text) to anon, authenticated;
