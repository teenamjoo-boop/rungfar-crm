-- =============================================================
-- STAGE 54A-7B — eWorkPermit / Government Tracking Logs (Phase 2, additive)
-- เป้าหมาย:
--   * บันทึก "ประวัติติดตาม e-WorkPermit / ราชการ" ต่อเคสแบบ manual
--     (public.case_tracking_logs — append-only)
--   * พนักงานตรวจเว็บราชการ "ด้วยตัวเอง" แล้วมาจดใน CRM:
--     วันเวลาที่ตรวจ, ข้อความสถานะที่พบ, หมายเหตุ, วันติดตามครั้งถัดไป,
--     และเอกสารหลักฐานที่มีอยู่แล้วในคลัง (document id เท่านั้น)
--
--   ❗ นโยบายความปลอดภัย (สำคัญ):
--     - ระบบ "ไม่เชื่อมต่อ/ไม่ automate/ไม่ scrape" เว็บ eworkpermit.doe.go.th ใด ๆ
--     - ไม่เก็บรหัสผ่านเว็บราชการ
--     - gov_status_text คือข้อความที่พนักงาน "พิมพ์เอง" จากสิ่งที่เห็น —
--       ไม่ใช่ข้อมูลยืนยันจากราชการ และไม่ใช่เอกสารราชการ
--     - ไม่สร้าง/ไม่ปลอมเอกสารราชการ
--   ❗ append-only: ไม่มี RPC แก้ไข/ลบใน stage นี้ — ประวัติแก้ย้อนหลังไม่ได้
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE inbox/customer-doc-upload/
--     customer-doc-sign/delete approval/Meta/import-export/สถานะเคสเดิม (54A-3)
--   ❗ เขียนทุกอย่างผ่าน RPC เท่านั้น — ❌ ไม่ grant สิทธิ์ตรงบนตารางใหม่
--   ❗ RPC ไม่คืน file_data / base64 / storage_path / storage_bucket / signed URL ใด ๆ
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์ (create if not exists / or replace)
-- =============================================================

-- =============================================================
-- A) ตารางประวัติติดตามของเคส (append-only)
-- =============================================================
create table if not exists public.case_tracking_logs (
  id                   bigserial primary key,
  case_id              bigint not null references public.cases(id) on delete cascade,
  tracking_type        text not null default 'ewp',
  gov_status_text      text null,
  note                 text null,
  evidence_document_id bigint null references public.documents(id) on delete set null,
  next_check_date      date null,
  tracked_at           timestamptz not null default now(),
  created_by_code      text null,
  created_at           timestamptz not null default now(),
  constraint case_tracking_type_check check (
    tracking_type in ('ewp','government_office','phone','onsite','internal')
  )
);

comment on table public.case_tracking_logs is
  'STAGE 54A-7B: ประวัติติดตาม e-WorkPermit/ราชการของเคส (Phase 2) — พนักงานจดเองจากการตรวจ manual เท่านั้น ไม่ใช่ข้อมูลยืนยันจากราชการ ระบบไม่เชื่อมต่อเว็บราชการ. append-only เขียนผ่าน RPC เท่านั้น (app_add_case_tracking_log) — ห้าม grant เขียนตรงให้ anon/authenticated. ไม่มีแก้ไข/ลบ';

create index if not exists idx_case_trk_case
  on public.case_tracking_logs (case_id, tracked_at desc);
create index if not exists idx_case_trk_next_check
  on public.case_tracking_logs (next_check_date);
create index if not exists idx_case_trk_type
  on public.case_tracking_logs (tracking_type);
create index if not exists idx_case_trk_evidence
  on public.case_tracking_logs (evidence_document_id);

-- =============================================================
-- ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2..6)
-- =============================================================
revoke all on table public.case_tracking_logs from public, anon, authenticated;
revoke all on sequence public.case_tracking_logs_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_case_tracking_logs — staff/admin อ่านประวัติติดตามของเคส
--     เอกสารหลักฐาน join เป็น metadata เท่านั้น (doc_* prefix กันชนกับ created_at ของ log)
--     ❌ ไม่มี storage_path / file_data / base64 / signed URL — has_storage เป็น boolean
-- =============================================================
create or replace function public.app_list_case_tracking_logs(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  id                   bigint,
  case_id              bigint,
  tracking_type        text,
  gov_status_text      text,
  note                 text,
  evidence_document_id bigint,
  next_check_date      date,
  tracked_at           timestamptz,
  created_by_code      text,
  created_at           timestamptz,
  doc_type             text,
  doc_name             text,
  doc_file_type        text,
  doc_mime_type        text,
  doc_file_size        bigint,
  doc_uploaded_by      text,
  doc_created_at       timestamptz,
  doc_source           text,
  doc_status           text,
  doc_note             text,
  doc_expiry           date,
  doc_has_storage      boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok   boolean := false;
  v_case bigint;
begin
  select true into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select cs.id into v_case from public.cases cs where cs.id = p_case_id;
  if v_case is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  return query
  select
    t.id, t.case_id, t.tracking_type, t.gov_status_text, t.note,
    t.evidence_document_id, t.next_check_date, t.tracked_at,
    t.created_by_code, t.created_at,
    d.doc_type, d.doc_name, d.file_type, d.mime_type,
    d.file_size::bigint, d.uploaded_by, d.created_at, d.source,
    d.doc_status, d.doc_note, d.doc_expiry,
    (d.storage_path is not null) as doc_has_storage
  from public.case_tracking_logs t
  left join public.documents d on d.id = t.evidence_document_id
  where t.case_id = p_case_id
  order by t.tracked_at desc, t.created_at desc;
end;
$$;

revoke all on function public.app_list_case_tracking_logs(text, text, bigint) from public;
grant execute on function public.app_list_case_tracking_logs(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B2) app_add_case_tracking_log — staff/admin เพิ่มบันทึกติดตาม (append-only)
--     * เอกสารหลักฐาน (ถ้าส่งมา) ต้องผ่านกฎความเป็นเจ้าของเดียวกับ 54A-4/6A:
--       A) ลิงก์กับเคสนี้แล้วผ่าน case_documents หรือ
--       B) เป็นของลูกค้าเจ้าของเคส (customer_id / owner_type='customer') หรือ
--       C) owner_type='case' and owner_id = เคสนี้
--       ผิดจากนี้ → raise document_not_allowed
--     * ไม่มี RPC แก้ไข/ลบ — ประวัติเป็น append-only
-- =============================================================
create or replace function public.app_add_case_tracking_log(
  p_user_id              text,
  p_username             text,
  p_case_id              bigint,
  p_tracking_type        text default 'ewp',
  p_gov_status_text      text default null,
  p_note                 text default null,
  p_evidence_document_id bigint default null,
  p_next_check_date      date default null,
  p_tracked_at           timestamptz default null
)
returns table (
  id                   bigint,
  case_id              bigint,
  tracking_type        text,
  gov_status_text      text,
  note                 text,
  evidence_document_id bigint,
  next_check_date      date,
  tracked_at           timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_type      text := lower(btrim(coalesce(p_tracking_type, 'ewp')));
  v_case      record;
  v_doc       bigint;
  v_id        bigint;
begin
  -- ── ตัวตน: staff/admin active (predicate เดียวกับ 54A-3/4/6) ──
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

  if v_type = '' then v_type := 'ewp'; end if;
  if v_type not in ('ewp','government_office','phone','onsite','internal') then
    raise exception 'invalid_tracking_type' using errcode = 'P0003';
  end if;

  select cs.id, cs.customer_id into v_case
  from public.cases cs where cs.id = p_case_id;
  if v_case.id is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  -- ── ตรวจสอบเอกสารหลักฐาน (ถ้าส่งมา) — กฎเดียวกับ 54A-4/6A ──
  if p_evidence_document_id is not null then
    select d.id into v_doc
    from public.documents d
    where d.id = p_evidence_document_id
      and (
        exists (select 1 from public.case_documents cd
                where cd.case_id = v_case.id and cd.document_id = d.id)
        or d.customer_id = v_case.customer_id
        or (d.owner_type = 'customer' and d.owner_id = v_case.customer_id)
        or (d.owner_type = 'case'     and d.owner_id = v_case.id)
      );
    if v_doc is null then
      raise exception 'document_not_allowed' using errcode = 'P0003';
    end if;
  end if;

  insert into public.case_tracking_logs
    (case_id, tracking_type, gov_status_text, note, evidence_document_id,
     next_check_date, tracked_at, created_by_code)
  values
    (v_case.id, v_type,
     nullif(btrim(coalesce(p_gov_status_text,'')),''),
     nullif(btrim(coalesce(p_note,'')),''),
     v_doc,
     p_next_check_date,
     coalesce(p_tracked_at, now()),
     p_username)
  returning case_tracking_logs.id into v_id;

  -- ── audit log ฝั่ง server (best-effort — pattern 20260728) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.tracking.add', 'case_tracking_log', v_id::text,
            jsonb_build_object('case_id', v_case.id, 'tracking_type', v_type,
                               'evidence_document_id', v_doc, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select t.id, t.case_id, t.tracking_type, t.gov_status_text, t.note,
         t.evidence_document_id, t.next_check_date, t.tracked_at
  from public.case_tracking_logs t where t.id = v_id;
end;
$$;

revoke all on function public.app_add_case_tracking_log(
  text, text, bigint, text, text, text, bigint, date, timestamptz
) from public;
grant execute on function public.app_add_case_tracking_log(
  text, text, bigint, text, text, text, bigint, date, timestamptz
) to anon, authenticated;
