-- =============================================================
-- LINE-ASSIST-002 — Mitang LINE group registry foundation
--
-- Additive registry for LINE groups seen by the OA. This is intentionally
-- separate from public.groups, which is the existing CRM customer-group table.
-- Edge Functions use service_role for registry reads/writes; browser roles have
-- no direct table access and no RLS policies are created here.
-- =============================================================

create table if not exists public.line_bot_groups (
  group_id      text primary key,
  group_name    text null,
  picture_url   text null,
  branch_id     bigint null references public.branches(id) on delete set null,
  is_active     boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  joined_at     timestamptz null,
  left_at       timestamptz null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.line_bot_groups is
  'Mitang registry of LINE groups seen by the OA; distinct from the CRM public.groups table.';

alter table public.line_bot_groups enable row level security;

revoke all on table public.line_bot_groups from public;
revoke all on table public.line_bot_groups from anon;
revoke all on table public.line_bot_groups from authenticated;

-- The router needs only read/upsert/update. Leave events retain rows, so DELETE
-- and other owner-like privileges are deliberately unavailable to service_role.
grant select, insert, update on table public.line_bot_groups to service_role;
revoke delete, truncate, references, trigger, maintain
  on table public.line_bot_groups
  from service_role;
