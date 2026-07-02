-- =============================================================
-- STAGE 52A-7 — Revoke Direct Write on public.employers / public.groups (safety lock)
-- เป้าหมาย:
--   * ปิดทาง "เขียนนายจ้าง/กลุ่มแบบ browser-direct" (anon key) — ประตูเขียนตรง
--     บานสุดท้ายของระบบ หลังจาก Stage 52A-6 (20260726) วางประตู server ครบแล้ว:
--       - สร้าง/แก้นายจ้าง  → app_save_employer  (SECURITY DEFINER, ตรวจตัวตน)
--       - สร้าง/แก้กลุ่ม    → app_save_group     (SECURITY DEFINER, ตรวจตัวตน)
--       - ลบกลุ่ม           → app_delete_group   (SECURITY DEFINER, admin เท่านั้น)
--     frontend เป็น RPC-first แล้วทุกจุด (saveEmployer / auto-create ใน customer save
--     และ import / saveGroup / delGrp) — path ตรงเหลือเป็น fallback เฉพาะกรณี
--     RPC error ซึ่งหลัง revoke จะได้ permission denied (ยอมรับได้ — RPC คือทางที่ถูก)
--
-- plain-language:
--   revoke = ปิดสิทธิ์เขียนตรงเก่า — browser แก้/เพิ่ม/ลบแถวนายจ้าง-กลุ่มเองไม่ได้อีก
--   ต่อไปทุกการเขียนต้องผ่าน RPC (ประตู server) ที่ตรวจตัวตนก่อนเสมอ
--
--   ทำไมไม่ revoke SELECT:
--   * หน้าเว็บยังอ่านรายชื่อนายจ้าง/กลุ่มตรงอยู่ (loadAll → dbGet('employers'/'groups')
--     ใช้ทำ dropdown, sidebar นับจำนวน, หน้านายจ้าง/กลุ่ม) — ปิดแล้วหน้าเว็บพังทันที
--   * ข้อมูลสองตารางนี้เป็น master data ไม่มี field อ่อนไหว (ไม่มีไฟล์/path/ข้อมูลลูกค้า)
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ INSERT / UPDATE / DELETE ตรงไม่ได้อีกต่อไป (ทั้งสองตาราง)
--                           ✅ SELECT ยังทำงานเหมือนเดิม (ไม่แตะ)
--   * SECURITY DEFINER RPC (รันด้วยสิทธิ์ owner): ไม่กระทบ — เขียนได้ตามปกติ
--   * การจัดกลุ่ม/ผูกนายจ้างให้ลูกค้า: ไม่เกี่ยวกับ grant สองตารางนี้ —
--     เขียนที่ customers ผ่าน app_save_customer / app_bulk_update_customers อยู่แล้ว
--
-- ⚠️ ไม่ revoke SELECT / ไม่แตะ RLS policy / ไม่ ALTER โครงสร้างตาราง
-- ⚠️ ไม่ DROP / ไม่ TRUNCATE / ไม่ DELETE ข้อมูลนายจ้าง/กลุ่ม/ลูกค้าใด ๆ
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าสิทธิ์ถูกถอนแล้ว)
--
-- รวมด้วย: อัปเดต app_admin_phase1_readiness_check ให้ตรวจ lock ใหม่ 2 แถว:
--   "ปิดเขียนตรง: ตารางนายจ้าง" / "ปิดเขียนตรง: ตารางกลุ่มงาน"
--   (โค้ดฟังก์ชัน = เวอร์ชัน 20260726 เดิม + 2 แถวใหม่ใน lock_defs เท่านั้น)
-- =============================================================

do $$
begin
  -- ── public.employers ──────────────────────────────────────────────────────
  if to_regclass('public.employers') is not null then
    -- เขียนนายจ้างต้องผ่าน app_save_employer เท่านั้น (ตรวจตัวตน + whitelist คอลัมน์)
    revoke insert on table public.employers from anon, authenticated;
    revoke update on table public.employers from anon, authenticated;
    revoke delete on table public.employers from anon, authenticated;
    raise notice 'safety-lock: revoked INSERT, UPDATE, DELETE on public.employers from anon, authenticated (writes via app_save_employer; SELECT untouched for UI reads)';
  else
    raise notice 'safety-lock: public.employers not found — skipped';
  end if;

  -- ── public.groups ─────────────────────────────────────────────────────────
  if to_regclass('public.groups') is not null then
    -- เขียนกลุ่มต้องผ่าน app_save_group / ลบผ่าน app_delete_group (admin เท่านั้น)
    revoke insert on table public.groups from anon, authenticated;
    revoke update on table public.groups from anon, authenticated;
    revoke delete on table public.groups from anon, authenticated;
    raise notice 'safety-lock: revoked INSERT, UPDATE, DELETE on public.groups from anon, authenticated (writes via app_save_group / app_delete_group; SELECT untouched for UI reads)';
  else
    raise notice 'safety-lock: public.groups not found — skipped';
  end if;
end$$;

-- =============================================================
-- readiness checker — เพิ่ม lock 2 แถว (employers / groups) ใน lock_defs
-- (ส่วนอื่นเหมือนเวอร์ชัน 20260726 ทุกประการ — ไม่คืน business data ใด ๆ)
-- =============================================================
create or replace function public.app_admin_phase1_readiness_check(
  p_admin_username text,
  p_admin_password text
)
returns table (
  check_key    text,
  check_label  text,
  check_status text,   -- pass / fail / warn / unauthorized
  check_group  text,   -- rpc / login / audit / delreq / locks / overall
  detail       text,
  sort_order   integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok    integer := 0;
  v_admin boolean := false;
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_verify_login'
  ) then
    return query select 'unauthorized'::text, 'ตรวจสิทธิ์ไม่สำเร็จ'::text,
      'unauthorized'::text, 'overall'::text, null::text, 0;
    return;
  end if;
  begin
    select count(*) into v_ok
    from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);
  exception when others then
    v_ok := 0;
  end;
  if coalesce(v_ok, 0) < 1 then
    return query select 'unauthorized'::text, 'รหัส ADMIN ไม่ถูกต้อง'::text,
      'unauthorized'::text, 'overall'::text, null::text, 0;
    return;
  end if;

  select (lower(coalesce(u.role, '')) = 'admin') into v_admin
  from public.app_users u where u.username = p_admin_username limit 1;
  if not coalesce(v_admin, false) then
    return query select 'unauthorized'::text, 'เฉพาะผู้ดูแลระบบ'::text,
      'unauthorized'::text, 'overall'::text, null::text, 0;
    return;
  end if;

  return query
  with
  fn_defs(fk, flbl, fmig, fgrp, fcrit, ford) as (values
    ('app_save_customer',              'RPC บันทึก/แก้ไขลูกค้า',        '20260716_customer_write_rpc.sql',            'rpc',    true, 10),
    ('app_bulk_update_customers',      'RPC แก้ไขลูกค้าแบบชุด',         '20260718_customer_bulk_update_rpc.sql',      'rpc',    true, 11),
    ('app_bulk_create_customers',      'RPC นำเข้าลูกค้า (Excel/CSV)',  '20260719_customer_import_write_rpc.sql',     'rpc',    true, 12),
    ('app_set_customer_photo_fallback','RPC รูปลูกค้าสำรอง',            '20260720_customer_photo_fallback_rpc.sql',   'rpc',    true, 13),
    ('app_update_document_metadata',   'RPC แก้ข้อมูลเอกสาร',           '20260705 / 20260706',                        'rpc',    true, 14),
    ('app_list_documents',             'RPC คลังเอกสาร',                '20260704 / 20260708',                        'rpc',    true, 15),
    ('app_document_summary',           'RPC สรุปเอกสาร',                '20260707_app_document_summary.sql',          'rpc',    true, 16),
    ('app_admin_audit_action_summary', 'RPC Dashboard การใช้งาน',       '20260715_audit_action_summary.sql',          'rpc',    true, 17),
    ('app_admin_list_security_logs',   'RPC ประวัติ Login/Security',    '20260621 / 20260713',                        'rpc',    true, 18),
    ('app_list_delete_requests',       'RPC รายการคำขอลบ',              '20260711_delete_requests_rpc_hardening.sql', 'rpc',    true, 19),
    ('app_save_employer',              'ประตู server นายจ้าง (app_save_employer)',  '20260726_employer_group_write_rpc.sql', 'rpc', true, 20),
    ('app_save_group',                 'ประตู server กลุ่มงาน (app_save_group)',    '20260726_employer_group_write_rpc.sql', 'rpc', true, 21),
    ('app_delete_group',               'ประตู server ลบกลุ่ม (app_delete_group)',   '20260726_employer_group_write_rpc.sql', 'rpc', true, 22),
    ('app_verify_login',               'ฟังก์ชันตรวจรหัสผ่าน (login)',  '(ติดตั้งพร้อมระบบ login)',                    'login',  true, 30),
    ('app_verify_session',             'ฟังก์ชันตรวจ session',          '20260608_app_users_rls_harden.sql',          'login',  true, 31),
    ('app_log_login_event',            'RPC บันทึกเหตุการณ์ login',     '20260712 / 20260713',                        'login',  false, 33),
    ('app_log_audit_event',            'RPC บันทึกประวัติการใช้งาน',    '20260712 / 20260714',                        'audit',  false, 41),
    ('app_create_delete_request',      'RPC สร้างคำขอลบ',               '20260711_delete_requests_rpc_hardening.sql', 'delreq', true, 51),
    ('app_review_delete_request',      'RPC อนุมัติ/ปฏิเสธคำขอลบ',      '20260711_delete_requests_rpc_hardening.sql', 'delreq', true, 52)
  ),
  fn_rows as (
    select
      ('rpc_' || d.fk)::text as k,
      d.flbl::text           as lbl,
      case when e.ok then 'pass' when d.fcrit then 'fail' else 'warn' end::text as st,
      d.fgrp::text            as grp,
      case when e.ok then 'ติดตั้งแล้ว'
           else 'ไม่พบฟังก์ชัน — apply migration ' || d.fmig end::text as det,
      d.ford                  as ord
    from fn_defs d
    cross join lateral (
      select exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = d.fk
      ) as ok
    ) e
  ),
  tbl_defs(tk, tlbl, tmig, tgrp, tord) as (values
    ('security_login_logs', 'ตาราง security_login_logs', '20260621 / 20260624', 'login',  32),
    ('audit_logs',          'ตาราง audit_logs',          '20260623_audit_logs.sql',      'audit',  40),
    ('delete_requests',     'ตาราง delete_requests',     '20260625_delete_requests.sql', 'delreq', 50)
  ),
  tbl_rows as (
    select
      ('table_' || t.tk)::text as k,
      t.tlbl::text             as lbl,
      case when to_regclass('public.' || t.tk) is not null then 'pass' else 'fail' end::text as st,
      t.tgrp::text             as grp,
      case when to_regclass('public.' || t.tk) is not null then 'พบตารางแล้ว'
           else 'ไม่พบตาราง — apply migration ' || t.tmig end::text as det,
      t.tord                   as ord
    from tbl_defs t
  ),
  lock_defs(lk, llbl, lmig, lord) as (values
    ('customers',           'ปิดเขียนตรง: ตารางลูกค้า',        '20260710 / 20260721 / 20260722', 60),
    ('documents',           'ปิดเขียนตรง: ตารางเอกสาร',        '20260710 / 20260723',            61),
    ('audit_logs',          'ปิดเขียนตรง: ประวัติการใช้งาน',   '20260623 / 20260712',            62),
    ('security_login_logs', 'ปิดเขียนตรง: ประวัติ login',      '20260712 / 20260725',            63),
    ('delete_requests',     'ปิดเขียนตรง: คำขอลบ',             '20260625 / 20260711',            64),
    ('employers',           'ปิดเขียนตรง: ตารางนายจ้าง',       '20260727_employer_group_revoke_direct_write.sql', 65),
    ('groups',              'ปิดเขียนตรง: ตารางกลุ่มงาน',      '20260727_employer_group_revoke_direct_write.sql', 66)
  ),
  lock_rows as (
    select
      ('lock_' || l.lk)::text as k,
      l.llbl::text            as lbl,
      case when to_regclass('public.' || l.lk) is null then 'fail'
           when x.leaks is null then 'pass'
           else 'fail' end::text as st,
      'locks'::text           as grp,
      case when to_regclass('public.' || l.lk) is null
             then 'ไม่พบตาราง — apply migration ' || l.lmig
           when x.leaks is null
             then 'ปิดสิทธิ์ INSERT/UPDATE/DELETE ครบ (browser เขียนตรงไม่ได้)'
           else 'ยังเปิดสิทธิ์: ' || x.leaks || ' — apply migration ' || l.lmig end::text as det,
      l.lord                  as ord
    from lock_defs l
    cross join lateral (
      select string_agg(rp.rolname || ':' || rp.priv, ', ' order by rp.rolname, rp.priv) as leaks
      from (
        select r.rolname, p.priv
        from (values ('anon'), ('authenticated')) r(rolname)
        cross join (values ('INSERT'), ('UPDATE'), ('DELETE')) p(priv)
      ) rp
      where case
        when to_regclass('public.' || l.lk) is null then false
        when not exists (select 1 from pg_roles g where g.rolname = rp.rolname) then false
        else has_table_privilege(rp.rolname, ('public.' || l.lk)::regclass, rp.priv)
      end
    ) x
  ),
  allrows as (
    select * from fn_rows
    union all select * from tbl_rows
    union all select * from lock_rows
  )
  select z.k, z.lbl, z.st, z.grp, z.det, z.ord from (
    select a.k, a.lbl, a.st, a.grp, a.det, a.ord from allrows a
    union all
    select
      'overall'::text,
      'ผลตรวจรวม Phase 1'::text,
      case when exists (select 1 from allrows a where a.st = 'fail') then 'fail'
           when exists (select 1 from allrows a where a.st = 'warn') then 'warn'
           else 'pass' end::text,
      'overall'::text,
      (
        'ผ่าน '   || (select count(*) from allrows a where a.st = 'pass') ||
        ' / เตือน ' || (select count(*) from allrows a where a.st = 'warn') ||
        ' / ไม่ผ่าน ' || (select count(*) from allrows a where a.st = 'fail') ||
        ' รายการ'
      )::text,
      999
  ) z
  order by z.ord;
end;
$$;

revoke all on function public.app_admin_phase1_readiness_check(text, text) from public;
grant execute on function public.app_admin_phase1_readiness_check(text, text) to anon, authenticated;
