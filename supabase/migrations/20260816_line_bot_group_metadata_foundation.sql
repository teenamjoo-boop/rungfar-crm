-- =============================================================
-- LINE-ASSIST-003 — Mitang LINE group metadata foundation
--
-- Additive, manually managed metadata for future network routing. The LINE
-- router continues to own discovery/lifecycle fields only. This migration does
-- not add routing behavior, policies, or direct browser-role table access.
-- =============================================================

alter table public.line_bot_groups
  add column if not exists group_type text not null default 'general',
  add column if not exists route_profile text null,
  add column if not exists department_code text null,
  add column if not exists display_label text null,
  add column if not exists notes text null,
  add column if not exists metadata_updated_at timestamptz null;

do $$
begin
  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conname = 'line_bot_groups_group_type_check'
       and conrelid = 'public.line_bot_groups'::regclass
  ) then
    alter table public.line_bot_groups
      add constraint line_bot_groups_group_type_check
      check (
        group_type in (
          'general',
          'branch',
          'department',
          'document_inbox',
          'pdf_excel',
          'finance',
          'management',
          'sandbox'
        )
      );
  end if;
end;
$$;

comment on column public.line_bot_groups.group_type is
  'Manual classification for future routing; not inferred by the LINE router.';
comment on column public.line_bot_groups.route_profile is
  'Optional manual route profile identifier; no profile table or FK exists yet.';
comment on column public.line_bot_groups.metadata_updated_at is
  'Time at which manually managed group metadata was last updated.';

-- p_group_type appears before defaulted parameters because PostgreSQL requires
-- every input after the first defaulted input to also have a default. Supabase
-- RPC calls use parameter names, so the external field names remain unchanged.
create or replace function public.app_set_line_bot_group_metadata(
  p_group_id text,
  p_group_type text,
  p_branch_id bigint default null,
  p_route_profile text default null,
  p_department_code text default null,
  p_display_label text default null,
  p_notes text default null
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

  update public.line_bot_groups
     set branch_id = p_branch_id,
         group_type = p_group_type,
         route_profile = p_route_profile,
         department_code = p_department_code,
         display_label = p_display_label,
         notes = p_notes,
         metadata_updated_at = v_now,
         updated_at = v_now
   where group_id = p_group_id;
end;
$$;

revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text
) from public;
revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text
) from anon;
revoke all on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text
) from authenticated;
grant execute on function public.app_set_line_bot_group_metadata(
  text, text, bigint, text, text, text, text
) to service_role;
