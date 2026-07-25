-- =============================================================
-- F2/58L-FIX-1A — app_set_establishment_active: same-state no-op + audit ครั้งเดียว
-- เป้าหมาย (defense-in-depth ฝั่ง backend — ไม่แทนที่ frontend in-flight guard):
--   * คงสัญญาเดิมทุกอย่างของ app_set_establishment_active (จาก 20260804):
--     ชื่อฟังก์ชัน, argument types, return (id bigint, is_active boolean),
--     admin-only, error codes (unauthorized/invalid_arguments/establishment_not_found),
--     SECURITY DEFINER, search_path=public, grant execute anon/authenticated
--   * เพิ่ม: อ่าน+ล็อกแถวเป้าหมาย (FOR UPDATE) ก่อนตัดสิน
--   * ถ้า requested state == current state → NO-OP:
--       ❌ ไม่ UPDATE, ❌ ไม่แตะ updated_at/updated_by_code, ❌ ไม่เขียน audit
--       ✅ คืนผลสำเร็จที่ caller เดิมใช้ได้ (id, is_active ปัจจุบัน)
--   * ถ้า state เปลี่ยนจริง → UPDATE ครั้งเดียว + audit 'establishment.set_active' ครั้งเดียว
--     (audit detail ปลอดภัยเดิม: is_active/soft_toggle/internal_only)
--
--   ❗ additive ล้วน — CREATE OR REPLACE FUNCTION เท่านั้น
--   ❗ ไม่แตะตาราง/RLS/ACL อื่น, ไม่มี trigger, ไม่ลบ/แก้ข้อมูล, ไม่แตะ audit เดิม
--   ❗ ไม่แตะ fixture, ไม่มีคำสั่งเฉพาะ Production
--   ❗ ห้าม apply อัตโนมัติ — apply บน Staging ผ่านการอนุมัติแยก
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

create or replace function public.app_set_establishment_active(
  p_user_id          text,
  p_username         text,
  p_establishment_id bigint,
  p_is_active        boolean
)
returns table (id bigint, is_active boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_id        bigint;
  v_current   boolean;
begin
  -- ── ตัวตน + สิทธิ์: admin เท่านั้น (server-side บังคับจริง เหมือน 20260804) ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null or lower(v_role) <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_establishment_id is null or p_is_active is null then
    raise exception 'invalid_arguments' using errcode = 'P0003';
  end if;

  -- ── อ่าน+ล็อกแถวเป้าหมายก่อนตัดสิน (กัน 2 request ตัดสินพร้อมกันว่าต้องเปลี่ยน) ──
  select s.id, s.is_active into v_id, v_current
  from public.establishments s
  where s.id = p_establishment_id
  for update;

  if v_id is null then
    raise exception 'establishment_not_found' using errcode = 'P0002';
  end if;

  -- ── same-state → NO-OP: ไม่ update, ไม่แตะ timestamp/actor, ไม่เขียน audit ──
  if v_current is not distinct from p_is_active then
    return query select v_id, v_current;
    return;
  end if;

  -- ── state เปลี่ยนจริง → update ครั้งเดียว ──
  update public.establishments s
  set is_active = p_is_active, updated_at = now(), updated_by_code = p_username
  where s.id = p_establishment_id;

  -- ── audit log ฝั่ง server (best-effort) — เขียนเฉพาะเมื่อสถานะเปลี่ยนจริง ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'establishment.set_active', 'establishment', v_id::text,
            jsonb_build_object('is_active', p_is_active, 'soft_toggle', true, 'internal_only', true));
  exception when others then null;
  end;

  return query select v_id, p_is_active;
end;
$$;

-- ── สิทธิ์เดิม (RPC-only — pattern เดียวกับ 20260804) ──
revoke all on function public.app_set_establishment_active(text, text, bigint, boolean) from public;
grant execute on function public.app_set_establishment_active(text, text, bigint, boolean) to anon, authenticated;
