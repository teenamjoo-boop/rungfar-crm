-- =============================================================
-- LINE Inbox pagination — additive read RPC
--
-- Purpose:
--   * Keep every filter predicate from public.app_list_line_inbox unchanged.
--   * Return one bounded page plus exact filtered/global-pending counts.
--   * Leave the legacy RPC, table, RLS, Storage, router and workers untouched.
--
-- Security model intentionally matches the existing CRM session contract:
--   active public.app_users row identified by (user_id, username), with a
--   non-null role. SECURITY DEFINER is required because line_file_inbox has no
--   direct client SELECT policy. The empty search_path and fully-qualified
--   relations constrain name resolution.
-- =============================================================

create or replace function public.app_list_line_inbox_page(
  p_user_id     text,
  p_username    text,
  p_status      text default null,   -- pending | approved | rejected | linked | (null/all)
  p_source_type text default null,   -- image | pdf | excel | other | (null/all)
  p_start_date  date default null,
  p_end_date    date default null,
  p_sender      text default null,   -- search LINE display name
  p_search      text default null,   -- search filename / note / sender
  p_page_size   integer default 50,
  p_offset      integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ok            boolean := false;
  v_page_size     integer := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_offset        integer := greatest(coalesce(p_offset, 0), 0);
  v_result        jsonb;
begin
  -- Same identity predicate as public.app_list_line_inbox/app_verify_session.
  select true
    into v_ok
  from public.app_users u
  where u.id::text = p_user_id
    and u.username = p_username
    and coalesce(u.is_active, true) = true
    and u.role is not null
  limit 1;

  if not coalesce(v_ok, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  with filtered as materialized (
    select
      f.*,
      case
        when (p_status is null or p_status not in ('pending','approved','rejected','linked'))
          and f.status = 'pending'
        then 0
        else 1
      end as _status_rank
    from public.line_file_inbox f
    where
      -- Keep the legacy RPC's permissive invalid-value semantics exactly:
      -- an unknown status/source value means no filter.
      (p_status is null or p_status not in ('pending','approved','rejected','linked') or f.status = p_status)
      and (p_source_type is null or p_source_type not in ('image','pdf','excel','other') or f.source_type = p_source_type)
      and (p_start_date is null or f.created_at >= p_start_date::timestamptz)
      and (p_end_date is null or f.created_at < ((p_end_date + 1))::timestamptz)
      and (
        p_sender is null or p_sender = ''
        or f.line_display_name ilike '%' || p_sender || '%'
      )
      and (
        p_search is null or p_search = ''
        or f.file_name         ilike '%' || p_search || '%'
        or f.note              ilike '%' || p_search || '%'
        or f.line_display_name ilike '%' || p_search || '%'
      )
  ),
  page_rows as (
    select
      to_jsonb(f) - '_status_rank' as item,
      f._status_rank,
      f.created_at,
      f.id
    from filtered f
    order by f._status_rank, f.created_at desc, f.id desc
    limit v_page_size
    offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(p.item order by p._status_rank, p.created_at desc, p.id desc)
        from page_rows p
      ),
      '[]'::jsonb
    ),
    'total_count', (select count(*) from filtered),
    'pending_count', (
      select count(*)
      from public.line_file_inbox f
      where f.status = 'pending'
    ),
    'page_size', v_page_size,
    'offset', v_offset,
    'has_more', v_offset + v_page_size < (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.app_list_line_inbox_page(
  text, text, text, text, date, date, text, text, integer, integer
) is
  'Bounded LINE inbox metadata page with exact filtered and pending counts; preserves app_list_line_inbox filter semantics.';

-- Functions are executable by PUBLIC by default. Make this intentional and
-- grant only the same client roles as the legacy CRM read RPC.
revoke all on function public.app_list_line_inbox_page(
  text, text, text, text, date, date, text, text, integer, integer
) from public, anon, authenticated;

grant execute on function public.app_list_line_inbox_page(
  text, text, text, text, date, date, text, text, integer, integer
) to anon, authenticated;
