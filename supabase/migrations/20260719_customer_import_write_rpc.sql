-- =============================================================
-- STAGE 50A-7 — Customer Import Write RPC (SECURITY DEFINER, additive)
-- เป้าหมาย:
--   * ให้ "นำเข้าลูกค้าหลายรายจาก Excel/CSV" (bulk create) เขียนผ่าน RPC ที่ตรวจตัวตน
--     + server-stamp actor/created_at แทน direct dbPost (anon key) — เป็น "ประตูหลังที่ปลอดภัย"
--   * รูปแบบ sanitize เดียวกับ app_save_customer (50A-1) / app_bulk_update_customers (50A-5):
--     deny-list field อันตราย + เก็บเฉพาะคอลัมน์จริงของ customers (whitelist ตาม information_schema)
--     + coerce ชนิดด้วย jsonb_populate_record (เลียนแบบ PostgREST) — ค่าเข้าทาง bind param เท่านั้น
--
--   ❗ ไม่ revoke INSERT/UPDATE ตรงของ customers ในสเตจนี้ (additive/foundation)
--   ❗ ไม่ DELETE/DROP/TRUNCATE/ALTER ข้อมูลลูกค้าเดิม / ไม่แตะ RLS/policy เดิม
--   ❗ ไม่รับ/ไม่คืน file_data / base64 / storage_path / signed_url / bucket path / photo
--   ❗ ไม่รับ id / created_at / updated_at จาก client — server เป็นคน stamp เสมอ
--   ❗ ไม่ redesign การตรวจซ้ำ (dedup ยังทำที่ frontend เหมือนเดิม)
--
--   วิธี write (robust ต่อสคีมา ~45 คอลัมน์):
--     - รับ p_rows jsonb (ต้องเป็น array) → วนทีละแถว (คงลำดับด้วย ordinality)
--     - แต่ละแถว: ตัด deny-list → เก็บเฉพาะคอลัมน์จริง → ต้องมี name → INSERT เฉพาะคอลัมน์ที่ส่งมา
--     - server-stamp created_at = now() ลบ offset เล็กน้อยตามลำดับแถว (ถ้ามีคอลัมน์)
--       เพื่อให้แถวที่นำเข้ายังเรียงตามลำดับไฟล์ (sort created_at DESC: แถวแรกใหม่สุด)
--     - server-stamp updated_at / updated_by_code (ถ้ามีคอลัมน์)
--     - dynamic SQL: ชื่อคอลัมน์ผ่าน quote_ident (กัน injection), ค่าผ่าน bind $1 (jsonb) เท่านั้น
--
-- ไม่แตะ: Edge Functions / Storage / LINE / Attendance / Meta Ads / customer DELETE
--
-- ⚠️ Additive / idempotent — create or replace function + grant เท่านั้น
-- ⚠️ ต้อง apply migration นี้ก่อน หน้า import จึงจะบันทึกผ่าน RPC
--    (ก่อน apply: frontend เตือน "กรุณา apply migration 20260719" แล้ว fallback ไป direct write เดิม)
-- =============================================================

create or replace function public.app_bulk_create_customers(
  p_user_id  text,
  p_username text,
  p_rows     jsonb default '[]'::jsonb
)
returns table (
  inserted_count integer,
  ids            bigint[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text;
  v_active   boolean := false;
  v_deny     text[] := array[
    'id','created_at','updated_at','deleted_at',
    'photo','photo_storage_path','photo_storage_bucket',
    'file_data','base64','storage_path','signed_url','signedurl','raw_bucket_path','bucket_path'
  ];
  v_has_created_at boolean;
  v_has_updated_at boolean;
  v_has_updated_by boolean;
  v_elem     jsonb;
  v_ord      bigint;
  v_data     jsonb;
  v_col_list text;
  v_src_list text;
  v_new_id   bigint;
  v_ids      bigint[] := array[]::bigint[];
  v_count    integer := 0;
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

  -- ── p_rows ต้องเป็น JSON array ──
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid_rows' using errcode = 'P0003';
  end if;

  -- ── ตรวจว่ามีคอลัมน์ stamp หรือไม่ (ครั้งเดียว) ──
  select exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='customers' and column_name='created_at')
    into v_has_created_at;
  select exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='customers' and column_name='updated_at')
    into v_has_updated_at;
  select exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='customers' and column_name='updated_by_code')
    into v_has_updated_by;

  -- ── วนทีละแถว (ordinality คงลำดับไฟล์นำเข้า) ──
  for v_elem, v_ord in
    select value, ordinality
    from jsonb_array_elements(p_rows) with ordinality
  loop
    -- แถวต้องเป็น object เท่านั้น (ข้ามค่าที่ไม่ใช่)
    if v_elem is null or jsonb_typeof(v_elem) <> 'object' then
      continue;
    end if;

    -- sanitize: ตัด deny-list ออก (รวม created_at/updated_at จาก client)
    v_data := v_elem - v_deny;

    -- เก็บเฉพาะ key ที่เป็น "คอลัมน์จริง" ของ public.customers (whitelist ตามสคีมาจริง)
    select coalesce(jsonb_object_agg(t.key, v_data -> t.key), '{}'::jsonb)
      into v_data
    from jsonb_object_keys(v_data) as t(key)
    where t.key in (
      select c.column_name
      from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = 'customers'
    );

    -- แต่ละแถวต้องมีชื่อ (frontend กรองไว้แล้ว — กันอีกชั้น, ข้ามแถวไร้ชื่อแบบเงียบ)
    if coalesce(btrim(v_data ->> 'name'), '') = '' then
      continue;
    end if;

    -- server-stamp created_at: now() ลบ offset ตามลำดับแถว → คงลำดับไฟล์ (แถวแรกใหม่สุด)
    if v_has_created_at then
      v_data := v_data || jsonb_build_object(
        'created_at', now() - ((v_ord - 1) * interval '1 millisecond')
      );
    end if;
    -- server-stamp updated_at / updated_by_code (override client)
    if v_has_updated_at then
      v_data := v_data || jsonb_build_object('updated_at', now());
    end if;
    if v_has_updated_by then
      v_data := v_data || jsonb_build_object('updated_by_code', p_username);
    end if;

    -- สร้างรายการคอลัมน์/ค่า (idents ผ่าน quote_ident) จาก key ที่เหลือ
    select string_agg(quote_ident(t.key), ', '),
           string_agg('src.' || quote_ident(t.key), ', ')
      into v_col_list, v_src_list
    from jsonb_object_keys(v_data) as t(key);

    if v_col_list is null then
      continue;
    end if;

    -- INSERT เฉพาะคอลัมน์ที่ส่งมา (ค่าผ่าน bind $1 → jsonb_populate_record; คอลัมน์อื่นใช้ default)
    execute format(
      'insert into public.customers (%s) '
      || 'select %s from jsonb_populate_record(null::public.customers, $1) src '
      || 'returning id',
      v_col_list, v_src_list
    ) using v_data into v_new_id;

    v_ids   := v_ids || v_new_id;
    v_count := v_count + 1;
  end loop;

  -- ── คืน metadata ปลอดภัยเท่านั้น (❌ ไม่มี photo/path/file) ──
  return query select v_count, v_ids;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจตัวตนภายในก่อนเขียนเสมอ)
-- ❗ ไม่ revoke INSERT ตรงของ public.customers ในสเตจนี้ (foundation)
revoke all on function public.app_bulk_create_customers(text, text, jsonb) from public;
grant execute on function public.app_bulk_create_customers(text, text, jsonb) to anon, authenticated;
