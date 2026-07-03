-- =============================================================
-- STAGE 54A-6A — Case Payments Foundation (Phase 2, additive)
-- เป้าหมาย:
--   * ติดตามรายการชำระเงินภายในของเคส (public.case_payments)
--   * ผูกหลักฐานการชำระเงินกับเอกสารที่มีอยู่แล้วใน public.documents เท่านั้น
--     (ใช้ document_id ที่ผ่านการตรวจสอบความเป็นเจ้าของ — ไม่มีการอัปโหลดใหม่ที่นี่)
--
--   ❗ นี่คือ "การติดตามภายในบริษัท" เท่านั้น — ไม่ใช่ใบเสร็จราชการ
--     ไม่ออกใบเสร็จทางการ ไม่สร้าง/ปลอมเอกสารราชการ ไม่ automate เว็บราชการ
--   ❗ ไม่มี hard delete ของประวัติการชำระเงิน — ยกเลิก = เปลี่ยนสถานะ cancelled เท่านั้น
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE inbox/customer-doc-upload/
--     customer-doc-sign/delete approval/Meta/import-export/case checklist (54A-4)/
--     employer establishments (54A-5)
--   ❗ เขียนทุกอย่างผ่าน RPC เท่านั้น — ❌ ไม่ grant สิทธิ์ตรงบนตารางใหม่
--   ❗ RPC ไม่คืน file_data / base64 / storage_path / storage_bucket / signed URL ใด ๆ
--
-- ⚠️ Idempotent — รันซ้ำได้ทั้งไฟล์
-- =============================================================

-- =============================================================
-- A) ตารางรายการชำระเงินของเคส
-- =============================================================
create table if not exists public.case_payments (
  id                 bigserial primary key,
  case_id            bigint not null references public.cases(id) on delete cascade,
  payment_code       text null,
  payment_type       text not null,
  payment_title      text null,
  amount_due         numeric(12,2) not null default 0,
  amount_paid        numeric(12,2) not null default 0,
  payment_status     text not null default 'unpaid',
  due_date           date null,
  paid_at            timestamptz null,
  proof_document_id  bigint null references public.documents(id) on delete set null,
  note               text null,
  is_active          boolean not null default true,
  created_by_code    text null,
  updated_by_code    text null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint case_payments_type_check check (
    payment_type in ('service_fee','deposit','final_payment','government_fee',
                     'document_fee','transport_fee','other')
  ),
  constraint case_payments_status_check check (
    payment_status in ('unpaid','partial','paid','overdue','waived','refunded','cancelled')
  )
);

comment on table public.case_payments is
  'STAGE 54A-6A: การชำระเงินภายในของเคส (Phase 2) — ติดตามภายในบริษัทเท่านั้น ไม่ใช่ใบเสร็จราชการ. เขียนผ่าน RPC เท่านั้น (app_save_case_payment / app_set_case_payment_status) — ห้าม grant เขียนตรงให้ anon/authenticated. ไม่มี hard delete — ยกเลิก = เปลี่ยนสถานะ cancelled';

create index if not exists idx_case_payments_case
  on public.case_payments (case_id);
create index if not exists idx_case_payments_status
  on public.case_payments (payment_status);
create index if not exists idx_case_payments_due
  on public.case_payments (due_date);
create index if not exists idx_case_payments_proof_doc
  on public.case_payments (proof_document_id);
create index if not exists idx_case_payments_created
  on public.case_payments (created_at desc);

-- =============================================================
-- ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2/3/4/5)
-- =============================================================
revoke all on table public.case_payments from public, anon, authenticated;
revoke all on sequence public.case_payments_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_case_payments — staff/admin อ่านรายการชำระเงินของเคส
--     รวม metadata ของเอกสารหลักฐาน (ถ้ามี) — ❌ ไม่มี storage_path/file_data/base64/signed URL
-- =============================================================
create or replace function public.app_list_case_payments(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  id                  bigint,
  case_id             bigint,
  payment_code        text,
  payment_type        text,
  payment_title       text,
  amount_due          numeric,
  amount_paid         numeric,
  payment_status      text,
  due_date            date,
  paid_at             timestamptz,
  note                text,
  is_active           boolean,
  created_by_code     text,
  updated_by_code     text,
  created_at          timestamptz,
  updated_at          timestamptz,
  proof_document_id   bigint,
  proof_doc_type      text,
  proof_doc_name      text,
  proof_file_type     text,
  proof_mime_type     text,
  proof_has_storage   boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  return query
  select
    p.id, p.case_id, p.payment_code, p.payment_type, p.payment_title,
    p.amount_due, p.amount_paid, p.payment_status, p.due_date, p.paid_at,
    p.note, p.is_active, p.created_by_code, p.updated_by_code, p.created_at, p.updated_at,
    p.proof_document_id, d.doc_type, d.doc_name, d.file_type, d.mime_type,
    (d.storage_path is not null) as proof_has_storage
  from public.case_payments p
  left join public.documents d on d.id = p.proof_document_id
  where p.case_id = p_case_id
  order by p.due_date nulls last, p.created_at desc;
end;
$$;

revoke all on function public.app_list_case_payments(text, text, bigint) from public;
grant execute on function public.app_list_case_payments(text, text, bigint) to anon, authenticated;

-- =============================================================
-- B2) app_save_case_payment — staff/admin สร้าง/แก้ไขรายการชำระเงิน
--     * proof_document_id (ถ้าส่งมา) ต้องผ่านการตรวจสอบความเป็นเจ้าของก่อนเสมอ:
--       A) เอกสารถูกลิงก์ไว้กับเคสนี้แล้วผ่าน case_documents (54A-4) หรือ
--       B) เอกสารเป็นของลูกค้าเจ้าของเคส (documents.customer_id หรือ
--          owner_type='customer'/owner_id ตรงกับ customer ของเคส — เหมือน 54A-4) หรือ
--       C) owner_type='case' and owner_id = case นี้เอง
--     * status normalization แบบง่าย กำหนดชัดเจน (ไม่ auto ทับ waived/refunded/cancelled ที่ผู้ใช้ตั้งเอง)
--
--     ⚠️ ข้อแตกต่างจาก spec เดิมโดยตั้งใจ: p_amount_due / p_amount_paid / p_payment_status
--     ใช้ default null แทน 0/'unpaid' — เพราะถ้า default เป็นค่าคงที่ เวลา frontend เรียก
--     update แค่บาง field (เช่น ผูกหลักฐานอย่างเดียว) แล้วไม่ส่ง amount มา PostgREST จะเติม
--     default ให้อัตโนมัติ → ทับยอดเงินเดิมเป็น 0 โดยไม่ตั้งใจ (data loss bug)
--     ที่นี่ null = "คงค่าเดิม" ตอน update, และ "ใช้ 0/normalize" ตอน create — ปลอดภัยกว่า
--     และยังคง deterministic ตามที่ระบุไว้
-- =============================================================
create or replace function public.app_save_case_payment(
  p_user_id            text,
  p_username           text,
  p_payment_id         bigint default null,   -- null = สร้างใหม่
  p_case_id            bigint default null,   -- จำเป็นตอนสร้าง
  p_payment_type       text default null,
  p_payment_title      text default null,
  p_amount_due         numeric default null,  -- null = คงเดิม (update) / 0 (create)
  p_amount_paid        numeric default null,  -- null = คงเดิม (update) / 0 (create)
  p_payment_status     text default null,     -- null = normalize อัตโนมัติจากยอด
  p_due_date           date default null,
  p_paid_at            timestamptz default null,
  p_proof_document_id  bigint default null,   -- null = คงเดิม (update) / ไม่ผูก (create)
  p_note               text default null
)
returns table (id bigint, case_id bigint, payment_status text, amount_due numeric, amount_paid numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_type      text := lower(btrim(coalesce(p_payment_type, '')));
  v_status_in text := lower(btrim(coalesce(p_payment_status, '')));
  v_status    text;
  v_case      record;
  v_old       record;
  v_due       numeric;
  v_paid      numeric;
  v_proof     bigint;
  v_id        bigint;
  v_case_id   bigint;
  v_action    text;
begin
  -- ── ตัวตน: staff/admin active ──
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

  if v_status_in <> '' and v_status_in not in ('unpaid','partial','paid','overdue',
                                               'waived','refunded','cancelled') then
    raise exception 'invalid_payment_status' using errcode = 'P0003';
  end if;

  if p_payment_id is null then
    -- ── CREATE: ต้องมีเคสจริง + ประเภทถูกต้อง ──
    if p_case_id is null then
      raise exception 'case_id_required' using errcode = 'P0003';
    end if;
    if v_type = '' or v_type not in ('service_fee','deposit','final_payment','government_fee',
                                     'document_fee','transport_fee','other') then
      raise exception 'invalid_payment_type' using errcode = 'P0003';
    end if;
    select cs.id, cs.customer_id into v_case
    from public.cases cs where cs.id = p_case_id;
    if v_case.id is null then
      raise exception 'case_not_found' using errcode = 'P0002';
    end if;
    v_case_id := v_case.id;
    v_due  := coalesce(p_amount_due, 0);
    v_paid := coalesce(p_amount_paid, 0);
  else
    -- ── UPDATE: ดึงแถวเดิม + เคสของแถวเดิม (❗ ไม่รับ p_case_id — ห้ามย้ายเคสของรายการเดิม) ──
    select p.case_id, p.payment_type, p.amount_due, p.amount_paid, p.proof_document_id, p.paid_at
      into v_old
    from public.case_payments p
    where p.id = p_payment_id;
    if v_old.case_id is null then
      raise exception 'payment_not_found' using errcode = 'P0002';
    end if;
    v_case_id := v_old.case_id;

    select cs.id, cs.customer_id into v_case
    from public.cases cs where cs.id = v_case_id;

    if v_type = '' then v_type := v_old.payment_type; end if;
    if v_type not in ('service_fee','deposit','final_payment','government_fee',
                      'document_fee','transport_fee','other') then
      raise exception 'invalid_payment_type' using errcode = 'P0003';
    end if;
    v_due  := coalesce(p_amount_due, v_old.amount_due);
    v_paid := coalesce(p_amount_paid, v_old.amount_paid);
  end if;

  if v_due < 0 or v_paid < 0 then
    raise exception 'invalid_amount' using errcode = 'P0003';
  end if;

  -- ── ตรวจสอบเอกสารหลักฐาน — ส่งมาใหม่ต้องผ่านตรวจสอบเสมอ; ไม่ส่ง = คงค่าเดิม (update) / ไม่ผูก (create) ──
  if p_proof_document_id is not null then
    select d.id into v_proof
    from public.documents d
    where d.id = p_proof_document_id
      and (
        exists (select 1 from public.case_documents cd
                where cd.case_id = v_case_id and cd.document_id = d.id)
        or d.customer_id = v_case.customer_id
        or (d.owner_type = 'customer' and d.owner_id = v_case.customer_id)
        or (d.owner_type = 'case'     and d.owner_id = v_case_id)
      );
    if v_proof is null then
      raise exception 'document_not_allowed' using errcode = 'P0003';
    end if;
  elsif p_payment_id is not null then
    v_proof := v_old.proof_document_id;
  else
    v_proof := null;
  end if;

  -- ── status normalization แบบง่าย: ไม่ทับสถานะที่ผู้ใช้ตั้งเป็น waived/refunded/cancelled เอง ──
  if v_status_in = '' then
    if v_due > 0 and v_paid >= v_due then
      v_status := 'paid';
    elsif v_paid > 0 and v_paid < v_due then
      v_status := 'partial';
    else
      v_status := 'unpaid';
    end if;
  else
    v_status := v_status_in;
  end if;

  if p_payment_id is null then
    insert into public.case_payments
      (case_id, payment_type, payment_title, amount_due, amount_paid, payment_status,
       due_date, paid_at, proof_document_id, note, created_by_code, updated_by_code)
    values
      (v_case_id, v_type, nullif(btrim(coalesce(p_payment_title,'')),''), v_due, v_paid, v_status,
       p_due_date,
       case when v_status = 'paid' then coalesce(p_paid_at, now()) else p_paid_at end,
       v_proof, nullif(btrim(coalesce(p_note,'')),''), p_username, p_username)
    returning case_payments.id into v_id;
    v_action := 'case.payment.create';
  else
    update public.case_payments p
    set payment_type   = v_type,
        payment_title  = case when p_payment_title is null then p.payment_title else nullif(btrim(p_payment_title),'') end,
        amount_due     = v_due,
        amount_paid    = v_paid,
        payment_status = v_status,
        due_date       = case when p_due_date is null then p.due_date else p_due_date end,
        paid_at        = case when v_status = 'paid' and v_old.paid_at is null then coalesce(p_paid_at, now())
                              else coalesce(p_paid_at, v_old.paid_at) end,
        proof_document_id = v_proof,
        note           = case when p_note is null then p.note else nullif(btrim(p_note),'') end,
        updated_by_code = p_username,
        updated_at     = now()
    where p.id = p_payment_id
    returning p.id into v_id;
    -- ผูก/เปลี่ยนหลักฐานใหม่ในรอบนี้ → action เฉพาะ case.payment.proof_link (ตรวจย้อนหลังง่าย)
    v_action := case when p_proof_document_id is not null
                     then 'case.payment.proof_link' else 'case.payment.update' end;
  end if;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_payment', v_id::text,
            jsonb_build_object('case_id', v_case_id, 'status', v_status,
                               'proof_document_id', v_proof, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select p.id, p.case_id, p.payment_status, p.amount_due, p.amount_paid
  from public.case_payments p where p.id = v_id;
end;
$$;

revoke all on function public.app_save_case_payment(
  text, text, bigint, bigint, text, text, numeric, numeric, text, date, timestamptz, bigint, text
) from public;
grant execute on function public.app_save_case_payment(
  text, text, bigint, bigint, text, text, numeric, numeric, text, date, timestamptz, bigint, text
) to anon, authenticated;

-- =============================================================
-- B3) app_set_case_payment_status — staff/admin เปลี่ยนสถานะเท่านั้น (soft — ไม่ล้าง paid_at ทิ้ง)
-- =============================================================
create or replace function public.app_set_case_payment_status(
  p_user_id        text,
  p_username       text,
  p_payment_id     bigint,
  p_payment_status text,
  p_note           text default null
)
returns table (id bigint, payment_status text, paid_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_status    text := lower(btrim(coalesce(p_payment_status, '')));
  v_id        bigint;
  v_case_id   bigint;
  v_action    text;
begin
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

  if v_status not in ('unpaid','partial','paid','overdue','waived','refunded','cancelled') then
    raise exception 'invalid_payment_status' using errcode = 'P0003';
  end if;

  update public.case_payments p
  set payment_status = v_status,
      paid_at         = case when v_status = 'paid' and p.paid_at is null then now() else p.paid_at end,
      note            = case when p_note is null then p.note else nullif(btrim(p_note),'') end,
      updated_by_code = p_username,
      updated_at      = now()
  where p.id = p_payment_id
  returning p.id, p.case_id into v_id, v_case_id;

  if v_id is null then
    raise exception 'payment_not_found' using errcode = 'P0002';
  end if;

  v_action := case when v_status = 'cancelled' then 'case.payment.cancel' else 'case.payment.status' end;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, v_action, 'case_payment', v_id::text,
            jsonb_build_object('case_id', v_case_id, 'status', v_status, 'internal_only', true));
  exception when others then null;
  end;

  return query
  select p.id, p.payment_status, p.paid_at
  from public.case_payments p where p.id = v_id;
end;
$$;

revoke all on function public.app_set_case_payment_status(text, text, bigint, text, text) from public;
grant execute on function public.app_set_case_payment_status(text, text, bigint, text, text) to anon, authenticated;

-- =============================================================
-- B4) app_case_payment_summary — สรุปยอด/นับสถานะของเคส (สำหรับ card ใน case detail)
--     overdue = รายการที่ยัง active, due_date < วันนี้, และสถานะยังไม่จบ (ไม่ใช่ paid/waived/refunded/cancelled)
-- =============================================================
create or replace function public.app_case_payment_summary(
  p_user_id  text,
  p_username text,
  p_case_id  bigint
)
returns table (
  total_due       numeric,
  total_paid      numeric,
  balance_due     numeric,
  unpaid_count    bigint,
  partial_count   bigint,
  paid_count      bigint,
  overdue_count   bigint,
  cancelled_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
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

  return query
  select
    coalesce(sum(p.amount_due) filter (where p.payment_status <> 'cancelled'), 0)  as total_due,
    coalesce(sum(p.amount_paid) filter (where p.payment_status <> 'cancelled'), 0) as total_paid,
    coalesce(sum(p.amount_due - p.amount_paid) filter (
      where p.payment_status not in ('paid','waived','refunded','cancelled')), 0)  as balance_due,
    count(*) filter (where p.payment_status = 'unpaid')                            as unpaid_count,
    count(*) filter (where p.payment_status = 'partial')                           as partial_count,
    count(*) filter (where p.payment_status = 'paid')                              as paid_count,
    count(*) filter (where p.due_date is not null and p.due_date < current_date
                     and p.payment_status not in ('paid','waived','refunded','cancelled')) as overdue_count,
    count(*) filter (where p.payment_status = 'cancelled')                         as cancelled_count
  from public.case_payments p
  where p.case_id = p_case_id;
end;
$$;

revoke all on function public.app_case_payment_summary(text, text, bigint) from public;
grant execute on function public.app_case_payment_summary(text, text, bigint) to anon, authenticated;
