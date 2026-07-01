-- =============================================================
-- STAGE 50A-1 — Customer Write RPC Foundation (additive, SECURITY DEFINER)
-- เป้าหมาย:
--   * ให้ create/edit ลูกค้าผ่าน RPC ที่ตรวจตัวตน + server-stamp actor แทน
--     direct dbPost/dbPatch (anon key) — เป็น "ฐาน" ก่อน (ยังไม่ revoke สิทธิ์ direct)
--   * whitelisted columns เท่านั้น + deny-list field อันตราย/system
--   * ตัวตน = (user_id, username) ต้องตรงแถว app_users ที่ is_active และ role ไม่ null
--
--   ❗ ไม่ revoke INSERT/UPDATE ตรงของ customers ในสเตจนี้ (foundation)
--   ❗ ไม่ลบข้อมูล, ไม่แตะ RLS/policy เดิม
--   ❗ ไม่รับ/ไม่คืน file_data / base64 / storage_path / signed_url / bucket path / photo
--
--   วิธี write (robust ต่อสคีมา ~45 คอลัมน์ที่อยู่นอก VC):
--     - รับ p_data jsonb → ตัด deny-list → เก็บเฉพาะ key ที่ "เป็นคอลัมน์จริง" ของ customers
--     - server-stamp updated_at / updated_by_code (ถ้ามีคอลัมน์)
--     - coerce ชนิดด้วย jsonb_populate_record(null::customers, ...) (เหมือน PostgREST)
--     - create = INSERT เฉพาะคอลัมน์ที่ส่งมา (คอลัมน์อื่นใช้ default: id identity, created_at ฯลฯ)
--     - update = UPDATE เฉพาะคอลัมน์ที่ส่งมา (คอลัมน์อื่นคงค่าเดิม — เหมือน PATCH)
--     - dynamic SQL: ชื่อคอลัมน์ผ่าน quote_ident (กัน injection), ค่าผ่าน bind $1 (jsonb) เท่านั้น
--
-- ไม่แตะ: Edge Functions / Storage / LINE / Attendance / Meta Ads / customer DELETE
--
-- ⚠️ Additive: create or replace function + grant เท่านั้น (idempotent)
-- ⚠️ ต้อง apply migration นี้ก่อน หน้าเพิ่ม/แก้ไขลูกค้าจึงจะบันทึกผ่าน RPC
--    (ก่อน apply: frontend fallback ไป direct write เดิม + เตือนให้ apply)
-- =============================================================

create or replace function public.app_save_customer(
  p_user_id     text,
  p_username    text,
  p_customer_id bigint default null,   -- null = สร้างใหม่, มีค่า = แก้ไขตาม id
  p_data        jsonb  default '{}'::jsonb
)
returns table (
  id            bigint,
  name          text,
  customer_type text,
  work_status   text,
  updated_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text;
  v_active   boolean := false;
  v_data     jsonb;
  v_deny     text[] := array[
    'id','created_at','updated_at','deleted_at',
    'photo','photo_storage_path','photo_storage_bucket',
    'file_data','base64','storage_path','signed_url','signedurl','raw_bucket_path','bucket_path'
  ];
  v_col_list text;
  v_src_list text;
  v_set_list text;
  v_new_id   bigint;
  v_rowcount integer := 0;
begin
  -- ── ตัวตน: active user จริง (predicate เดียวกับ RPC อื่นของระบบ) ──
  select u.role, true
    into v_role, v_active
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

  -- ── sanitize: ตัด deny-list ออก ──
  v_data := p_data - v_deny;

  -- ── เก็บเฉพาะ key ที่เป็น "คอลัมน์จริง" ของ public.customers (whitelist ตามสคีมาจริง) ──
  select coalesce(jsonb_object_agg(t.key, v_data -> t.key), '{}'::jsonb)
    into v_data
  from jsonb_object_keys(v_data) as t(key)
  where t.key in (
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'customers'
  );

  -- ── create: ต้องมีชื่อ ──
  if p_customer_id is null and coalesce(btrim(v_data ->> 'name'), '') = '' then
    raise exception 'name_required' using errcode = 'P0003';
  end if;

  -- ── server-stamp actor/updated_at (override ค่าจาก client เสมอ) ──
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_at') then
    v_data := v_data || jsonb_build_object('updated_at', now());
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_by_code') then
    v_data := v_data || jsonb_build_object('updated_by_code', p_username);
  end if;

  -- ── สร้างรายการคอลัมน์/ค่า/SET จาก key ที่เหลือ (idents ผ่าน quote_ident) ──
  select string_agg(quote_ident(t.key), ', '),
         string_agg('src.' || quote_ident(t.key), ', '),
         string_agg(quote_ident(t.key) || ' = src.' || quote_ident(t.key), ', ')
    into v_col_list, v_src_list, v_set_list
  from jsonb_object_keys(v_data) as t(key);

  if v_col_list is null then
    raise exception 'no_valid_fields' using errcode = 'P0003';
  end if;

  if p_customer_id is null then
    -- ── CREATE — INSERT เฉพาะคอลัมน์ที่ส่งมา (ค่าผ่าน bind $1 → jsonb_populate_record) ──
    execute format(
      'insert into public.customers (%s) '
      || 'select %s from jsonb_populate_record(null::public.customers, $1) src '
      || 'returning id',
      v_col_list, v_src_list
    ) using v_data into v_new_id;
  else
    -- ── UPDATE — เฉพาะคอลัมน์ที่ส่งมา (คอลัมน์อื่นคงเดิม) ──
    execute format(
      'update public.customers c set %s '
      || 'from jsonb_populate_record(null::public.customers, $1) src '
      || 'where c.id = $2',
      v_set_list
    ) using v_data, p_customer_id;
    get diagnostics v_rowcount = row_count;
    if v_rowcount = 0 then
      raise exception 'customer_not_found' using errcode = 'P0002';
    end if;
    v_new_id := p_customer_id;
  end if;

  -- ── คืน metadata ปลอดภัยเท่านั้น (❌ ไม่มี photo/path/file) ──
  return query
  select c.id, c.name, c.customer_type, c.work_status, c.updated_at
  from public.customers c
  where c.id = v_new_id;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจตัวตนภายในก่อนเขียนเสมอ)
-- ❗ ไม่ revoke INSERT/UPDATE ตรงของ public.customers ในสเตจนี้ (foundation)
revoke all on function public.app_save_customer(text, text, bigint, jsonb) from public;
grant execute on function public.app_save_customer(text, text, bigint, jsonb) to anon, authenticated;
