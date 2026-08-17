-- =============================================================
-- LINE-ASSIST-007b — Mitang retention scheduler (PRODUCTION ONLY)
--
-- This file is Production-only operational SQL. It is deliberately NOT part of
-- supabase/migrations/, because under the Owner's strategy B the Staging project
-- intentionally has no pg_cron installation, no scheduler and no cron job. A
-- cross-environment migration would therefore fail or misrepresent Staging.
--
-- Scheduler contract (intentionally fixed, not parameterised)
-- ----------------------------------------------------------
--   job name  : line-intake-retention-purge
--   schedule  : 17 20 * * *
--   command   : select public.app_purge_line_intake_retention();
--
-- Target business time is 03:17 Asia/Bangkok daily. The approved Production cron
-- clock is GMT / zero-offset UTC, so 03:17 Bangkok is 20:17 GMT on the previous
-- calendar day, giving the fixed expression above. Asia/Bangkok is UTC+7 with no
-- daylight saving, so the mapping is stable while the cron clock stays at a
-- zero-offset, non-DST value.
--
-- cron.timezone MUST be revalidated live immediately before every Production
-- proof or deployment gate. If the cron clock is ever moved off a zero-offset
-- non-DST value, the fixed expression above becomes wrong and this file must be
-- re-approved rather than re-run.
--
-- Retention policy is owned entirely by public.app_purge_line_intake_retention():
-- 30 days measured from line_intake_events.received_at, and unsend tombstones are
-- retained indefinitely in V1. This scheduler neither restates nor alters that
-- policy; it only decides when the function runs. The purge function remains the
-- only path in this design that removes captured rows.
--
-- The script fails closed: every assumption below is asserted before the single
-- scheduling call, and an unexpected pre-existing job of the same name aborts the
-- run rather than being silently replaced.
-- =============================================================

do $chk$
declare
  v_tz  text;
  v_db  text;
begin
  -- 1. pg_cron must already be present. This script never installs it.
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    raise exception using
      errcode = '55000',
      message = 'pg_cron is not present in this database';
  end if;

  -- 2. The purge function must already exist (Patch #13B.1).
  if pg_catalog.to_regprocedure('public.app_purge_line_intake_retention()') is null then
    raise exception using
      errcode = '42883',
      message = 'public.app_purge_line_intake_retention() does not exist';
  end if;

  -- 3/4/5. Execution identity. cron.schedule records the scheduling role as the
  -- job owner, so the job will run as whoever executes this file. Both
  -- current_user and session_user are required to be postgres: current_user is
  -- what pg_cron records, and session_user additionally rules out a
  -- role-switched session that would record postgres while actually being
  -- driven by another login role.
  if pg_catalog.current_database() <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = 'must be executed in the postgres database';
  end if;
  if current_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'must be executed as postgres (current_user)';
  end if;
  if session_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'must be executed as postgres (session_user)';
  end if;

  -- 6. postgres must be able to run the purge function.
  if not pg_catalog.has_function_privilege(
       'postgres', 'public.app_purge_line_intake_retention()', 'EXECUTE') then
    raise exception using
      errcode = '42501',
      message = 'postgres lacks EXECUTE on the purge function';
  end if;

  -- 7. service_role must NOT be able to run it. Retention stays an
  -- administrative operation; the Edge runtime must not be able to trigger it.
  if pg_catalog.has_function_privilege(
       'service_role', 'public.app_purge_line_intake_retention()', 'EXECUTE') then
    raise exception using
      errcode = '42501',
      message = 'service_role unexpectedly holds EXECUTE on the purge function';
  end if;

  -- 8. Cron clock. Only explicit zero-offset, non-DST values are accepted, so a
  -- fixed GMT-based expression cannot silently drift. Any other value -- or an
  -- unset one -- aborts instead of being interpreted.
  v_tz := pg_catalog.current_setting('cron.timezone', true);
  if v_tz is null or pg_catalog.upper(pg_catalog.btrim(v_tz))
       not in ('GMT', 'UTC', 'ETC/UTC') then
    raise exception using
      errcode = '55000',
      message = 'cron.timezone is not an accepted zero-offset value';
  end if;

  -- 9. pg_cron must be reading jobs from the postgres database.
  v_db := pg_catalog.current_setting('cron.database_name', true);
  if v_db is null or v_db <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = 'cron.database_name is not postgres';
  end if;

  -- 10. Fail closed on any pre-existing job of the same name. Named-job
  -- replacement behaviour is deliberately not relied upon.
  if exists (select 1 from cron.job where jobname = 'line-intake-retention-purge') then
    raise exception using
      errcode = '42710',
      message = 'a cron job named line-intake-retention-purge already exists';
  end if;
end
$chk$;

select cron.schedule(
  'line-intake-retention-purge',
  '17 20 * * *',
  $cron$select public.app_purge_line_intake_retention();$cron$
);
