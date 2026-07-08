-- =============================================================
-- STAGE 58H-RESET-2 — Phase 2 Backend Foundation: case_workers / Name List
--   (additive, RPC-only) — first approved backend foundation piece
--
-- เป้าหมาย (scope แคบ — เฉพาะ case_workers / Name List เท่านั้น):
--   * เพิ่มตาราง public.case_workers — รองรับ "หลายแรงงานต่อเคส" (MOU Name List)
--   * RPC อ่าน/เพิ่ม/ปิดใช้งาน (soft) แรงงานในเคส ผ่าน SECURITY DEFINER เท่านั้น
--   * cases.customer_id คงเป็น "แรงงานหลัก/แสดง" (backward compatibility) —
--     เคสเดี่ยวเดิมที่ไม่มีแถว case_workers ยังทำงานได้ (ฝั่งอ่าน fallback ใช้ customer_id)
--
--   ผูกกับสัญญา/แผน:
--     - manual/PHASE2_BACKEND_CONTRACT_58F.md  §D (case_workers / Name List)
--     - manual/DRAFT_PHASE2_BACKEND_SQL_58F_DO_NOT_APPLY.sql  SECTION 2
--     - manual/PHASE2_BACKEND_STAGING_RUNBOOK_58G.md  §5–§7 (apply/verify/rollback)
--
--   ❗ ขอบเขต stage นี้ (ทำเฉพาะ case_workers):
--     - ❌ ไม่เพิ่ม cases.mou_side / cases.establishment_id / template item mou_side
--       (อยู่ในสัญญา §C/§F — เลื่อนไปสเตจถัดไปตามที่เจ้าของอนุมัติแยก)
--     - ❌ ไม่แตะ app_link_case_document / readiness รายแรงงาน (§D.4/§E — สเตจถัดไป)
--     - ❌ ไม่แก้ app_create_case / app_init_case_checklist
--
--   ❗ นโยบายความปลอดภัย (รักษา pattern เดิม 54A-2..7 ทุกข้อ):
--     - RPC-only: revoke all บนตาราง + sequence (public/anon/authenticated)
--     - SECURITY DEFINER + set search_path = public + identity predicate เดิม
--       (staff/admin active) ทุกฟังก์ชัน
--     - No hard delete: ยกเลิกแรงงาน = soft is_active=false (ไม่ลบแถว)
--     - Metadata-only: ❌ ไม่คืน file_data / base64 / storage_path / storage_bucket /
--       signed URL ใด ๆ (RPC นี้ไม่แตะ documents/storage เลย)
--     - Additive + Idempotent: create if not exists / guarded constraint /
--       create or replace — รันซ้ำได้ทั้งไฟล์
--     - Audit best-effort: insert audit_logs ใน begin ... exception when others then null
--
--   ❗ ไม่แตะ: login/session/security logs/attendance/LINE/Meta/import-export/
--     delete approval/customer-doc-upload/Storage/Edge Function/customers/cases เดิม
--
-- ⚠️ DO NOT APPLY ที่นี่ — apply บน staging เท่านั้น หลัง backup + อนุมัติ (ดู runbook 58G)
-- =============================================================

-- =============================================================
-- A) ตาราง case_workers — หลายแรงงานต่อเคส (Name List)
--    * case_id → cases(id) on delete cascade (เคสหายไป → แรงงานในเคสหายตาม)
--    * customer_id: ไม่ FK — customers ใช้ soft delete เหมือน cases.customer_id
--      (ตรวจความมีจริง/ไม่ถูก soft delete ที่ระดับ RPC ตอนเพิ่ม)
--    * role default 'worker' — CHECK ขยายภายหลังได้
--    * name_list_seq: ลำดับใน Name List (null ได้)
--    * is_active: soft active/inactive (❌ ไม่มี hard delete)
-- =============================================================
create table if not exists public.case_workers (
  id              bigserial primary key,
  case_id         bigint not null references public.cases(id) on delete cascade,
  customer_id     bigint not null,
  role            text not null default 'worker',
  name_list_seq   integer null,
  note            text null,
  is_active       boolean not null default true,
  created_by_code text null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz null,
  updated_by_code text null,
  constraint case_workers_role_check check (role in ('worker','dependent','other'))
);

comment on table public.case_workers is
  'STAGE 58H: หลายแรงงานต่อเคส (MOU Name List, Phase 2, additive). cases.customer_id ยังเป็นแรงงานหลัก/แสดง (backward compat) — เคสเดี่ยวเดิมที่ไม่มีแถวยัง fallback ใช้ customer_id ได้. เขียนผ่าน RPC เท่านั้น (app_add_case_worker / app_set_case_worker_active) — ห้าม grant เขียนตรงให้ anon/authenticated. No hard delete: soft is_active=false. customer_id ไม่ FK (customers ใช้ soft delete).';

-- ── ดัชนี ──
create index if not exists idx_case_workers_case
  on public.case_workers (case_id, name_list_seq nulls last);
create index if not exists idx_case_workers_customer
  on public.case_workers (customer_id);

-- ── กันเพิ่มแรงงานคนเดิมซ้ำในเคสเดียว (เฉพาะแถว active) ──
create unique index if not exists uq_case_workers_case_customer_active
  on public.case_workers (case_id, customer_id) where is_active;

-- ── ปิดสิทธิ์ตรงทั้งหมด (RPC-only — pattern เดียวกับ 54A-2..7) ──
revoke all on table public.case_workers from public, anon, authenticated;
revoke all on sequence public.case_workers_id_seq from public, anon, authenticated;

-- =============================================================
-- B1) app_list_case_workers — staff/admin อ่าน Name List ของเคส
--     * join customers เป็น metadata เท่านั้น (name/passport/สถานะ) — ❌ ไม่มี path/file/URL
--     * is_primary = (worker.customer_id = cases.customer_id) → ฝั่ง UI ใช้กันลบแรงงานหลัก
--     * แสดงเฉพาะแถว active ตาม default (p_include_inactive=true เพื่อดูที่ปิดแล้ว)
--     * เคสเดี่ยวเดิม (ไม่มีแถว) → คืน 0 แถว, ฝั่งอ่าน fallback ใช้ cases.customer_id
-- =============================================================
create or replace function public.app_list_case_workers(
  p_user_id           text,
  p_username          text,
  p_case_id           bigint,
  p_include_inactive  boolean default false
)
returns table (
  id               bigint,
  case_id          bigint,
  customer_id      bigint,
  role             text,
  name_list_seq    integer,
  note             text,
  is_active        boolean,
  is_primary       boolean,
  created_by_code  text,
  created_at       timestamptz,
  updated_at       timestamptz,
  worker_name      text,
  nationality      text,
  work_status      text,
  passport_no      text,
  alien_id         text,
  wp_no            text,
  exp_visa         date,
  exp_wp           date,
  worker_deleted   boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok        boolean := false;
  v_case_cust bigint;
  v_case      bigint;
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

  select cs.id, cs.customer_id into v_case, v_case_cust
  from public.cases cs where cs.id = p_case_id;
  if v_case is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  return query
  select
    w.id, w.case_id, w.customer_id, w.role, w.name_list_seq, w.note,
    w.is_active,
    (w.customer_id = v_case_cust) as is_primary,
    w.created_by_code, w.created_at, w.updated_at,
    c.name, c.nationality, c.work_status,
    c.passport_no, c.alien_id, c.wp_no, c.exp_visa, c.exp_wp,
    (c.id is null or c.deleted_at is not null) as worker_deleted
  from public.case_workers w
  left join public.customers c on c.id = w.customer_id
  where w.case_id = p_case_id
    and (coalesce(p_include_inactive, false) = true or w.is_active)
  order by (w.customer_id = v_case_cust) desc,
           w.name_list_seq nulls last, w.id;
end;
$$;

revoke all on function public.app_list_case_workers(text, text, bigint, boolean) from public;
grant execute on function public.app_list_case_workers(text, text, bigint, boolean) to anon, authenticated;

-- =============================================================
-- B2) app_add_case_worker — staff/admin เพิ่มแรงงานเข้า Name List ของเคส
--     * ตรวจ: เคสมีจริง + ลูกค้ามีจริงและไม่ถูก soft delete (predicate เดียวกับ app_create_case)
--     * role validate (worker/dependent/other) — ค่าว่าง = 'worker'
--     * idempotent: ถ้ามีแถว active ของ (case, customer) อยู่แล้ว → คืนแถวเดิม (ไม่เพิ่มซ้ำ)
--       สอดคล้อง unique index uq_case_workers_case_customer_active
--     * สิทธิ์: staff+admin (งาน operational ต่อเคส — เหมือน add payment/appointment/tracking)
-- =============================================================
create or replace function public.app_add_case_worker(
  p_user_id       text,
  p_username      text,
  p_case_id       bigint,
  p_customer_id   bigint,
  p_role          text default 'worker',
  p_name_list_seq integer default null,
  p_note          text default null
)
returns table (
  id            bigint,
  case_id       bigint,
  customer_id   bigint,
  role          text,
  name_list_seq integer,
  is_active     boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_full_name text;
  v_wrole     text := lower(btrim(coalesce(p_role, 'worker')));
  v_case      bigint;
  v_cust      bigint;
  v_id        bigint;
begin
  -- ── ตัวตน: staff/admin active (predicate เดียวกับ 54A-3/4/6/7) ──
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

  if v_wrole = '' then v_wrole := 'worker'; end if;
  if v_wrole not in ('worker','dependent','other') then
    raise exception 'invalid_worker_role' using errcode = 'P0003';
  end if;

  -- ── เคสต้องมีจริง ──
  select cs.id into v_case from public.cases cs where cs.id = p_case_id;
  if v_case is null then
    raise exception 'case_not_found' using errcode = 'P0002';
  end if;

  -- ── ลูกค้าต้องมีจริงและไม่ถูก soft delete (เดียวกับ app_create_case) ──
  if p_customer_id is null then
    raise exception 'invalid_arguments' using errcode = 'P0003';
  end if;
  select c.id into v_cust
  from public.customers c
  where c.id = p_customer_id and c.deleted_at is null;
  if v_cust is null then
    raise exception 'customer_not_found' using errcode = 'P0002';
  end if;

  -- ── idempotent: ถ้ามีแถว active อยู่แล้ว → คืนแถวเดิม (ไม่เพิ่มซ้ำ) ──
  select w.id into v_id
  from public.case_workers w
  where w.case_id = v_case and w.customer_id = v_cust and w.is_active
  limit 1;

  if v_id is null then
    insert into public.case_workers
      (case_id, customer_id, role, name_list_seq, note, created_by_code)
    values
      (v_case, v_cust, v_wrole, p_name_list_seq,
       nullif(btrim(coalesce(p_note,'')),''),
       p_username)
    returning case_workers.id into v_id;

    -- ── audit log ฝั่ง server (best-effort — pattern 20260728) ──
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (p_username,
              coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
              v_role, 'case.worker.add', 'case_worker', v_id::text,
              jsonb_build_object('case_id', v_case, 'customer_id', v_cust,
                                 'role', v_wrole, 'internal_only', true));
    exception when others then null;
    end;
  end if;

  return query
  select w.id, w.case_id, w.customer_id, w.role, w.name_list_seq, w.is_active
  from public.case_workers w where w.id = v_id;
end;
$$;

revoke all on function public.app_add_case_worker(
  text, text, bigint, bigint, text, integer, text
) from public;
grant execute on function public.app_add_case_worker(
  text, text, bigint, bigint, text, integer, text
) to anon, authenticated;

-- =============================================================
-- B3) app_set_case_worker_active — staff/admin เปิด/ปิด (soft) แรงงานใน Name List
--     * No hard delete — เปลี่ยน is_active เท่านั้น
--     * ❗ ห้ามปิดแรงงานหลัก (customer_id = cases.customer_id) — กันเคสไม่มีแรงงานแสดง
--       (raise cannot_deactivate_primary_worker)
--     * สิทธิ์: staff+admin (operational ต่อเคส — สอดคล้อง app_add_case_worker)
-- =============================================================
create or replace function public.app_set_case_worker_active(
  p_user_id        text,
  p_username       text,
  p_case_worker_id bigint,
  p_is_active      boolean
)
returns table (id bigint, is_active boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role       text;
  v_full_name  text;
  v_id         bigint;
  v_case_id    bigint;
  v_cust_id    bigint;
  v_case_cust  bigint;
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

  if p_case_worker_id is null or p_is_active is null then
    raise exception 'invalid_arguments' using errcode = 'P0003';
  end if;

  -- ── หาแถวแรงงาน + เคสของมัน ──
  select w.id, w.case_id, w.customer_id into v_id, v_case_id, v_cust_id
  from public.case_workers w where w.id = p_case_worker_id;
  if v_id is null then
    raise exception 'case_worker_not_found' using errcode = 'P0002';
  end if;

  -- ── กันปิดแรงงานหลัก (ยังเป็น cases.customer_id) ──
  if p_is_active = false then
    select cs.customer_id into v_case_cust
    from public.cases cs where cs.id = v_case_id;
    if v_case_cust is not null and v_case_cust = v_cust_id then
      raise exception 'cannot_deactivate_primary_worker' using errcode = 'P0003';
    end if;
  end if;

  update public.case_workers w
  set is_active = p_is_active, updated_at = now(), updated_by_code = p_username
  where w.id = p_case_worker_id
  returning w.id into v_id;

  -- ── audit log ฝั่ง server (best-effort) ──
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_username,
            coalesce(nullif(btrim(coalesce(v_full_name,'')),''), p_username),
            v_role, 'case.worker.set_active', 'case_worker', v_id::text,
            jsonb_build_object('case_id', v_case_id, 'customer_id', v_cust_id,
                               'is_active', p_is_active, 'soft_toggle', true,
                               'internal_only', true));
  exception when others then null;
  end;

  return query select v_id, p_is_active;
end;
$$;

revoke all on function public.app_set_case_worker_active(text, text, bigint, boolean) from public;
grant execute on function public.app_set_case_worker_active(text, text, bigint, boolean) to anon, authenticated;

-- =============================================================
-- C) VERIFICATION QUERIES  [รันบน staging หลัง apply — comment ล้วน ห้ามรันอัตโนมัติ]
--    อ้าง runbook 58G §5–§6 · เก็บผลไว้เทียบใน runbook log
-- =============================================================
-- C.1 ตารางมีจริง:
--   select to_regclass('public.case_workers');   -- ควรได้ 'case_workers' (ไม่ null)
--
-- C.2 คอลัมน์ครบ (คาดหวัง 11 คอลัมน์ ตามนิยาม A):
--   select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--   where table_schema='public' and table_name='case_workers'
--   order by ordinal_position;
--
-- C.3 constraint / index ครบ:
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint where conrelid='public.case_workers'::regclass;
--     -- ควรเห็น: case_workers_pkey, case_workers_role_check,
--     --          FK case_id → cases(id) on delete cascade
--   select indexname, indexdef from pg_indexes
--   where schemaname='public' and tablename='case_workers' order by indexname;
--     -- ควรเห็น: idx_case_workers_case, idx_case_workers_customer,
--     --          uq_case_workers_case_customer_active (partial WHERE is_active),
--     --          case_workers_pkey
--
-- C.4 RPC มีจริง + signature ตามคาด:
--   select p.proname,
--          pg_get_function_identity_arguments(p.oid) as args,
--          p.prosecdef as security_definer
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public'
--     and p.proname in ('app_list_case_workers','app_add_case_worker','app_set_case_worker_active')
--   order by p.proname;
--     -- security_definer ต้องเป็น true ทุกตัว
--
-- C.5 สิทธิ์ตารางปลอดภัย (RPC-only) — direct grant ต้องไม่มีให้ anon/authenticated:
--   select grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_schema='public' and table_name='case_workers'
--     and grantee in ('anon','authenticated','public');
--     -- ควรได้ 0 แถว (revoke all แล้ว)
--
-- C.6 สิทธิ์ execute RPC ครบ anon/authenticated:
--   select p.proname, r.rolname, has_function_privilege(r.rolname, p.oid, 'EXECUTE') as can_exec
--   from pg_proc p
--   join pg_namespace n on n.oid=p.pronamespace
--   cross join (values ('anon'),('authenticated')) r(rolname)
--   where n.nspname='public'
--     and p.proname in ('app_list_case_workers','app_add_case_worker','app_set_case_worker_active');
--     -- can_exec ต้องเป็น true ทุกแถว
--
-- C.7 SMOKE TEST (staging เท่านั้น — ใช้ admin/staff id+username จริงบน staging):
--   -- เตรียม: <uid> <uname> = ผู้ใช้ active บน staging, <case_id> = เคสทดสอบ,
--   --         <cust_a> = customer_id เดียวกับ cases.customer_id ของ <case_id> (แรงงานหลัก),
--   --         <cust_b> = customer_id อื่นที่ไม่ถูก soft delete
--   -- 1) เพิ่มแรงงานหลัก + แรงงานที่สอง:
--   --    select * from public.app_add_case_worker('<uid>','<uname>',<case_id>,<cust_a>);
--   --    select * from public.app_add_case_worker('<uid>','<uname>',<case_id>,<cust_b>,'worker',2);
--   -- 2) idempotent: เพิ่ม <cust_b> ซ้ำ → ต้องได้แถวเดิม (ไม่เพิ่มซ้ำ, is_active=true):
--   --    select * from public.app_add_case_worker('<uid>','<uname>',<case_id>,<cust_b>);
--   -- 3) list: ต้องเห็น 2 แถว, is_primary=true ที่ <cust_a>, ไม่มี storage_path/URL:
--   --    select * from public.app_list_case_workers('<uid>','<uname>',<case_id>);
--   -- 4) ปิด <cust_b> (soft) → is_active=false:
--   --    select * from public.app_set_case_worker_active('<uid>','<uname>',<worker_id_b>,false);
--   -- 5) กันปิดแรงงานหลัก → ต้อง raise 'cannot_deactivate_primary_worker':
--   --    select * from public.app_set_case_worker_active('<uid>','<uname>',<worker_id_a>,false);
--   -- 6) customer ถูก soft delete → ต้อง raise 'customer_not_found':
--   --    select * from public.app_add_case_worker('<uid>','<uname>',<case_id>,<deleted_cust>);
--   -- 7) เคสเดี่ยวเดิม (ไม่มีแถว) → list คืน 0 แถว, UI fallback ใช้ cases.customer_id:
--   --    select * from public.app_list_case_workers('<uid>','<uname>',<legacy_case_id>);
--
-- C.8 ROLLBACK (staging เท่านั้น, เฉพาะเมื่อยังไม่มีข้อมูลใช้จริง — ดู runbook 58G §7):
--   -- drop function if exists public.app_set_case_worker_active(text, text, bigint, boolean);
--   -- drop function if exists public.app_add_case_worker(text, text, bigint, bigint, text, integer, text);
--   -- drop function if exists public.app_list_case_workers(text, text, bigint, boolean);
--   -- drop table if exists public.case_workers;   -- cascade index/constraint ในตัว
-- =============================================================
-- END STAGE 58H-RESET-2 — additive, idempotent, RPC-only. DO NOT APPLY here.
-- =============================================================
