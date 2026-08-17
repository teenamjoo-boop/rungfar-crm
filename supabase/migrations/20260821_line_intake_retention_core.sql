-- =============================================================
-- LINE-ASSIST-007 — Mitang generic intake retention core
--
-- Owner-approved policy:
--   * captured generic LINE text is retained for 30 days
--   * retention age is measured ONLY by public.line_intake_events.received_at
--   * unsend tombstones are retained INDEFINITELY in V1 and are never touched
--     by this patch
--
-- received_at is the authoritative retention clock. event_timestamp reflects when
-- LINE says the message occurred and can be arbitrarily old on a delayed or
-- redelivered webhook; created_at is a row-insert artifact. Using received_at
-- means the clock starts when this system actually took custody of the text.
--
-- Scheduling is deliberately out of scope. This migration installs the index and
-- the purge function only; no cron job, extension, or Edge Function is created.
--
-- Why this delete does NOT take the Patch #13 advisory lock (20260819, 0)
-- ----------------------------------------------------------------------
--   * New captures are written with received_at = now(), so a freshly captured
--     row can never satisfy the 30-day predicate. Purge and capture do not
--     contend for the same rows.
--   * If purge and an unsend touch the same old intake row, ordinary PostgreSQL
--     row-level concurrency resolves it: one statement deletes the row, the other
--     removes zero rows.
--   * Unsend correctness rests on the tombstone being written first, inside the
--     same transaction as its delete -- not on whether that delete happened to
--     remove one row or none. A row purged by retention leaves the tombstone
--     path unaffected, and the BEFORE INSERT guard still blocks any later
--     redelivery.
--   * Taking the single global Patch #13 lock for a potentially large retention
--     delete would serialize it against all capture and unsend activity for the
--     duration of the delete, which is a real availability cost for no
--     correctness gain.
-- =============================================================

-- Supports the retention predicate below. Existing indexes are left untouched:
-- idx_line_intake_events_group (group_id, created_at desc) serves per-group reads
-- and cannot answer a received_at range scan efficiently.
create index if not exists idx_line_intake_events_received_at
  on public.line_intake_events (received_at);

create or replace function public.app_purge_line_intake_retention()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cutoff  timestamptz;
  v_deleted integer := 0;
begin
  -- One stable cutoff for the whole invocation, so the boundary is deterministic
  -- and does not drift while the delete runs.
  v_cutoff := pg_catalog.now() - interval '30 days';

  -- Strictly older than the cutoff. A row exactly at the cutoff is retained.
  delete from public.line_intake_events
   where received_at < v_cutoff;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.app_purge_line_intake_retention() is
  'Deletes captured generic LINE text older than the fixed 30-day retention window, measured only by line_intake_events.received_at; unsend tombstones are intentionally retained indefinitely in V1. Returns the number of rows deleted.';

-- No role is granted EXECUTE. service_role must not be able to run this, and it
-- still holds no direct DELETE on public.line_intake_events. A later scheduler
-- gate will invoke this as the owner; that grant is not part of this migration.
revoke all on function public.app_purge_line_intake_retention() from public;
revoke all on function public.app_purge_line_intake_retention() from anon;
revoke all on function public.app_purge_line_intake_retention() from authenticated;
revoke all on function public.app_purge_line_intake_retention() from service_role;
