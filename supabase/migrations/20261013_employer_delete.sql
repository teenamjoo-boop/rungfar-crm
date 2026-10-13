-- =============================================================
-- STAGE EMP-DELETE — ลบนายจ้างจาก CRM (แอดมินเท่านั้น) + แก้ลบกลุ่มที่มีลิงก์รวมไม่ได้
--   * app_delete_employer(p_user_id, p_username, p_employer_id, p_confirm_name)
--       - ตรวจตัวตนฝั่ง server: ต้องเป็น admin ที่ active
--       - ต้องส่งชื่อนายจ้างมายืนยัน (กันลบผิดตัว)
--       - ลบได้เฉพาะนายจ้างที่ "ไม่มีอะไรผูกอยู่": แรงงาน (ที่ยังไม่ถูกลบ) / เคส / สถานประกอบการ / เอกสารนายจ้าง
--         ถ้ามี → ไม่ลบ คืนจำนวนที่ผูกอยู่ให้หน้าเว็บแจ้งผู้ใช้
--       - ลิงก์หน้านายจ้าง + รายการรูปพื้นหลังของนายจ้างนี้ ลบตามไปด้วย (เป็นของนายจ้างนี้เท่านั้น)
--       - แรงงานที่ถูกลบไปแล้ว (soft delete) ที่ยังอ้างนายจ้างนี้ → ตัดการอ้างอิง (FK เดิม ON DELETE SET NULL)
--       - บันทึก audit_logs 'employer.delete' (ไม่มีข้อมูลส่วนตัว)
--   * group_share_links → groups: ON DELETE CASCADE (เดิมลบกลุ่มที่มีลิงก์รวมไม่ได้)
-- ❗ ไม่ลบข้อมูลใด ๆ ตอนรันไฟล์นี้ — แค่สร้างฟังก์ชัน · รันซ้ำได้
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf)
-- =============================================================

-- A) ลบกลุ่มที่มีลิงก์รวมได้ (ลิงก์ของกลุ่มนั้นลบตาม)
alter table public.group_share_links drop constraint if exists group_share_links_group_id_fkey;
alter table public.group_share_links add constraint group_share_links_group_id_fkey
  foreign key (group_id) references public.groups(id) on delete cascade;

-- B) app_delete_employer
create or replace function public.app_delete_employer(
  p_user_id      text,
  p_username     text,
  p_employer_id  bigint,
  p_confirm_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role   text;
  v_full   text;
  v_name   text;
  n_cust   integer := 0;
  n_soft   integer := 0;
  n_cases  integer := 0;
  n_est    integer := 0;
  n_docs   integer := 0;
  n_links  integer := 0;
  n_banner integer := 0;
begin
  select u.role, u.full_name into v_role, v_full
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  -- ลบนายจ้าง = admin เท่านั้น (บังคับฝั่ง server)
  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;
  if p_employer_id is null then
    raise exception 'invalid_data' using errcode = 'P0003';
  end if;

  select e.name into v_name from public.employers e where e.id = p_employer_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if p_confirm_name is null or btrim(p_confirm_name) <> btrim(coalesce(v_name, '')) then
    return jsonb_build_object('ok', false, 'error', 'name_mismatch');
  end if;

  select count(*) filter (where c.deleted_at is null),
         count(*) filter (where c.deleted_at is not null)
    into n_cust, n_soft
  from public.customers c where c.employer_id = p_employer_id;
  select count(*) into n_cases from public.cases k where k.employer_id = p_employer_id;
  select count(*) into n_est   from public.establishments s where s.employer_id = p_employer_id;
  select count(*) into n_docs  from public.documents d
   where d.owner_type = 'employer' and d.owner_id = p_employer_id
     and coalesce(d.doc_type, '') not like 'share_banner%';

  if n_cust > 0 or n_cases > 0 or n_est > 0 or n_docs > 0 then
    return jsonb_build_object('ok', false, 'error', 'has_dependents',
      'customers', n_cust, 'cases', n_cases, 'establishments', n_est, 'documents', n_docs);
  end if;

  delete from public.employer_share_links l where l.employer_id = p_employer_id;
  get diagnostics n_links = row_count;
  delete from public.documents d
   where d.owner_type = 'employer' and d.owner_id = p_employer_id
     and coalesce(d.doc_type, '') like 'share_banner%';
  get diagnostics n_banner = row_count;
  delete from public.employers e where e.id = p_employer_id;

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username, coalesce(nullif(btrim(coalesce(v_full, '')), ''), p_username), v_role,
            'employer.delete', 'employer', p_employer_id::text,
            jsonb_build_object('name', v_name, 'links_removed', n_links, 'banners_removed', n_banner,
                               'deleted_workers_unlinked', n_soft));
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', p_employer_id, 'name', v_name);
end;
$$;

revoke all on function public.app_delete_employer(text, text, bigint, text) from public;
grant execute on function public.app_delete_employer(text, text, bigint, text) to anon, authenticated;

-- C) ตรวจผล — ควรได้ rpc_ok = 1, cascade_ok = 1
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_delete_employer')                       as rpc_ok,
  (select count(*) from pg_constraint
    where conname = 'group_share_links_group_id_fkey'
      and pg_get_constraintdef(oid) like '%ON DELETE CASCADE%')                            as cascade_ok;
