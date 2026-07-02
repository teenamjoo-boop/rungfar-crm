-- =============================================================
-- STAGE 52A-6 — Employers / Groups Write RPC Foundation (additive, SECURITY DEFINER)
-- เป้าหมาย:
--   * ให้ create/edit นายจ้าง (employers) และ create/edit/delete กลุ่ม (groups)
--     ผ่าน RPC ที่ตรวจตัวตนฝั่ง server แทน direct dbPost/dbPatch/dbDel (anon key)
--   * เป็น "ฐาน" (foundation) แบบเดียวกับ Stage 50A-1 ของ customers:
--     ❗ ยังไม่ revoke สิทธิ์ direct INSERT/UPDATE/DELETE ของ employers/groups
--       ในสเตจนี้ — revoke เป็นสเตจถัดไป หลัง frontend ผ่านการทดสอบแล้ว
--   * whitelist เฉพาะคอลัมน์จริงของตาราง + deny-list field อันตราย/system
--   * ตัวตน = (user_id, username) ต้องตรงแถว app_users ที่ is_active และ role ไม่ null
--   * ลบกลุ่ม = admin เท่านั้น (ตรงกับ UI Stage 49A-2) — ลบเฉพาะแถว groups
--     ❌ ไม่ลบ/ไม่แก้ customers ใด ๆ (customer.group_id ปล่อยไว้ — UI จัดการ orphan เองอยู่แล้ว)
--
-- plain-language:
--   RPC = ประตูฝั่ง server ที่ตรวจตัวตนก่อนเขียนเสมอ — ปลอดภัยกว่าให้หน้าเว็บ
--   เขียนตารางตรง ๆ ด้วย public key (direct write) ซึ่งจะถูกปิดในสเตจถัดไป
--
--   ❗ ไม่ลบข้อมูลนายจ้าง/กลุ่ม/ลูกค้าใด ๆ ใน migration นี้ (ฟังก์ชันลบกลุ่มทำงาน
--     เฉพาะเมื่อ admin กดลบเท่านั้น) — ไม่แตะโครงสร้างตาราง / RLS / policy เดิม
--   ❗ ไม่รับ/ไม่คืน file_data / base64 / storage_path / signed_url / bucket path
--
-- รวมด้วย: อัปเดต app_admin_phase1_readiness_check (20260724) ให้ตรวจ 3 ฟังก์ชันใหม่
--   (กลุ่ม "ประตู server (RPC)") — ยังไม่บังคับตรวจ revoke ของ employers/groups
--
-- ไม่แตะ: customers write RPC เดิม / documents / import RPC / Edge Functions /
--         Storage / LINE / Attendance / Meta Ads
-- ⚠️ Additive + idempotent: create or replace function + grant เท่านั้น
-- =============================================================

-- =============================================================
-- 1) app_save_employer — create/update นายจ้างผ่านประตู server
-- =============================================================
create or replace function public.app_save_employer(
  p_user_id     text,
  p_username    text,
  p_employer_id bigint default null,   -- null = สร้างใหม่, มีค่า = แก้ไขตาม id
  p_data        jsonb  default '{}'::jsonb
)
returns table (
  id   bigint,
  name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active   boolean := false;
  v_data     jsonb;
  v_deny     text[] := array[
    'id','created_at','updated_at','deleted_at',
    'file_data','base64','storage_path','signed_url','signedurl','raw_bucket_path','bucket_path'
  ];
  v_col_list text;
  v_src_list text;
  v_set_list text;
  v_new_id   bigint;
  v_rowcount integer := 0;
begin
  -- ── ตัวตน: active user จริง (predicate เดียวกับ app_save_customer) ──
  select true into v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid_data' using errcode = 'P0003';
  end if;

  -- ── sanitize: ตัด deny-list → เก็บเฉพาะคอลัมน์จริงของ public.employers ──
  v_data := p_data - v_deny;
  select coalesce(jsonb_object_agg(t.key, v_data -> t.key), '{}'::jsonb)
    into v_data
  from jsonb_object_keys(v_data) as t(key)
  where t.key in (
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'employers'
  );

  -- ── create: ต้องมีชื่อนายจ้าง ──
  if p_employer_id is null and coalesce(btrim(v_data ->> 'name'), '') = '' then
    raise exception 'name_required' using errcode = 'P0003';
  end if;

  -- ── server-stamp updated_at (override ค่าจาก client เสมอ — ถ้ามีคอลัมน์) ──
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='employers' and column_name='updated_at') then
    v_data := v_data || jsonb_build_object('updated_at', now());
  end if;

  select string_agg(quote_ident(t.key), ', '),
         string_agg('src.' || quote_ident(t.key), ', '),
         string_agg(quote_ident(t.key) || ' = src.' || quote_ident(t.key), ', ')
    into v_col_list, v_src_list, v_set_list
  from jsonb_object_keys(v_data) as t(key);
  if v_col_list is null then
    raise exception 'no_valid_fields' using errcode = 'P0003';
  end if;

  if p_employer_id is null then
    -- CREATE — INSERT เฉพาะคอลัมน์ที่ส่งมา (ident ผ่าน quote_ident, ค่าผ่าน bind $1)
    execute format(
      'insert into public.employers (%s) '
      || 'select %s from jsonb_populate_record(null::public.employers, $1) src '
      || 'returning id',
      v_col_list, v_src_list
    ) using v_data into v_new_id;
  else
    -- UPDATE — เฉพาะคอลัมน์ที่ส่งมา (คอลัมน์อื่นคงเดิม — เหมือน PATCH)
    execute format(
      'update public.employers e set %s '
      || 'from jsonb_populate_record(null::public.employers, $1) src '
      || 'where e.id = $2',
      v_set_list
    ) using v_data, p_employer_id;
    get diagnostics v_rowcount = row_count;
    if v_rowcount = 0 then
      raise exception 'employer_not_found' using errcode = 'P0002';
    end if;
    v_new_id := p_employer_id;
  end if;

  -- ── คืน metadata ปลอดภัยเท่านั้น: id + name (❌ ไม่มี path/file ใด ๆ) ──
  return query
  select e.id, e.name from public.employers e where e.id = v_new_id;
end;
$$;

-- =============================================================
-- 2) app_save_group — create/update กลุ่มงานผ่านประตู server
--    (staff/admin ทำได้ทั้งคู่ — ตรงกับพฤติกรรม UI ปัจจุบัน)
-- =============================================================
create or replace function public.app_save_group(
  p_user_id  text,
  p_username text,
  p_group_id bigint default null,
  p_data     jsonb  default '{}'::jsonb
)
returns table (
  id   bigint,
  name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active   boolean := false;
  v_data     jsonb;
  v_deny     text[] := array[
    'id','created_at','updated_at','deleted_at',
    'file_data','base64','storage_path','signed_url','signedurl','raw_bucket_path','bucket_path'
  ];
  v_col_list text;
  v_src_list text;
  v_set_list text;
  v_new_id   bigint;
  v_rowcount integer := 0;
begin
  select true into v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid_data' using errcode = 'P0003';
  end if;

  -- ── sanitize: ตัด deny-list → เก็บเฉพาะคอลัมน์จริงของ public.groups (เช่น name/description) ──
  v_data := p_data - v_deny;
  select coalesce(jsonb_object_agg(t.key, v_data -> t.key), '{}'::jsonb)
    into v_data
  from jsonb_object_keys(v_data) as t(key)
  where t.key in (
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'groups'
  );

  if p_group_id is null and coalesce(btrim(v_data ->> 'name'), '') = '' then
    raise exception 'name_required' using errcode = 'P0003';
  end if;

  select string_agg(quote_ident(t.key), ', '),
         string_agg('src.' || quote_ident(t.key), ', '),
         string_agg(quote_ident(t.key) || ' = src.' || quote_ident(t.key), ', ')
    into v_col_list, v_src_list, v_set_list
  from jsonb_object_keys(v_data) as t(key);
  if v_col_list is null then
    raise exception 'no_valid_fields' using errcode = 'P0003';
  end if;

  if p_group_id is null then
    execute format(
      'insert into public.groups (%s) '
      || 'select %s from jsonb_populate_record(null::public.groups, $1) src '
      || 'returning id',
      v_col_list, v_src_list
    ) using v_data into v_new_id;
  else
    execute format(
      'update public.groups g set %s '
      || 'from jsonb_populate_record(null::public.groups, $1) src '
      || 'where g.id = $2',
      v_set_list
    ) using v_data, p_group_id;
    get diagnostics v_rowcount = row_count;
    if v_rowcount = 0 then
      raise exception 'group_not_found' using errcode = 'P0002';
    end if;
    v_new_id := p_group_id;
  end if;

  -- ❌ ไม่แตะ customers ใด ๆ — จัดกลุ่มลูกค้าไปทาง app_save_customer / app_bulk_update_customers
  return query
  select g.id, g.name from public.groups g where g.id = v_new_id;
end;
$$;

-- =============================================================
-- 3) app_delete_group — ลบกลุ่ม (admin เท่านั้น — ตรงกับ UI Stage 49A-2)
--    ลบเฉพาะแถวใน public.groups — ❌ ไม่ลบลูกค้า ❌ ไม่แก้ customer.group_id
--    (UI จัดการ group_id กำพร้าอยู่แล้ว: grpN() คืนค่าว่าง — ลูกค้าไม่หาย)
-- =============================================================
create or replace function public.app_delete_group(
  p_user_id  text,
  p_username text,
  p_group_id bigint
)
returns table (
  id      bigint,
  deleted boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text;
  v_rowcount integer := 0;
begin
  select u.role into v_role
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  -- ลบกลุ่ม = admin เท่านั้น (server-side บังคับจริง ไม่ใช่แค่ซ่อนปุ่ม)
  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_group_id is null then
    raise exception 'invalid_data' using errcode = 'P0003';
  end if;

  delete from public.groups g where g.id = p_group_id;
  get diagnostics v_rowcount = row_count;

  return query select p_group_id, (v_rowcount > 0);
end;
$$;

-- =============================================================
-- 4) สิทธิ์เรียกใช้ RPC (ฟังก์ชันตรวจตัวตนภายในก่อนเขียนเสมอ)
--    ❗ ไม่ revoke INSERT/UPDATE/DELETE ตรงของ employers/groups ในสเตจนี้
--      (foundation — ปิดประตูเขียนตรงเป็นสเตจถัดไป หลังทดสอบ frontend ผ่าน)
-- =============================================================
revoke all on function public.app_save_employer(text, text, bigint, jsonb) from public;
grant execute on function public.app_save_employer(text, text, bigint, jsonb) to anon, authenticated;

revoke all on function public.app_save_group(text, text, bigint, jsonb) from public;
grant execute on function public.app_save_group(text, text, bigint, jsonb) to anon, authenticated;

revoke all on function public.app_delete_group(text, text, bigint) from public;
grant execute on function public.app_delete_group(text, text, bigint) to anon, authenticated;

-- =============================================================
-- 5) อัปเดต readiness checker (20260724) — เพิ่มตรวจ 3 ประตู server ใหม่
--    (กลุ่ม 'rpc': app_save_employer / app_save_group / app_delete_group)
--    ❗ ยังไม่เพิ่ม employers/groups ในกลุ่ม locks — revoke เป็นสเตจถัดไป
--    (โค้ดฟังก์ชันด้านล่าง = เวอร์ชัน 20260724 เดิม + 3 แถวใหม่ใน fn_defs เท่านั้น)
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
