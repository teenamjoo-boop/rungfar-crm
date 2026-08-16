-- =============================================================
-- LINE-ASSIST-006a — Mitang unsend advisory lock hardening
--
-- Corrective follow-up to 20260819_line_intake_unsend_foundation.sql. That
-- migration is already applied and is left untouched; this file is the
-- canonical documentation of the final locking behavior.
--
-- Observed problem
-- ----------------
-- The foundation derived a per-message advisory key by hashing each
-- line_message_id. A transaction inserting several rows
-- therefore acquired several distinct Patch #13 advisory locks, one per message
-- id, in row order. Two concurrent transactions inserting the same message ids
-- in opposite order formed a lock cycle, reproduced in Staging as a genuine
-- PostgreSQL deadlock:
--
--   SQLSTATE 40P01 deadlock detected
--   advisory lock [5,20260819,2554966459,2] / [5,20260819,3996586956,2]
--   CONTEXT: public.line_intake_events_unsent_guard()
--
-- Fix
-- ---
-- Both the insert guard and the unsend RPC now take ONE global transaction
-- advisory lock: namespace 20260819, key 0. A transaction that inserts many
-- rows fires the guard many times but requests the same single lock each time,
-- and re-acquiring a lock already held in the same transaction is immediate.
-- With exactly one Patch #13 advisory resource in existence there is no second
-- resource to form a cycle with, so the reverse-order deadlock is structurally
-- impossible rather than merely unlikely.
--
-- Tradeoff (accepted deliberately)
-- --------------------------------
-- All generic intake capture and all unsend mutations now serialize against
-- each other for the duration of their transactions. These transactions are
-- short — a bounded insert or a tombstone-plus-delete — and generic intake is
-- opt-in per group, so the throughput ceiling is accepted in exchange for
-- deadlock freedom. Correctness is enforced in the database, not by ordering
-- rows in the caller.
--
-- Both functions keep their existing signatures, VOLATILE + SECURITY DEFINER +
-- search_path = '' hardening, and privilege model. CREATE OR REPLACE preserves
-- ownership and rebinds the existing trigger automatically, so no table,
-- trigger, policy, extension, or table-level privilege is touched here.
-- =============================================================

create or replace function public.line_intake_events_unsent_guard()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  -- One global Patch #13 lock (namespace 20260819, key 0). Lock first, then
  -- read: reading before locking would let a capture observe "no tombstone",
  -- block behind a concurrent unsend, and then insert a row that unsend had
  -- already deleted.
  perform pg_catalog.pg_advisory_xact_lock(20260819, 0);

  if exists (
    select 1
      from public.line_intake_unsent_tombstones t
     where t.line_message_id = new.line_message_id
  ) then
    -- Silently drop the row; the caller uses Prefer: return=minimal and must not
    -- learn whether a given message was retracted.
    return null;
  end if;

  return new;
end;
$$;

comment on function public.line_intake_events_unsent_guard() is
  'BEFORE INSERT guard dropping captured text whose LINE message id has been unsent; serializes on the single global Patch #13 advisory lock (namespace 20260819, key 0) so multi-row inserts cannot deadlock.';

-- Reasserted for determinism. CREATE OR REPLACE preserves the existing ACL, but
-- restating the revokes keeps this migration correct on any database where the
-- functions are created fresh.
revoke all on function public.line_intake_events_unsent_guard() from public;
revoke all on function public.line_intake_events_unsent_guard() from anon;
revoke all on function public.line_intake_events_unsent_guard() from authenticated;
revoke all on function public.line_intake_events_unsent_guard() from service_role;

create or replace function public.app_unsend_line_intake_event(
  p_group_id text,
  p_line_message_id text,
  p_unsent_event_id text default null,
  p_unsent_event_timestamp timestamptz default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_deleted integer := 0;
begin
  if p_group_id is null or pg_catalog.btrim(p_group_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'invalid group id';
  end if;

  if p_line_message_id is null or pg_catalog.btrim(p_line_message_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'invalid line message id';
  end if;

  -- Identical global lock to the insert guard, so capture and unsend for any
  -- message id can never interleave.
  perform pg_catalog.pg_advisory_xact_lock(20260819, 0);

  -- Tombstone first: it must exist even when no row was captured, so a later
  -- redelivery of the original message is still blocked.
  insert into public.line_intake_unsent_tombstones (
    group_id,
    line_message_id,
    unsent_event_id,
    unsent_event_timestamp
  ) values (
    p_group_id,
    p_line_message_id,
    p_unsent_event_id,
    p_unsent_event_timestamp
  )
  on conflict (line_message_id) do nothing;

  delete from public.line_intake_events
   where line_message_id = p_line_message_id
     and group_id = p_group_id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.app_unsend_line_intake_event(text, text, text, timestamptz) is
  'Atomically tombstones an unsent LINE message id and deletes any captured text for it under the single global Patch #13 advisory lock (namespace 20260819, key 0); returns the number of rows removed.';

revoke all on function public.app_unsend_line_intake_event(
  text, text, text, timestamptz
) from public;
revoke all on function public.app_unsend_line_intake_event(
  text, text, text, timestamptz
) from anon;
revoke all on function public.app_unsend_line_intake_event(
  text, text, text, timestamptz
) from authenticated;
grant execute on function public.app_unsend_line_intake_event(
  text, text, text, timestamptz
) to service_role;
