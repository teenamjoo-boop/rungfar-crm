-- =============================================================
-- STAGE 48A-1 — Audit Detail Privacy Hardening (scrub + server-side sanitize)
-- เป้าหมาย:
--   1) ลบ key ที่ไม่ปลอดภัยออกจาก public.audit_logs.detail ที่ "มีอยู่เดิม"
--      (เช่น storage_path ที่ document.upload.storage เคยเก็บ)
--   2) ให้ app_log_audit_event "sanitize" p_detail ฝั่ง server ก่อน insert
--      → แม้ caller เผลอส่ง key ไม่ปลอดภัยในอนาคต ก็จะไม่ถูกเก็บ
--
--   key ที่ถือว่าไม่ปลอดภัย (ลบทิ้ง top-level):
--     storage_path, storagePath, signed_url, signedUrl,
--     file_data, base64, raw_bucket_path, bucket_path
--   เมื่อมีการลบจริง → ใส่ marker { "redacted_storage_path": true }
--
-- ไม่ทำ (สำคัญ):
--   ❌ ไม่ลบแถว audit_logs / ไม่ลบ customers/documents/files
--   ❌ ไม่ drop/rename column / ไม่แตะ RLS/grant (insert ถูก revoke ไว้แล้ว — 47A-1)
--   ❌ ไม่แตะ storage / Edge Functions / LINE / Attendance / Meta Ads
--   ❌ ไม่เปลี่ยน signature ของ app_log_audit_event
--
--   อัปเดตเฉพาะ public.audit_logs.detail (privacy) เท่านั้น
--
-- ⚠️ Idempotent — รันซ้ำได้:
--   * scrub UPDATE จับเฉพาะแถวที่ "ยังมี" key ไม่ปลอดภัย → รันซ้ำไม่มีผลเพิ่ม
--   * create or replace function (return type เดิม → ไม่ต้อง drop)
-- =============================================================

-- =============================================================
-- A) Scrub แถวเดิม — ลบ key ไม่ปลอดภัยออกจาก detail (เฉพาะที่เป็น jsonb object)
-- =============================================================
update public.audit_logs
set detail = (
      detail
        - 'storage_path' - 'storagePath'
        - 'signed_url'   - 'signedUrl'
        - 'file_data'    - 'base64'
        - 'raw_bucket_path' - 'bucket_path'
    ) || jsonb_build_object('redacted_storage_path', true)
where detail is not null
  and jsonb_typeof(detail) = 'object'
  and detail ?| array[
        'storage_path','storagePath','signed_url','signedUrl',
        'file_data','base64','raw_bucket_path','bucket_path'
      ];

-- =============================================================
-- B) app_log_audit_event — เพิ่ม server-side sanitize ของ p_detail (signature เดิม)
-- =============================================================
create or replace function public.app_log_audit_event(
  p_user_id     text,
  p_username    text,
  p_action      text,
  p_entity_type text  default null,
  p_entity_id   text  default null,
  p_detail      jsonb default '{}'::jsonb
)
returns table (
  id         bigint,
  created_at timestamptz,
  action     text,
  actor_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full   text;
  v_role   text;
  v_active boolean := false;
  v_action text := btrim(coalesce(p_action, ''));
  v_etype  text := nullif(btrim(coalesce(p_entity_type, '')), '');
  v_detail jsonb := coalesce(p_detail, '{}'::jsonb);
begin
  -- ── ตัวตน: ต้องเป็น active user จริง (เหมือน RPC อื่นของระบบ) ──
  select u.full_name, u.role, true
    into v_full, v_role, v_active
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_active, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── validate action / entity_type length (กัน junk/overflow) ──
  if char_length(v_action) < 1 or char_length(v_action) > 100 then
    raise exception 'invalid_action' using errcode = 'P0003';
  end if;
  if v_etype is not null and char_length(v_etype) > 50 then
    v_etype := left(v_etype, 50);
  end if;

  -- ── sanitize detail ฝั่ง server: ลบ key ไม่ปลอดภัย (กัน caller เผลอส่ง) ──
  --    เฉพาะกรณี detail เป็น jsonb object และมี key ไม่ปลอดภัยจริงเท่านั้น
  if jsonb_typeof(v_detail) = 'object'
     and v_detail ?| array[
           'storage_path','storagePath','signed_url','signedUrl',
           'file_data','base64','raw_bucket_path','bucket_path'
         ] then
    v_detail := (
        v_detail
          - 'storage_path' - 'storagePath'
          - 'signed_url'   - 'signedUrl'
          - 'file_data'    - 'base64'
          - 'raw_bucket_path' - 'bucket_path'
      ) || jsonb_build_object('redacted_storage_path', true);
  end if;

  -- ── insert (actor มาจาก server ไม่ใช่ client; detail ถูก sanitize แล้ว) ──
  return query
  insert into public.audit_logs (
    actor_code, actor_name, actor_role, action, entity_type, entity_id, detail
  )
  values (
    p_username,
    coalesce(nullif(btrim(coalesce(v_full, '')), ''), p_username),
    v_role,
    v_action,
    v_etype,
    nullif(btrim(coalesce(p_entity_id, '')), ''),
    v_detail
  )
  returning
    audit_logs.id, audit_logs.created_at, audit_logs.action, audit_logs.actor_code;
end;
$$;

-- สิทธิ์เรียก RPC: re-assert (create or replace คงสิทธิ์เดิมอยู่แล้ว) — insert ตรงยังถูก revoke ไว้
revoke all on function public.app_log_audit_event(text, text, text, text, text, jsonb) from public;
grant execute on function public.app_log_audit_event(text, text, text, text, text, jsonb) to anon, authenticated;
