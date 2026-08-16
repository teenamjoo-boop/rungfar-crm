-- =============================================================
-- LINE-ASSIST-006 — Mitang unsend privacy foundation
--
-- LINE sends an "unsend" webhook event when a user retracts a message. Any text
-- previously captured into public.line_intake_events must then be physically
-- removed, and must not be recreated when LINE redelivers the original message
-- event out of order.
--
-- Two mechanisms cooperate:
--   1. public.line_intake_unsent_tombstones records that a message id was
--      unsent. It stores no message text and no sender identity.
--   2. A BEFORE INSERT guard on public.line_intake_events drops any row whose
--      message id is tombstoned.
--
-- Both the guard and the unsend RPC serialize on the SAME transaction-level
-- advisory lock derived from line_message_id, so a concurrent capture and unsend
-- cannot interleave between the tombstone check and the insert/delete. A trigger
-- alone would not be sufficient: without the shared lock, a capture could pass
-- the tombstone check and commit after an unsend already deleted the row.
--
-- Advisory lock namespace 20260819 is reserved for this patch. The second lock
-- key is pg_catalog.hashtext(line_message_id); a hash collision may serialize
-- two unrelated message ids, which costs a little concurrency but never
-- weakens correctness.
--
-- service_role never receives DELETE on public.line_intake_events and never
-- receives any privilege on the tombstone table. All mutation happens through
-- the SECURITY DEFINER RPC below.
-- =============================================================

create table if not exists public.line_intake_unsent_tombstones (
  id                     uuid primary key default gen_random_uuid(),
  group_id               text not null,
  line_message_id        text not null,
  unsent_event_id        text null,
  unsent_event_timestamp timestamptz null,
  created_at             timestamptz not null default now(),
  -- Message ids are the system-wide identity for a captured message, matching
  -- the unique constraint already carried by public.line_intake_events.
  constraint line_intake_unsent_tombstones_line_message_id_key unique (line_message_id)
);

comment on table public.line_intake_unsent_tombstones is
  'Mitang record of LINE messages retracted via unsend; content-free and used only to block resurrection of captured text.';
comment on column public.line_intake_unsent_tombstones.group_id is
  'LINE group id the unsend event arrived from. Intentionally not a foreign key.';
comment on column public.line_intake_unsent_tombstones.line_message_id is
  'Unsent LINE message id; unique so repeated unsend deliveries stay idempotent.';
comment on column public.line_intake_unsent_tombstones.unsent_event_id is
  'LINE webhookEventId of the unsend event, retained for forensics only.';

alter table public.line_intake_unsent_tombstones enable row level security;

-- Explicit revokes rather than relying on the project default ACL: service_role
-- must hold zero direct privilege on this table.
revoke all on table public.line_intake_unsent_tombstones from public;
revoke all on table public.line_intake_unsent_tombstones from anon;
revoke all on table public.line_intake_unsent_tombstones from authenticated;
revoke all on table public.line_intake_unsent_tombstones from service_role;

-- -------------------------------------------------------------
-- BEFORE INSERT guard on public.line_intake_events
-- -------------------------------------------------------------

create or replace function public.line_intake_events_unsent_guard()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  -- Lock first, then read. Reading before locking would allow a capture to
  -- observe "no tombstone", block on the lock held by a concurrent unsend, and
  -- then insert a row the unsend has already deleted.
  perform pg_catalog.pg_advisory_xact_lock(
    20260819,
    pg_catalog.hashtext(new.line_message_id)
  );

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
  'BEFORE INSERT guard dropping captured text whose LINE message id has been unsent; serializes on the Patch #13 advisory lock.';

drop trigger if exists line_intake_events_unsent_guard_trg on public.line_intake_events;
create trigger line_intake_events_unsent_guard_trg
  before insert on public.line_intake_events
  for each row
  execute function public.line_intake_events_unsent_guard();

-- The function exists only to back the trigger above. PostgreSQL checks EXECUTE
-- at trigger creation time, not at firing time, so removing EXECUTE does not
-- affect inserts performed by service_role.
revoke all on function public.line_intake_events_unsent_guard() from public;
revoke all on function public.line_intake_events_unsent_guard() from anon;
revoke all on function public.line_intake_events_unsent_guard() from authenticated;
revoke all on function public.line_intake_events_unsent_guard() from service_role;

-- -------------------------------------------------------------
-- Unsend RPC
-- -------------------------------------------------------------

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

  -- Same namespace and same key derivation as the insert guard, so capture and
  -- unsend for one message id can never run concurrently.
  perform pg_catalog.pg_advisory_xact_lock(
    20260819,
    pg_catalog.hashtext(p_line_message_id)
  );

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
  'Atomically tombstones an unsent LINE message id and deletes any captured text for it; returns the number of rows removed.';

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
