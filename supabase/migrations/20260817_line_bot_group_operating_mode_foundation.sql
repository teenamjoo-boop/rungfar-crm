-- =============================================================
-- LINE-ASSIST-004 — Mitang LINE group operating-mode foundation
--
-- Future-ready capability metadata only. These values are intentionally not
-- enforced by the LINE router in this patch, so current command, document, and
-- PDF/Excel behavior remains unchanged.
-- =============================================================

alter table public.line_bot_groups
  add column if not exists command_mode text not null default 'enabled',
  add column if not exists intake_mode text not null default 'none',
  add column if not exists routing_mode text not null default 'none';

do $$
begin
  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conname = 'line_bot_groups_command_mode_check'
       and conrelid = 'public.line_bot_groups'::regclass
  ) then
    alter table public.line_bot_groups
      add constraint line_bot_groups_command_mode_check
      check (command_mode in ('enabled', 'disabled', 'customer_safe'));
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conname = 'line_bot_groups_intake_mode_check'
       and conrelid = 'public.line_bot_groups'::regclass
  ) then
    alter table public.line_bot_groups
      add constraint line_bot_groups_intake_mode_check
      check (intake_mode in ('none', 'observe', 'capture'));
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conname = 'line_bot_groups_routing_mode_check'
       and conrelid = 'public.line_bot_groups'::regclass
  ) then
    alter table public.line_bot_groups
      add constraint line_bot_groups_routing_mode_check
      check (routing_mode in ('none', 'source', 'destination', 'both'));
  end if;
end;
$$;

comment on column public.line_bot_groups.command_mode is
  'Future command capability: enabled, disabled, or reserved customer_safe.';
comment on column public.line_bot_groups.intake_mode is
  'Future intake capability: none, observe, or reserved capture.';
comment on column public.line_bot_groups.routing_mode is
  'Future network routing capability: none, source, destination, or both.';

-- PostgreSQL identifies a function by its input argument types. Drop the
-- seven-argument Patch #7 signature before creating the extended signature so
-- PostgREST cannot see ambiguous overloads. Migration execution is atomic.
drop function if exists public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text
);

-- p_group_type remains before defaulted parameters because PostgreSQL requires
-- every input after the first defaulted input to also have a default. Null mode
-- inputs mean "not supplied" and preserve the row's existing non-null modes.
create or replace function public.app_set_line_bot_group_metadata(
  p_group_id text,
  p_group_type text,
  p_branch_id bigint default null,
  p_route_profile text default null,
  p_department_code text default null,
  p_display_label text default null,
  p_notes text default null,
  p_command_mode text default null,
  p_intake_mode text default null,
  p_routing_mode text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.now();
begin
  if p_group_id is null or pg_catalog.btrim(p_group_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'invalid group id';
  end if;

  perform 1
    from public.line_bot_groups
   where group_id = p_group_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'LINE group registry row not found';
  end if;

  if p_group_type is null or p_group_type not in (
    'general',
    'branch',
    'department',
    'document_inbox',
    'pdf_excel',
    'finance',
    'management',
    'sandbox'
  ) then
    raise exception using
      errcode = '22023',
      message = 'invalid LINE group type';
  end if;

  if p_branch_id is not null and not exists (
    select 1
      from public.branches
     where id = p_branch_id
  ) then
    raise exception using
      errcode = '23503',
      message = 'branch not found';
  end if;

  if p_command_mode is not null and p_command_mode not in (
    'enabled', 'disabled', 'customer_safe'
  ) then
    raise exception using
      errcode = '22023',
      message = 'invalid LINE group command mode';
  end if;

  if p_intake_mode is not null and p_intake_mode not in (
    'none', 'observe', 'capture'
  ) then
    raise exception using
      errcode = '22023',
      message = 'invalid LINE group intake mode';
  end if;

  if p_routing_mode is not null and p_routing_mode not in (
    'none', 'source', 'destination', 'both'
  ) then
    raise exception using
      errcode = '22023',
      message = 'invalid LINE group routing mode';
  end if;

  update public.line_bot_groups
     set branch_id = p_branch_id,
         group_type = p_group_type,
         route_profile = p_route_profile,
         department_code = p_department_code,
         display_label = p_display_label,
         notes = p_notes,
         command_mode = coalesce(p_command_mode, command_mode),
         intake_mode = coalesce(p_intake_mode, intake_mode),
         routing_mode = coalesce(p_routing_mode, routing_mode),
         metadata_updated_at = v_now,
         updated_at = v_now
   where group_id = p_group_id;
end;
$$;

revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text, text, text, text
) from public;
revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text, text, text, text
) from anon;
revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text, text, text, text
) from authenticated;
grant execute on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text, text, text, text
) to service_role;
