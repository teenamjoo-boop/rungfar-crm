-- =============================================================
-- STAGE 52A-13 — Controlled Delete on Delete-Request Approval
-- เป้าหมาย:
--   * เดิม (46A-4): app_review_delete_request อนุมัติ = เปลี่ยนสถานะคำขอเท่านั้น
--     (safe mode) — ข้อมูลจริงไม่ถูกลบ
--   * สเตจนี้เปิด "controlled delete": การลบจริงเกิดได้ทางเดียวคือ
--     admin อนุมัติคำขอลบ ผ่าน RPC SECURITY DEFINER นี้เท่านั้น
--     (browser ยังลบตรงไม่ได้ — DELETE ถูก revoke ครบทุกตารางแล้ว)
--
-- plain-language:
--   controlled delete = ลบผ่านประตู server เท่านั้น หลัง admin อนุมัติ
--   soft delete = ไม่ลบแถวจริง แค่ประทับ deleted_at → ซ่อนจากหน้าจอ แต่หลักฐานยังอยู่
--   hard delete = ลบแถวออกจากฐานข้อมูลจริง
--
-- กลยุทธ์ต่อชนิดข้อมูล (เลือกทางที่ปลอดภัยที่สุด):
--   * customer_delete / customer_bulk_delete → SOFT DELETE:
--       ประทับ customers.deleted_at + deleted_by_code (คอลัมน์ใหม่ additive)
--       เหตุผล: ลูกค้ามีข้อมูลลูก (เอกสาร/ไทม์ไลน์/ประวัติติดต่อ) — hard delete
--       เสี่ยง orphan/หลักฐานหาย; soft delete ย้อนกลับได้ด้วย SQL admin
--   * document_delete → HARD DELETE แถวเดียวตาม id:
--       documents เป็นตารางปลายทาง (leaf) ไม่มีแถวอื่นอ้างถึง — ลบแถว metadata
--       ปลอดภัย ไม่ cascade; ไฟล์จริงใน Storage ไม่ถูกแตะ (ลบมือผ่าน Dashboard ถ้าต้องการ)
--   * groups → คงพฤติกรรมเดิม: app_delete_group (admin เท่านั้น) — ไม่อยู่ใน flow คำขอลบ
--   * employers → ไม่มีการลบ (ไม่มี UI/RPC ลบ — by design)
--
-- กติกาใหม่ใน RPC:
--   1) ตรวจ admin ผ่าน app_users (เหมือนเดิม)
--   2) คำขอต้อง "มีจริง" และ "ยังเป็น pending" เท่านั้น (เดิม review ซ้ำได้ — ปิดแล้ว)
--   3) approve → ทำ entity action ข้างบน + ประทับ reviewed_by/reviewed_at
--   4) reject  → เปลี่ยนสถานะอย่างเดียว ไม่แตะข้อมูล
--   5) เขียน audit log ฝั่ง server (delete_request.approve / .reject) — best-effort
--   6) คืนแถวคำขอเดิม (ไม่มี file/path/base64)
--
-- ไม่แตะ: RLS policy เดิม, grants เดิม (DELETE ยังถูก revoke จาก client),
--         Storage, Edge Functions, LINE, Attendance, Meta Ads, login/security logs
-- ⚠️ Additive + idempotent: add column if not exists + create or replace function
-- =============================================================

-- ── 1) คอลัมน์ soft delete ของ customers (additive — ไม่กระทบข้อมูล/สคีมาเดิม) ──
do $$
begin
  if to_regclass('public.customers') is not null then
    alter table public.customers add column if not exists deleted_at timestamptz;
    alter table public.customers add column if not exists deleted_by_code text;
    raise notice 'controlled-delete: customers.deleted_at / deleted_by_code ready';
  end if;
end$$;
-- หมายเหตุ: app_save_customer / bulk RPC มี deny-list 'deleted_at' อยู่แล้ว →
--   client ตั้ง/ล้างค่านี้เองไม่ได้; กู้คืน (undelete) ทำได้โดย admin ผ่าน SQL เท่านั้น:
--   (ตัวอย่าง — DO NOT RUN BLINDLY): update customers set deleted_at=null, deleted_by_code=null where id=...;

-- ── 2) app_review_delete_request เวอร์ชัน controlled delete ──
create or replace function public.app_review_delete_request(
  p_user_id     text,
  p_username    text,
  p_request_id  bigint,
  p_status      text,
  p_review_note text default null
)
returns table (
  id                bigint,
  created_at        timestamptz,
  requested_by_code text,
  requested_by_name text,
  requested_by_role text,
  request_type      text,
  entity_type       text,
  entity_id         text,
  entity_name       text,
  detail            jsonb,
  reason            text,
  status            text,
  reviewed_by_code  text,
  reviewed_by_name  text,
  reviewed_at       timestamptz,
  review_note       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_role      text;
  v_note      text := nullif(btrim(coalesce(p_review_note, '')), '');
  v_req       public.delete_requests%rowtype;
  v_eid       bigint;
  v_ids       bigint[];
  v_affected  integer := 0;
begin
  -- ── ตัวตน + admin only (เหมือนเวอร์ชัน 20260711) ──
  select u.full_name, u.role
    into v_full_name, v_role
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;
  if v_role is null or v_role <> 'admin' then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_status not in ('approved','rejected') then
    raise exception 'invalid_review_status' using errcode = 'P0003';
  end if;
  if v_note is not null and char_length(v_note) > 1000 then
    v_note := left(v_note, 1000);
  end if;

  -- ── คำขอต้องมีจริง และยังเป็น pending เท่านั้น (กัน review ซ้ำ/ลบซ้ำ) ──
  select * into v_req from public.delete_requests d where d.id = p_request_id limit 1;
  if v_req.id is null then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0002';
  end if;

  -- ── approve → controlled entity action (ทำก่อนอัปเดตสถานะ — อยู่ใน transaction เดียวกัน) ──
  if p_status = 'approved' then

    if v_req.request_type = 'customer_delete' then
      begin
        v_eid := nullif(btrim(coalesce(v_req.entity_id, '')), '')::bigint;
      exception when others then v_eid := null;
      end;
      if v_eid is null then
        raise exception 'invalid_entity_id' using errcode = 'P0003';
      end if;
      -- SOFT DELETE: ประทับเวลา + ผู้อนุมัติ — ❌ ไม่ลบแถว/ไม่แตะเอกสารลูก
      update public.customers c
      set deleted_at = now(), deleted_by_code = p_username
      where c.id = v_eid and c.deleted_at is null;
      get diagnostics v_affected = row_count;

    elsif v_req.request_type = 'customer_bulk_delete' then
      begin
        select array_agg(t.x::bigint) into v_ids
        from jsonb_array_elements_text(coalesce(v_req.detail -> 'ids', '[]'::jsonb)) t(x);
      exception when others then v_ids := null;
      end;
      if v_ids is null or coalesce(array_length(v_ids, 1), 0) = 0 then
        raise exception 'invalid_entity_id' using errcode = 'P0003';
      end if;
      update public.customers c
      set deleted_at = now(), deleted_by_code = p_username
      where c.id = any(v_ids) and c.deleted_at is null;
      get diagnostics v_affected = row_count;

    elsif v_req.request_type = 'document_delete' then
      begin
        v_eid := nullif(btrim(coalesce(v_req.entity_id, '')), '')::bigint;
      exception when others then v_eid := null;
      end;
      if v_eid is null then
        raise exception 'invalid_entity_id' using errcode = 'P0003';
      end if;
      -- HARD DELETE แถวเดียว (documents เป็น leaf table — ไม่มี cascade):
      --   ไฟล์จริงใน Storage ไม่ถูกแตะ; ประวัติยังอยู่ใน delete_requests + audit_logs
      delete from public.documents dd where dd.id = v_eid;
      get diagnostics v_affected = row_count;

    end if;
  end if;

  -- ── audit log ฝั่ง server (best-effort — พังไม่ทำให้ review ล้ม) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (
      p_username,
      coalesce(nullif(btrim(coalesce(v_full_name, '')), ''), p_username),
      v_role,
      case when p_status = 'approved' then 'delete_request.approve' else 'delete_request.reject' end,
      v_req.entity_type,
      v_req.entity_id,
      jsonb_build_object(
        'request_id', v_req.id, 'request_type', v_req.request_type,
        'entity_name', v_req.entity_name, 'affected', v_affected, 'controlled', true
      )
    );
  exception when others then null;
  end;

  -- ── อัปเดตสถานะคำขอ + ประทับผู้ตรวจ แล้วคืนแถว (เหมือนสัญญาเดิมทุกคอลัมน์) ──
  return query
  update public.delete_requests d
  set
    status           = p_status,
    reviewed_by_code = p_username,
    reviewed_by_name = coalesce(nullif(btrim(coalesce(v_full_name,'')), ''), p_username),
    reviewed_at      = now(),
    review_note      = v_note
  where d.id = p_request_id
  returning
    d.id, d.created_at, d.requested_by_code, d.requested_by_name, d.requested_by_role,
    d.request_type, d.entity_type, d.entity_id, d.entity_name, d.detail, d.reason,
    d.status, d.reviewed_by_code, d.reviewed_by_name, d.reviewed_at, d.review_note;
end;
$$;

-- ── 3) สิทธิ์เรียกใช้ (เหมือนเดิม — ฟังก์ชันบังคับตรวจ admin ภายในเสมอ) ──
revoke all on function public.app_review_delete_request(text, text, bigint, text, text) from public;
grant execute on function public.app_review_delete_request(text, text, bigint, text, text) to anon, authenticated;
