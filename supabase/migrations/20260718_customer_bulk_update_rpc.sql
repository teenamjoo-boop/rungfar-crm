-- =============================================================
-- STAGE 50A-5 — app_bulk_update_customers (SECURITY DEFINER, additive)
-- เป้าหมาย:
--   * ให้ "แก้ไขลูกค้าหลายรายการพร้อมกัน" (bulk group / assign / status) เขียนผ่าน
--     RPC ที่ตรวจตัวตน + server-stamp updated_by_code/updated_at แทน direct dbPatch
--   * รูปแบบ sanitize เดียวกับ app_save_customer (Stage 50A-1):
--     deny-list field อันตราย + เก็บเฉพาะคอลัมน์จริงของ customers + coerce ชนิดด้วย
--     jsonb_populate_record (เลียนแบบ PostgREST) — ค่าเข้าทาง bind param เท่านั้น
--
--   ❗ ไม่ revoke INSERT/UPDATE ตรงของ customers ในสเตจนี้ (additive/foundation)
--   ❗ ไม่ลบ row / ไม่ drop/truncate/rename / ไม่เปลี่ยนชนิดคอลัมน์
--   ❗ ไม่รับ/ไม่คืน file_data / base64 / storage_path / signed_url / bucket path / photo
--   ❗ ไม่รับ updated_by_code จาก client — server เป็นคน stamp เสมอ
--
-- ไม่แตะ: Edge Functions / Storage / LINE / Attendance / Meta Ads / RLS policy เดิม /
--         customer DELETE (ถูกบล็อกไว้แล้วที่ 20260710)
--
-- ⚠️ Additive / idempotent — create or replace function + grant เท่านั้น
-- =============================================================

create or replace function public.app_bulk_update_customers(
  p_user_id  text,
  p_username text,
  p_ids      bigint[],
  p_patch    jsonb default '{}'::jsonb
)
returns table (
  updated_count integer
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
  v_set_list text;
  v_count    integer := 0;
begin
  -- ── ตัวตน: active user จริง ──
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

  if p_ids is null or array_length(p_ids, 1) is null then
    raise exception 'ids_required' using errcode = 'P0003';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_patch' using errcode = 'P0003';
  end if;

  -- ── sanitize: ตัด deny-list + เก็บเฉพาะ key ที่เป็นคอลัมน์จริงของ customers ──
  v_data := p_patch - v_deny;
  select coalesce(jsonb_object_agg(t.key, v_data -> t.key), '{}'::jsonb)
    into v_data
  from jsonb_object_keys(v_data) as t(key)
  where t.key in (
    select c.column_name from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'customers'
  );

  -- ── server-stamp updated_at / updated_by_code (override client) ──
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_at') then
    v_data := v_data || jsonb_build_object('updated_at', now());
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='customers' and column_name='updated_by_code') then
    v_data := v_data || jsonb_build_object('updated_by_code', p_username);
  end if;

  -- ── สร้าง SET list (idents ผ่าน quote_ident) จาก key ที่เหลือ ──
  select string_agg(quote_ident(t.key) || ' = src.' || quote_ident(t.key), ', ')
    into v_set_list
  from jsonb_object_keys(v_data) as t(key);

  if v_set_list is null then
    raise exception 'no_valid_fields' using errcode = 'P0003';
  end if;

  -- ── UPDATE เฉพาะคอลัมน์ที่ส่งมา, เฉพาะ id ในลิสต์ (ค่าผ่าน bind $1 / ids ผ่าน $2) ──
  execute format(
    'update public.customers c set %s '
    || 'from jsonb_populate_record(null::public.customers, $1) src '
    || 'where c.id = any($2)',
    v_set_list
  ) using v_data, p_ids;
  get diagnostics v_count = row_count;

  return query select v_count;
end;
$$;

-- สิทธิ์เรียกใช้ (❗ ไม่ revoke UPDATE ตรงของ customers ในสเตจนี้)
revoke all on function public.app_bulk_update_customers(text, text, bigint[], jsonb) from public;
grant execute on function public.app_bulk_update_customers(text, text, bigint[], jsonb) to anon, authenticated;
