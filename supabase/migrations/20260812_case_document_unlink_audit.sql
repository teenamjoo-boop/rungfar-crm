-- =============================================================
-- STAGE 58K-B3-FIX-UNLINK-AUDIT — app_unlink_case_document: เพิ่ม audit log ที่หายไป
--
-- ปัญหาที่พบ (runtime test 58K-B3 บน staging):
--   * unlink ทำงานถูกต้อง (ลบแถว case_documents, documents ต้นฉบับอยู่ครบ)
--   * แต่ audit_logs "ไม่มี" action 'case.document.unlink' เลย —
--     ต่างจาก 'case.document.link' ที่บันทึกครบ (6 แถวจาก T1–T7)
--   → สาเหตุหลัก: นิยาม unlink ที่ deploy บน staging เป็น draft เก่าที่ไม่มี
--     (หรือมีแบบพัง) audit block และไม่เคยถูก replace อีก (20260811 ตั้งใจไม่แตะ unlink)
--
-- เป้าหมาย (scope แคบ — เฉพาะ audit ของ unlink):
--   * replace public.app_unlink_case_document ด้วยนิยามที่ "เขียน audit เสมอ"
--   * เก็บ attribution (58K-A) ผ่าน RETURNING ก่อนแถวหาย → detail ครบ
--   * ❗ audit fail = unlink transaction fail (ไม่ swallow) — ไม่ให้เกิด
--     "ลบสำเร็จแต่ไม่มี audit" ซึ่งเป็นสาเหตุของบั๊กนี้ตั้งแต่แรก
--
-- ผูกกับแผน/ผลตรวจ:
--   - 58K-B3-FIX-UNLINK-AUDIT-RESET-1 audit → decision
--     SAFE_TO_DRAFT_UNLINK_AUDIT_MIGRATION_NEXT
--   - 20260803_case_checklist_documents.sql  (นิยาม B5 เดิมที่ replace ที่นี่)
--   - 20260811_phase2_case_document_owner_links.sql  (รูปแบบ audit ของ link + คอลัมน์ attribution)
--
-- ❗ นโยบายความปลอดภัย (รักษา pattern เดิม 54A-4 / 58K-A ทุกข้อ):
--   - create or replace เท่านั้น: signature + return shape เดิมเป๊ะ → ไม่มี overload ใหม่
--   - SECURITY DEFINER + set search_path = public + identity predicate เดิม
--   - delete predicate เดิม: where l.id = p_link_id (authorization เดิมทุกประการ)
--   - ❌ ไม่ลบแถว public.documents / ไม่แตะ Storage — เอกสารจริงอยู่ครบ (document_kept=true)
--   - Metadata-only: ❌ audit detail ไม่มี storage_path / storage_bucket / file_data /
--     base64 / signed URL — มีเฉพาะ id + attribution + flag
--   - Additive + Idempotent: create or replace (return type เดิม → ไม่ต้อง drop) — รันซ้ำได้
--
-- ❗ ไม่แตะ: app_link_case_document / app_list_case_checklist / case_documents schema /
--   Storage / Edge Function / RLS / login / LINE / attendance / Meta / import-export /
--   delete safety / payments / Name List / checklist status / frontend
--
-- ⚠️ DO NOT APPLY ที่นี่ — ร่างเพื่อรีวิว → apply บน staging ก่อนเสมอ หลัง backup + อนุมัติ
-- =============================================================

-- =============================================================
-- app_unlink_case_document — ลบเฉพาะแถวลิงก์ + audit เสมอ (replace นิยาม 20260803 B5)
--   * RETURNING เก็บ attribution (58K-A) ก่อนแถวหาย — atomic, ไม่มี TOCTOU
--   * audit insert = คอลัมน์/รูปแบบเดียวกับ link audit (20260811) แต่ ❗ ไม่ swallow error
-- =============================================================
create or replace function public.app_unlink_case_document(
  p_user_id  text,
  p_username text,
  p_link_id  bigint
)
returns table (link_id bigint, ok boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_link      record;
begin
  -- ── ตัวตน: staff/admin active (predicate เดียวกับ 54A-4 / 58K-A) ──
  select u.role, u.full_name into v_role, v_full_name
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if v_role is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── ลบเฉพาะแถวลิงก์เป้าหมาย + เก็บ attribution ก่อนแถวหาย (RETURNING → atomic) ──
  --    predicate เดิมทุกประการ: where l.id = p_link_id
  delete from public.case_documents l
  where l.id = p_link_id
  returning l.id, l.case_id, l.case_checklist_item_id, l.document_id,
            l.linked_owner_type, l.linked_owner_id, l.linked_case_worker_id
  into v_link;

  if v_link.id is null then
    raise exception 'link_not_found' using errcode = 'P0002';
  end if;

  -- ── audit log ฝั่ง server — ❗ ไม่ swallow: audit fail = transaction fail ──
  --    (กันเคส "ลบสำเร็จแต่ไม่มี audit" ซึ่งเป็นบั๊กที่ fix นี้แก้)
  --    detail = id + attribution เท่านั้น — ❌ ไม่มี storage_path/bucket/file_data/URL/base64
  insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
  values (p_username,
          coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
          v_role, 'case.document.unlink', 'case_document', v_link.id::text,
          jsonb_build_object('case_id', v_link.case_id,
                             'case_checklist_item_id', v_link.case_checklist_item_id,
                             'document_id', v_link.document_id,
                             'linked_owner_type', v_link.linked_owner_type,
                             'linked_owner_id', v_link.linked_owner_id,
                             'linked_case_worker_id', v_link.linked_case_worker_id,
                             'document_kept', true,
                             'internal_only', true));

  return query select p_link_id, true;
end;
$$;

revoke all on function public.app_unlink_case_document(text, text, bigint) from public;
grant execute on function public.app_unlink_case_document(text, text, bigint) to anon, authenticated;

-- =============================================================
-- VERIFICATION QUERIES  [รันบน staging หลัง apply — comment ล้วน ห้ามรันอัตโนมัติ]
-- =============================================================
-- V.1 signature ใหม่ถูกต้อง + มี overload เดียว (กันกำกวม PostgREST):
--   select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.proname='app_unlink_case_document';
--     -- ต้องได้ "แถวเดียว": args = 'text, text, bigint', prosecdef = true
--
-- V.2 body ใหม่มี audit block + RETURNING 7 คอลัมน์ + ไม่มี swallow:
--   select pg_get_functiondef(p.oid)
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.proname='app_unlink_case_document';
--     -- ต้องเห็น 'case.document.unlink', linked_case_worker_id ใน RETURNING,
--     --   และ ❌ ไม่มี 'exception when others then null' ในบล็อก audit
--
-- V.3 สิทธิ์ execute ครบ anon/authenticated:
--   select r.rolname, has_function_privilege(r.rolname,
--            'public.app_unlink_case_document(text,text,bigint)', 'EXECUTE')
--   from (values ('anon'),('authenticated')) r(rolname);
--
-- V.4 SMOKE TEST (staging เท่านั้น — ใช้ id จริง):
--   -- 1) ลิงก์เอกสาร seed 1 ครั้ง (app_link_case_document) → ได้ <link_id>
--   -- 2) unlink: select * from public.app_unlink_case_document('<uid>','<uname>',<link_id>);
--   --      → คืน (link_id, true); case_documents แถวนั้นหาย; documents ยังครบ
--   -- 3) audit: select action, detail from public.audit_logs
--   --      where action='case.document.unlink' order by created_at desc limit 3;
--   --      → detail มี case_id / case_checklist_item_id / document_id /
--   --        linked_owner_type / linked_owner_id / linked_case_worker_id /
--   --        document_kept=true / internal_only=true
--   --      → ❌ ต้องไม่มี key: storage_path, storage_bucket, file_data, url, base64
--   -- 4) unlink ซ้ำด้วย <link_id> เดิม → raise link_not_found (แถวถูกลบแล้ว)
--
-- =============================================================
-- ROLLBACK (staging เท่านั้น) — re-apply นิยาม B5 เดิมจาก
--   20260803_case_checklist_documents.sql (บรรทัด B5) เพื่อคืน audit แบบ best-effort เดิม:
--   create or replace function public.app_unlink_case_document(text, text, bigint) ...
--     (คัดนิยามเดิมจาก 20260803 มาวางทับ — return shape เดิม ไม่มี schema change ให้ถอน)
-- =============================================================
-- END STAGE 58K-B3-FIX-UNLINK-AUDIT — additive, idempotent, RPC-only. DO NOT APPLY here — staging first.
-- =============================================================
