-- =============================================================
-- STAGE SHARE-GROUP-BANNER — รูปพื้นหลังหน้าลิงก์ของ "กลุ่ม" (เช่น สวนยาง) — additive
--   * เก็บเป็นเอกสาร documents.owner_type = 'group', owner_id = groups.id, doc_type = 'share_banner'
--     (อัปโหลดผ่าน Edge Function customer-doc-upload เวอร์ชัน cdu5 ขึ้นไป — path groups/<id>/...)
--   * "ใช้พื้นหลังส้มเดิม" = เปลี่ยน doc_type เป็น share_banner_off ด้วย app_update_document_metadata เดิม (ไม่ลบไฟล์)
--   * RPC ใหม่: app_get_group_banner — CRM ใช้ดูว่ากลุ่มมีรูปพื้นหลังอยู่หรือไม่ (คืน metadata เท่านั้น ❌ ไม่คืน path)
-- ❗ ไม่ลบข้อมูล · ไม่มี DROP TABLE · รันซ้ำได้
--   (เปลี่ยน check constraint documents_owner_type_check ให้รับ 'group' เพิ่ม — ค่าเดิมทั้งหมดยังใช้ได้เหมือนเดิม)
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf)
-- =============================================================

-- =============================================================
-- A) ให้ documents.owner_type รับค่า 'group'
-- =============================================================
alter table public.documents drop constraint if exists documents_owner_type_check;
alter table public.documents add constraint documents_owner_type_check
  check (owner_type = any (array['customer'::text, 'employer'::text, 'establishment'::text, 'case'::text, 'group'::text]));

-- =============================================================
-- B) app_get_group_banner — รูปพื้นหลังล่าสุดของกลุ่ม (ถ้ามี)
-- =============================================================
create or replace function public.app_get_group_banner(
  p_user_id  text,
  p_username text,
  p_group_id bigint
)
returns table (
  id          text,
  doc_name    text,
  doc_type    text,
  source      text,
  has_storage boolean,
  created_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_active boolean := false;
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

  return query
  select d.id::text, d.doc_name, d.doc_type, d.source, (d.storage_path is not null), d.created_at
  from public.documents d
  where d.owner_type = 'group'
    and d.owner_id = p_group_id
    and d.doc_type = 'share_banner'
  order by d.created_at desc nulls last
  limit 1;
end;
$$;

revoke all on function public.app_get_group_banner(text, text, bigint) from public;
grant execute on function public.app_get_group_banner(text, text, bigint) to anon, authenticated;

-- =============================================================
-- C) ตรวจผล — ควรได้ group_ok = 1, rpc_ok = 1
-- =============================================================
select
  (select count(*) from pg_constraint
    where conrelid = 'public.documents'::regclass
      and conname = 'documents_owner_type_check'
      and pg_get_constraintdef(oid) like '%group%')                       as group_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_get_group_banner')    as rpc_ok;
