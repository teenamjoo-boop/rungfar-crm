-- =============================================================
-- RLS-HARDEN-2C / 2D — app_users
-- เป้าหมาย:
--   * app_users ไม่ให้ anon/client อ่านตรงทั้งตาราง (เปิด RLS + revoke grant)
--   * เพิ่ม column is_active เพื่อรองรับ "inactive user"
--   * เพิ่ม RPC app_verify_session (SECURITY DEFINER) สำหรับ re-validate session
--     ตอนเปิดหน้า/refresh → คืน user เฉพาะเมื่อยังมีอยู่ + active + role valid
--
-- ⚠️ ข้อควรระวังก่อน apply (สำคัญมาก):
--   หลังเปิด RLS ตาราง app_users จะอ่านตรงไม่ได้ ยกเว้นผ่าน function ที่เป็น
--   SECURITY DEFINER. ฉะนั้น app_verify_login / app_admin_list_users /
--   app_admin_create_user / app_admin_update_user / app_admin_delete_user
--   "ต้องเป็น SECURITY DEFINER" ไม่งั้น login/admin จะพังหลัง apply.
--   flow ปัจจุบันใช้ RPC เหล่านี้อยู่แล้ว (frontend ไม่ direct SELECT) → คาดว่าเป็น
--   DEFINER อยู่แล้ว แต่ให้ตรวจก่อน apply ด้วย query นี้:
--
--     select p.proname, p.prosecdef
--     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--     where n.nspname='public'
--       and p.proname in ('app_verify_login','app_admin_list_users',
--         'app_admin_create_user','app_admin_update_user','app_admin_delete_user');
--     -- prosecdef ต้องเป็น true ทุกตัว ก่อนรันส่วน "เปิด RLS" ด้านล่าง
--
--   ถ้าตัวใด prosecdef=false → แก้ให้เป็น SECURITY DEFINER ก่อน แล้วค่อยรัน block RLS
-- =============================================================

-- ── 1) is_active column (additive, ปลอดภัย) ───────────────────────────────────
alter table if exists public.app_users
  add column if not exists is_active boolean not null default true;

-- ── 2) RPC: re-validate session ──────────────────────────────────────────────
-- ใช้ตอนเปิด app/refresh เพื่อไม่ trust localStorage อย่างเดียว
--   * p_user_id เป็น text แล้ว cast (รองรับ id เป็น int/bigint/uuid โดยไม่ต้องเดา type)
--   * คืน jsonb ของ user (id,username,full_name,role,branch_id,is_active) หรือ null
--   * role normalize: admin → admin, อื่น ๆ → staff
--   * คืนค่าเฉพาะเมื่อ: row มีอยู่ + is_active + role ไม่ null
create or replace function public.app_verify_session(
  p_user_id text,
  p_username text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select to_jsonb(t) from (
    select
      u.id,
      u.username,
      u.full_name,
      case when u.role = 'admin' then 'admin' else 'staff' end as role,
      u.branch_id,
      coalesce(u.is_active, true) as is_active
    from public.app_users u
    where u.id::text = p_user_id
      and u.username = p_username
      and coalesce(u.is_active, true) = true
      and u.role is not null
    limit 1
  ) t;
$$;

revoke all on function public.app_verify_session(text, text) from public;
grant execute on function public.app_verify_session(text, text) to anon, authenticated;

-- ── 3) เปิด RLS + ปิด direct client access ───────────────────────────────────
-- ⚠️ apply block นี้ต่อเมื่อยืนยันแล้วว่า RPC ข้างบน (login/admin) เป็น SECURITY DEFINER
-- ไม่สร้าง policy ใด ๆ สำหรับ anon/authenticated → default deny (อ่าน/เขียนตรงไม่ได้)
-- SECURITY DEFINER function รันเป็น owner → ไม่ถูกบล็อกโดย RLS/revoke
alter table if exists public.app_users enable row level security;

revoke all on table public.app_users from anon;
revoke all on table public.app_users from authenticated;
