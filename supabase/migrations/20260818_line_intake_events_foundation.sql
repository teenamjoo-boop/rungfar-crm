-- =============================================================
-- LINE-ASSIST-005 — Mitang text intake capture foundation
--
-- Dedicated store for ordinary inbound LINE group text captured when a group is
-- explicitly set to intake_mode='capture'. This is intentionally separate from
-- public.line_file_inbox, which is file-centric (storage_path is required there)
-- and drives the document approval queue and the "document-count" command.
--
-- Patch #12 is text-only: no customer records, no forwarding, no AI, and no
-- file/image capture. Document and PDF/Excel allowlisted groups are excluded by
-- the router in this patch, so mixed-mode groups remain a future decision.
--
-- Edge Functions use service_role; browser roles have no direct table access and
-- no RLS policies are created here.
-- =============================================================

create table if not exists public.line_intake_events (
  id               uuid primary key default gen_random_uuid(),
  group_id         text not null,
  line_message_id  text not null,
  line_event_id    text null,
  text_body        text not null,
  text_length      integer not null,
  text_truncated   boolean not null default false,
  source_user_id   text null,
  event_timestamp  timestamptz null,
  received_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  -- LINE retries webhook deliveries; the message id is the idempotency key and
  -- matches the existing public.line_file_inbox unique-on-message-id precedent.
  constraint line_intake_events_line_message_id_key unique (line_message_id),
  -- The 2000-character bound is enforced here as well as in the router so the
  -- database stays authoritative even if a future caller skips truncation.
  constraint line_intake_events_text_body_len_check
    check (char_length(text_body) <= 2000),
  -- text_length records the pre-truncation length, so it can never be smaller
  -- than what was actually stored.
  constraint line_intake_events_text_length_check
    check (text_length >= char_length(text_body))
);

comment on table public.line_intake_events is
  'Mitang inbound LINE group text captured for groups with intake_mode=capture; text-only, no files and no customer linkage.';
comment on column public.line_intake_events.group_id is
  'LINE group id. Intentionally not a foreign key to public.line_bot_groups in this patch.';
comment on column public.line_intake_events.line_message_id is
  'LINE message id; unique idempotency key for duplicate webhook delivery.';
comment on column public.line_intake_events.line_event_id is
  'LINE webhookEventId, retained for forensics only; never used as the dedupe key.';
comment on column public.line_intake_events.text_body is
  'Inbound message text, truncated to at most 2000 characters.';
comment on column public.line_intake_events.text_length is
  'Original character length before truncation.';
comment on column public.line_intake_events.text_truncated is
  'True when text_body was shortened to satisfy the 2000-character bound.';

create index if not exists idx_line_intake_events_group
  on public.line_intake_events (group_id, created_at desc);

alter table public.line_intake_events enable row level security;

revoke all on table public.line_intake_events from public;
revoke all on table public.line_intake_events from anon;
revoke all on table public.line_intake_events from authenticated;

-- The router only appends rows: it never edits them and never reads their contents.
-- The insert posts to ?on_conflict=line_message_id with
-- Prefer: resolution=ignore-duplicates,return=minimal, so beyond INSERT the only
-- read needed is on the dedupe arbiter column itself. SELECT is therefore granted
-- at column level on line_message_id alone -- never table-wide -- so text_body,
-- source_user_id, line_event_id, text_length, text_truncated, group_id, and the
-- timestamps stay unreadable to service_role. UPDATE and DELETE remain unavailable;
-- acceptance reads use an administrative path.
grant insert on table public.line_intake_events to service_role;
grant select (line_message_id) on table public.line_intake_events to service_role;
revoke update, delete, truncate, references, trigger, maintain
  on table public.line_intake_events
  from service_role;
