-- =============================================================
-- STAGE 52A-3 — app_admin_phase1_readiness_check (admin-only, READ-ONLY healthcheck)
-- เป้าหมาย:
--   * ให้ admin กดตรวจได้ว่า migration / RPC / ล็อกสิทธิ์เขียนตรง ของ Phase 1
--     ถูกติดตั้งใน Supabase ครบแล้วหรือยัง — จากหน้าตั้งค่า (readiness checker)
--   * อ่านอย่างเดียว 100%:
--       ❌ ไม่ INSERT / UPDATE / DELETE / DROP / TRUNCATE / ALTER ใด ๆ
--       ❌ ไม่อ่าน/ไม่คืน business data (ชื่อลูกค้า, ชื่อเอกสาร, file_data,
--          base64, storage_path, signed URL, bucket path, user-agent)
--       ✅ คืนเฉพาะสถานะทางเทคนิค: ชื่อฟังก์ชัน/ตาราง, ชื่อ role:สิทธิ์, ชื่อไฟล์ migration
--
-- plain-language:
--   readiness checker = ปุ่มตรวจสุขภาพระบบ — เช็คว่า "ประตู server" (RPC) ติดตั้งครบ
--   และ "ประตูเขียนตรงจาก browser" (direct write) ถูกปิด (revoke) แล้วจริงใน DB
--   healthcheck = ตรวจอย่างเดียว ไม่เพิ่ม/แก้/ลบข้อมูลจริง
--
--   ตรวจสิทธิ์ admin แบบเดียวกับ RPC admin เดิมทุกตัว (app_admin_audit_action_summary):
--     เช็ครหัสผ่านผ่าน app_verify_login + ยืนยัน role='admin'
--   รหัสผิด → คืนแถวเดียว status='unauthorized' — ❌ ไม่เผยรายละเอียดระบบใด ๆ
--
-- สิ่งที่ตรวจ (คืนเป็นแถว check_key / check_status: pass|warn|fail|unauthorized):
--   [rpc]    ฟังก์ชัน Phase 1 ครบ: app_save_customer, app_bulk_update_customers,
--            app_bulk_create_customers, app_set_customer_photo_fallback,
--            app_update_document_metadata, app_list_documents, app_document_summary,
--            app_admin_audit_action_summary, app_admin_list_security_logs,
--            app_list_delete_requests
--   [login]  app_verify_login / app_verify_session / app_log_login_event
--            + ตาราง security_login_logs
--   [audit]  ตาราง audit_logs + app_log_audit_event
--   [delreq] ตาราง delete_requests + app_create_delete_request / app_review_delete_request
--   [locks]  anon/authenticated ถูกปิด INSERT/UPDATE/DELETE บน:
--            customers (20260710/20260721/20260722), documents (20260710/20260723),
--            audit_logs (20260623/20260712), security_login_logs (20260712),
--            delete_requests (20260625)
--   [overall] แถวสรุป: pass ถ้า critical ผ่านหมด / warn ถ้ามีรายการ optional ขาด /
--             fail ถ้าฟังก์ชันหรือ lock สำคัญหาย
--
-- ไม่แตะ:
--   * ข้อมูล/โครงสร้างตารางใด ๆ, RLS policy, Storage, Edge Functions,
--     attendance, LINE notification, Meta Ads
-- ⚠️ Additive + idempotent: create or replace function + grant เท่านั้น
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
  -- ── 1) ตรวจรหัสผ่าน admin ด้วย RPC login เดิม (scheme เดียวกับ admin RPC ทุกตัว) ──
  --      รหัสผิด/ไม่ใช่ admin → คืนแถว unauthorized เดียว ❌ ไม่เผยรายละเอียดระบบ
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

  -- ── 2) ตรวจระบบ (อ่าน pg_catalog อย่างเดียว — ไม่แตะข้อมูลจริง) ──
  return query
  with
  -- ฟังก์ชันที่ต้องมี: (key, ป้ายไทย, migration ที่ต้อง apply, กลุ่ม, critical, ลำดับ)
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
  -- ตารางระบบที่ต้องมี (ไม่อ่านข้อมูลข้างใน — เช็คแค่ว่ามีตาราง)
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
  -- ล็อกสิทธิ์เขียนตรง: anon/authenticated ต้อง INSERT/UPDATE/DELETE ไม่ได้
  lock_defs(lk, llbl, lmig, lord) as (values
    ('customers',           'ปิดเขียนตรง: ตารางลูกค้า',        '20260710 / 20260721 / 20260722', 60),
    ('documents',           'ปิดเขียนตรง: ตารางเอกสาร',        '20260710 / 20260723',            61),
    ('audit_logs',          'ปิดเขียนตรง: ประวัติการใช้งาน',   '20260623 / 20260712',            62),
    ('security_login_logs', 'ปิดเขียนตรง: ประวัติ login',      '20260712',                       63),
    ('delete_requests',     'ปิดเขียนตรง: คำขอลบ',             '20260625 / 20260711',            64)
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
      -- คืนเฉพาะชื่อ role:สิทธิ์ ที่ยัง "รั่ว" — ไม่มีข้อมูลธุรกิจใด ๆ
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

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจรหัส admin ภายในก่อนคืนผลเสมอ —
-- รหัสผิดได้แค่แถว 'unauthorized' แถวเดียว ไม่มีรายละเอียดระบบ)
revoke all on function public.app_admin_phase1_readiness_check(text, text) from public;
grant execute on function public.app_admin_phase1_readiness_check(text, text) to anon, authenticated;
