-- ============================================================================
-- N8N-001A — Automation Integration Foundation (READ-ONLY V1)
-- Target: Supabase STAGING ONLY (bzwtknqvhvdmatangzqf)
--
-- Purpose
--   Provide a minimal, hard-allowlisted, read-only integration surface for an
--   external automation client (n8n). Machine identity is completely separate
--   from public.app_users; no human authentication path is touched.
--
-- Security contract (mandatory)
--   * All 5 functions are SECURITY INVOKER (never SECURITY DEFINER).
--   * All 5 functions use SET search_path = '' and fully-qualify every relation.
--   * EXECUTE is granted ONLY to service_role.
--   * No new privilege is granted on any existing business table. service_role
--     already holds SELECT on public.cases / customers / employers /
--     case_checklist_items and has rolbypassrls = true, so SECURITY INVOKER is
--     sufficient and no elevation is required.
--   * No existing app_* function, grant, or RLS policy is modified.
--
-- Business timezone
--   BUSINESS_TIMEZONE = Asia/Bangkok. The database default TimeZone is UTC, so
--   business dates are computed with an explicit Bangkok conversion and never
--   with bare current_date.
--
-- Clock authority
--   The database clock is authoritative. The Edge layer never supplies
--   created_at, finished_at, or any authoritative current time.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Audit table
-- ---------------------------------------------------------------------------
-- Records one row per ADMITTED integration request. Contains no token, no auth
-- header, no request/response payload, and no business or personal data.

create table public.integration_request_logs (
  request_id        uuid        primary key,
  client_code       text        not null,
  client_request_id text        null,
  action            text        not null,
  outcome           text        not null,
  row_count         integer     null,
  duration_ms       integer     null,
  error_code        text        null,
  created_at        timestamptz not null,
  finished_at       timestamptz null,

  constraint integration_request_logs_client_code_check
    check (client_code in ('n8n-staging-readonly')),

  constraint integration_request_logs_action_check
    check (action in ('health.v1', 'management.summary.v1', 'cases.readiness.v1')),

  constraint integration_request_logs_outcome_check
    check (outcome in ('started', 'success', 'error', 'timeout'))
);

comment on table public.integration_request_logs is
  'N8N-001A machine integration request audit. No secrets, no auth headers, no business payload, no PII.';

-- Supports the rolling rate-admission window lookup.
create index integration_request_logs_client_created_idx
  on public.integration_request_logs (client_code, created_at desc);

-- RLS: enabled with NO policies. anon/authenticated therefore have no access at
-- all. service_role carries rolbypassrls = true and reaches the table through
-- the explicit grants below only.
alter table public.integration_request_logs enable row level security;

revoke all on table public.integration_request_logs from public;
revoke all on table public.integration_request_logs from anon;
revoke all on table public.integration_request_logs from authenticated;

-- Deliberately NO DELETE: the integration audit is append-and-finalize only.
grant select, insert, update on table public.integration_request_logs to service_role;

-- This project carries an ALTER DEFAULT PRIVILEGES rule on schema public that
-- auto-grants TRUNCATE/REFERENCES/TRIGGER/MAINTAIN to service_role on every new
-- table (pg_default_acl: service_role=Dxtm/postgres). Those are stripped here so
-- the effective service_role privilege set on this audit table is EXACTLY
-- SELECT / INSERT / UPDATE. TRUNCATE in particular would otherwise allow the
-- audit trail to be wiped, which contradicts append-and-finalize semantics.
--
-- Must run AFTER the grant above. Verified on Staging: relacl becomes
--   postgres=arwdDxtm/postgres | service_role=arw/postgres
revoke truncate, references, trigger, maintain
  on table public.integration_request_logs
  from service_role;

-- ---------------------------------------------------------------------------
-- 2. Rate admission
-- ---------------------------------------------------------------------------
-- Serializes admission for the single machine client behind a FIXED transaction
-- advisory lock. The lock key is a hard-coded constant and is never derived from
-- client input. All timing uses the database clock.
--
-- Thresholds: 5 / rolling second, 30 / rolling minute, 300 / rolling hour.
-- A rejected request does NOT insert a 'started' row.

create or replace function public.integration_n8n_admit_request_v1(
  p_request_id        uuid,
  p_client_code       text,
  p_action            text,
  p_client_request_id text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now     timestamptz;
  v_sec     bigint;
  v_min     bigint;
  v_hour    bigint;
begin
  -- Static allowlist validation happens before any admission side effect.
  if p_request_id is null then
    return jsonb_build_object('admitted', false, 'error_code', 'invalid_request_id');
  end if;

  if p_client_code is distinct from 'n8n-staging-readonly' then
    return jsonb_build_object('admitted', false, 'error_code', 'invalid_client');
  end if;

  if p_action is null
     or p_action not in ('health.v1', 'management.summary.v1', 'cases.readiness.v1') then
    return jsonb_build_object('admitted', false, 'error_code', 'invalid_action');
  end if;

  -- client_request_id is informational only. It never affects auth, timing,
  -- rate limiting, or request identity.
  if p_client_request_id is not null then
    if pg_catalog.length(p_client_request_id) < 1
       or pg_catalog.length(p_client_request_id) > 80
       or p_client_request_id !~ '^[A-Za-z0-9._:-]+$' then
      return jsonb_build_object('admitted', false, 'error_code', 'invalid_client_request_id');
    end if;
  end if;

  -- Fixed, non-client-controlled advisory lock key. Serializes admission for
  -- this one client for the remainder of the transaction.
  perform pg_catalog.pg_advisory_xact_lock(4820260814);

  -- ONE database clock read drives every window and the inserted created_at.
  v_now := pg_catalog.clock_timestamp();

  select
    pg_catalog.count(*) filter (where l.created_at > v_now - '1 second'::interval),
    pg_catalog.count(*) filter (where l.created_at > v_now - '1 minute'::interval),
    pg_catalog.count(*) filter (where l.created_at > v_now - '1 hour'::interval)
  into v_sec, v_min, v_hour
  from public.integration_request_logs l
  where l.client_code = p_client_code
    and l.created_at > v_now - '1 hour'::interval;

  if v_sec >= 5 then
    return jsonb_build_object('admitted', false, 'error_code', 'rate_limited_second');
  end if;

  if v_min >= 30 then
    return jsonb_build_object('admitted', false, 'error_code', 'rate_limited_minute');
  end if;

  if v_hour >= 300 then
    return jsonb_build_object('admitted', false, 'error_code', 'rate_limited_hour');
  end if;

  insert into public.integration_request_logs (
    request_id, client_code, client_request_id, action, outcome, created_at
  )
  values (
    p_request_id, p_client_code, p_client_request_id, p_action, 'started', v_now
  );

  return jsonb_build_object('admitted', true, 'error_code', null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Finish / finalize audit
-- ---------------------------------------------------------------------------
-- finished_at and duration_ms are derived from the database clock. The caller
-- cannot supply either value.

create or replace function public.integration_n8n_finish_request_v1(
  p_request_id uuid,
  p_outcome    text,
  p_row_count  integer default null,
  p_error_code text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now     timestamptz;
  v_updated integer;
begin
  if p_request_id is null then
    return jsonb_build_object('finished', false, 'error_code', 'invalid_request_id');
  end if;

  if p_outcome is null or p_outcome not in ('success', 'error', 'timeout') then
    return jsonb_build_object('finished', false, 'error_code', 'invalid_outcome');
  end if;

  v_now := pg_catalog.clock_timestamp();

  update public.integration_request_logs l
     set outcome     = p_outcome,
         finished_at = v_now,
         row_count   = p_row_count,
         error_code  = pg_catalog.left(p_error_code, 80),
         duration_ms = (pg_catalog.date_part('epoch', v_now - l.created_at) * 1000)::integer
   where l.request_id = p_request_id
     and l.outcome = 'started';

  get diagnostics v_updated = row_count;

  return jsonb_build_object('finished', v_updated = 1, 'error_code', null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. health.v1
-- ---------------------------------------------------------------------------
-- Exposes only safe, non-identifying service facts. No DB version, no host, no
-- credential, no internal table inventory.

create or replace function public.integration_n8n_health_v1()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'service',           'rungfar-crm-n8n-read',
    'environment',       'staging',
    'database',          'reachable',
    'business_timezone', 'Asia/Bangkok',
    'business_date',     pg_catalog.to_char(
                           (pg_catalog.clock_timestamp() at time zone 'Asia/Bangkok')::date,
                           'YYYY-MM-DD'
                         )
  );
$$;

-- ---------------------------------------------------------------------------
-- 5. management.summary.v1
-- ---------------------------------------------------------------------------
-- OPEN case semantics preserve existing CRM behavior (public.app_case_summary):
--   case_status not in ('approved','rejected','cancelled','completed')
-- Per-status counts are over ALL cases; due_soon/overdue apply to OPEN cases
-- only. Business dates use one Bangkok business_date per execution.
--
-- Required-item completion semantics preserve public.app_case_checklist_summary:
--   COMPLETE  = approved | waived | not_required
--   REMAINING = missing | received | reviewing | needs_fix
--
-- No appointment, expiry, or tracking data is included in N8N-001A.

create or replace function public.integration_n8n_management_summary_v1()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  with b as (
    select (pg_catalog.clock_timestamp() at time zone 'Asia/Bangkok')::date as business_date
  ),
  c as (
    select
      pg_catalog.count(*) filter (
        where cs.case_status not in ('approved','rejected','cancelled','completed')
      ) as total_open,
      pg_catalog.count(*) filter (where cs.case_status = 'draft')               as draft,
      pg_catalog.count(*) filter (where cs.case_status = 'preparing_documents') as preparing_documents,
      pg_catalog.count(*) filter (where cs.case_status = 'ready_to_submit')     as ready_to_submit,
      pg_catalog.count(*) filter (where cs.case_status = 'submitted')           as submitted,
      pg_catalog.count(*) filter (where cs.case_status = 'waiting_result')      as waiting_result,
      pg_catalog.count(*) filter (where cs.case_status = 'approved')            as approved,
      pg_catalog.count(*) filter (where cs.case_status = 'rejected')            as rejected,
      pg_catalog.count(*) filter (where cs.case_status = 'cancelled')           as cancelled,
      pg_catalog.count(*) filter (where cs.case_status = 'completed')           as completed,
      pg_catalog.count(*) filter (
        where cs.case_status not in ('approved','rejected','cancelled','completed')
          and cs.due_date is not null
          and cs.due_date >= (select business_date from b)
          and cs.due_date <= (select business_date from b) + 7
      ) as due_soon_7,
      pg_catalog.count(*) filter (
        where cs.case_status not in ('approved','rejected','cancelled','completed')
          and cs.due_date is not null
          and cs.due_date < (select business_date from b)
      ) as overdue
    from public.cases cs
  ),
  open_cases as (
    select cs.id
    from public.cases cs
    where cs.case_status not in ('approved','rejected','cancelled','completed')
  ),
  per_case as (
    select
      oc.id,
      pg_catalog.count(i.id) filter (where i.is_required) as required_items,
      pg_catalog.count(i.id) filter (
        where i.is_required
          and i.checklist_status not in ('approved','waived','not_required')
      ) as required_remaining,
      pg_catalog.count(i.id) filter (
        where i.is_required and i.checklist_status = 'missing'
      ) as missing,
      pg_catalog.count(i.id) filter (
        where i.is_required and i.checklist_status = 'needs_fix'
      ) as needs_fix
    from open_cases oc
    left join public.case_checklist_items i on i.case_id = oc.id
    group by oc.id
  ),
  r as (
    select
      pg_catalog.count(*) filter (where pc.required_remaining > 0) as blocked_open_cases,
      coalesce(pg_catalog.sum(pc.required_items), 0)               as required_items,
      coalesce(pg_catalog.sum(pc.required_remaining), 0)           as required_remaining,
      coalesce(pg_catalog.sum(pc.missing), 0)                      as missing,
      coalesce(pg_catalog.sum(pc.needs_fix), 0)                    as needs_fix
    from per_case pc
  )
  select jsonb_build_object(
    'business_date', pg_catalog.to_char((select business_date from b), 'YYYY-MM-DD'),
    'active_customers', (select pg_catalog.count(*) from public.customers cu where cu.deleted_at is null),
    'employers_total',  (select pg_catalog.count(*) from public.employers),
    'cases', jsonb_build_object(
      'total_open',           c.total_open,
      'draft',                c.draft,
      'preparing_documents',  c.preparing_documents,
      'ready_to_submit',      c.ready_to_submit,
      'submitted',            c.submitted,
      'waiting_result',       c.waiting_result,
      'approved',             c.approved,
      'rejected',             c.rejected,
      'cancelled',            c.cancelled,
      'completed',            c.completed,
      'due_soon_7',           c.due_soon_7,
      'overdue',              c.overdue
    ),
    'readiness', jsonb_build_object(
      'blocked_open_cases', r.blocked_open_cases,
      'required_items',     r.required_items,
      'required_remaining', r.required_remaining,
      'missing',            r.missing,
      'needs_fix',          r.needs_fix
    )
  )
  from c, r;
$$;

-- ---------------------------------------------------------------------------
-- 6. cases.readiness.v1
-- ---------------------------------------------------------------------------
-- OPEN cases only, hard cap 100.
--
-- Canonical ordering reuses the existing CRM case-list semantic
-- (public.app_list_cases orders by cs.created_at desc) and adds a deterministic
-- stable tie-breaker:
--     order by public.cases.created_at desc, public.cases.id desc
-- Remaining checklist items are ordered sort_order asc, id asc.
--
-- Exposes NO customer name, passport_no, alien_id, wp_no, visa_no, notes,
-- document metadata, storage/file metadata, or URLs.
--
-- Per-case counters are scoped to REQUIRED items, so the contract is internally
-- consistent: required_remaining_count = missing + received + reviewing + needs_fix.

create or replace function public.integration_n8n_case_readiness_v1()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  with open_cases as (
    select cs.id, cs.case_code, cs.case_status, cs.due_date, cs.created_at
    from public.cases cs
    where cs.case_status not in ('approved','rejected','cancelled','completed')
  ),
  capped as (
    select oc.*
    from open_cases oc
    order by oc.created_at desc, oc.id desc
    limit 100
  ),
  agg as (
    select
      cp.id,
      pg_catalog.count(i.id) filter (where i.is_required) as required_items,
      pg_catalog.count(i.id) filter (
        where i.is_required and i.checklist_status in ('approved','waived','not_required')
      ) as complete_required_count,
      pg_catalog.count(i.id) filter (
        where i.is_required and i.checklist_status not in ('approved','waived','not_required')
      ) as required_remaining_count,
      pg_catalog.count(i.id) filter (where i.is_required and i.checklist_status = 'missing')   as missing_count,
      pg_catalog.count(i.id) filter (where i.is_required and i.checklist_status = 'received')  as received_count,
      pg_catalog.count(i.id) filter (where i.is_required and i.checklist_status = 'reviewing') as reviewing_count,
      pg_catalog.count(i.id) filter (where i.is_required and i.checklist_status = 'needs_fix') as needs_fix_count
    from capped cp
    left join public.case_checklist_items i on i.case_id = cp.id
    group by cp.id
  ),
  items as (
    select
      i.case_id,
      jsonb_agg(
        jsonb_build_object(
          'item_code',        i.item_code,
          'item_title_th',    i.item_title_th,
          'required_from',    i.required_from,
          'doc_type',         i.doc_type,
          'checklist_status', i.checklist_status
        )
        order by i.sort_order asc, i.id asc
      ) as remaining_items
    from public.case_checklist_items i
    where i.case_id in (select cp.id from capped cp)
      and i.is_required
      and i.checklist_status not in ('approved','waived','not_required')
    group by i.case_id
  )
  select jsonb_build_object(
    'business_date',    pg_catalog.to_char(
                          (pg_catalog.clock_timestamp() at time zone 'Asia/Bangkok')::date,
                          'YYYY-MM-DD'
                        ),
    'total_open_cases', (select pg_catalog.count(*) from open_cases),
    'returned_count',   (select pg_catalog.count(*) from capped),
    'truncated',        ((select pg_catalog.count(*) from open_cases) > (select pg_catalog.count(*) from capped)),
    'cases', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'case_id',                  cp.id,
            'case_code',                cp.case_code,
            'case_status',              cp.case_status,
            'due_date',                 pg_catalog.to_char(cp.due_date, 'YYYY-MM-DD'),
            'required_items',           a.required_items,
            'complete_required_count',  a.complete_required_count,
            'required_remaining_count', a.required_remaining_count,
            'missing_count',            a.missing_count,
            'received_count',           a.received_count,
            'reviewing_count',          a.reviewing_count,
            'needs_fix_count',          a.needs_fix_count,
            'readiness_status',         case
                                          when a.needs_fix_count > 0 then 'needs_fix'
                                          when a.required_remaining_count > 0 then 'blocked'
                                          else 'ready'
                                        end,
            'remaining_items',          coalesce(it.remaining_items, '[]'::jsonb)
          )
          order by cp.created_at desc, cp.id desc
        )
        from capped cp
        join agg a on a.id = cp.id
        left join items it on it.case_id = cp.id
      ),
      '[]'::jsonb
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 7. Function privileges
-- ---------------------------------------------------------------------------
-- EXECUTE for service_role only. No new privilege on any existing business table.

revoke all on function public.integration_n8n_admit_request_v1(uuid, text, text, text) from public;
revoke all on function public.integration_n8n_admit_request_v1(uuid, text, text, text) from anon;
revoke all on function public.integration_n8n_admit_request_v1(uuid, text, text, text) from authenticated;
grant execute on function public.integration_n8n_admit_request_v1(uuid, text, text, text) to service_role;

revoke all on function public.integration_n8n_finish_request_v1(uuid, text, integer, text) from public;
revoke all on function public.integration_n8n_finish_request_v1(uuid, text, integer, text) from anon;
revoke all on function public.integration_n8n_finish_request_v1(uuid, text, integer, text) from authenticated;
grant execute on function public.integration_n8n_finish_request_v1(uuid, text, integer, text) to service_role;

revoke all on function public.integration_n8n_health_v1() from public;
revoke all on function public.integration_n8n_health_v1() from anon;
revoke all on function public.integration_n8n_health_v1() from authenticated;
grant execute on function public.integration_n8n_health_v1() to service_role;

revoke all on function public.integration_n8n_management_summary_v1() from public;
revoke all on function public.integration_n8n_management_summary_v1() from anon;
revoke all on function public.integration_n8n_management_summary_v1() from authenticated;
grant execute on function public.integration_n8n_management_summary_v1() to service_role;

revoke all on function public.integration_n8n_case_readiness_v1() from public;
revoke all on function public.integration_n8n_case_readiness_v1() from anon;
revoke all on function public.integration_n8n_case_readiness_v1() from authenticated;
grant execute on function public.integration_n8n_case_readiness_v1() to service_role;
