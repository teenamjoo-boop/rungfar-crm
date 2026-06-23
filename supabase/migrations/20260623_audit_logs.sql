-- =============================================================
-- AUDIT-LOG STAGE 1 — public.audit_logs (+ admin read RPC)
-- เป้าหมาย:
--   * บันทึก "ประวัติการใช้งานลูกค้า" ที่ปัจจุบันไม่มีร่องรอยเลย
--     Stage 1 = 4 action ที่อันตราย/สำคัญที่สุดสำหรับทีม 2–3 คน:
--       - customer.delete        ลบลูกค้า (เดี่ยว)
--       - customer.bulk_delete   ลบลูกค้าหลายราย
--       - document.delete        ลบเอกสาร
--       - customer.export        export CSV/Excel (PDPA)
--       - customer.assign        มอบหมายผู้รับผิดชอบ (bulk / self)
--   * ใช้ "Option B": ตาราง audit_logs generic ตัวเดียว — เพิ่มอย่างเดียว (additive)
--     ไม่แตะ login flow, work_timeline, contact_logs, documents, customers
--   * อ่านแบบ admin-only ผ่าน RPC SECURITY DEFINER เลียนแบบ
--     app_admin_list_security_logs เป๊ะ ๆ (ไม่เปิด direct SELECT ให้ใคร)
--
-- รูปแบบการบันทึก (ฝั่ง client): logAudit() ยิง INSERT ตรงด้วย anon key
--   แบบ best-effort เหมือน logLoginActivity — ถ้าล้มจะไม่ทำให้ action หลักพัง
--
-- ไม่แตะ (สำคัญ):
--   * security_login_logs / app_verify_login / app_admin_*_user — คงเดิม
--   * โครงสร้างตารางลูกค้า/เอกสาร/timeline — คงเดิม
--
-- ⚠️ ต้อง apply migration นี้ใน Supabase ก่อน
--    - ก่อน apply: action จะทำงานปกติ แต่ INSERT log จะ fail เงียบ (best-effort)
--      และแท็บ "การใช้งานลูกค้า" จะขึ้น "ยังไม่ได้ติดตั้ง — apply migration ก่อน"
-- =============================================================

-- 1) ตาราง audit_logs ----------------------------------------------------------
create table if not exists public.audit_logs (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  actor_code  text,            -- curUser.username (รหัสพนักงาน)
  actor_name  text,            -- curUser.full_name
  actor_role  text,            -- admin / staff ...
  action      text not null,   -- เช่น 'customer.delete', 'customer.export'
  entity_type text,            -- 'customer' | 'document'
  entity_id   text,            -- id ที่ถูกกระทำ (text รองรับ bulk/หลายค่า)
  detail      jsonb            -- {count, ids, name, fname, scope, ...} ยืดหยุ่น
);

create index if not exists idx_audit_logs_created_at on public.audit_logs (created_at desc);
create index if not exists idx_audit_logs_action     on public.audit_logs (action);
create index if not exists idx_audit_logs_actor      on public.audit_logs (actor_code);

-- 2) RLS — อนุญาตเฉพาะ INSERT (เหมือน security_login_logs), ห้าม SELECT ตรง --
alter table public.audit_logs enable row level security;

-- เขียน log ได้ทุก role (best-effort จาก client ด้วย anon key)
drop policy if exists audit_logs_insert_any on public.audit_logs;
create policy audit_logs_insert_any
  on public.audit_logs
  for insert
  to anon, authenticated
  with check (true);

-- สิทธิ์ตาราง: ให้ INSERT เท่านั้น (ไม่ให้ SELECT/UPDATE/DELETE ตรง — อ่านผ่าน RPC)
revoke all on table public.audit_logs from anon, authenticated;
grant insert on table public.audit_logs to anon, authenticated;

-- 3) RPC อ่านแบบ admin-only (เลียนแบบ app_admin_list_security_logs) ------------
create or replace function public.app_admin_list_audit_logs(
  p_admin_username text,
  p_admin_password text,
  p_start_date     date default null,
  p_end_date       date default null,
  p_actor          text default null,
  p_action         text default null
)
returns setof public.audit_logs
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

  -- 2) ยืนยันว่าเป็น admin จริง
  select (lower(coalesce(u.role, '')) = 'admin')
    into v_admin
  from public.app_users u
  where u.username = p_admin_username
  limit 1;

  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- 3) คืน log — filter → เรียงใหม่ก่อน → จำกัด 500 แถว
  return query
  select a.*
  from public.audit_logs a
  where
    (p_start_date is null or a.created_at >=  p_start_date::timestamptz)
    and (p_end_date is null or a.created_at <  ((p_end_date + 1))::timestamptz)
    and (
      p_actor is null or p_actor = ''
      or a.actor_code ilike '%' || p_actor || '%'
      or a.actor_name ilike '%' || p_actor || '%'
    )
    and (p_action is null or p_action = '' or a.action = p_action)
  order by a.created_at desc
  limit 500;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated เรียกได้ (เหมือน RPC แอดมินเดิม)
-- แต่ฟังก์ชันบังคับตรวจ admin credential ภายในก่อนคืนข้อมูลเสมอ
revoke all on function public.app_admin_list_audit_logs(text, text, date, date, text, text) from public;
grant execute on function public.app_admin_list_audit_logs(text, text, date, date, text, text) to anon, authenticated;
