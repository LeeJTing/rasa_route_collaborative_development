-- Report housekeeping (time-based) - keeps the DATABASE authoritative on its
-- own, without waiting for a client read.
--
-- WHY (the app already filters expired data at read time - this is the
-- server-side half):
--   1. Report claims expire after 1 year (`reportClaimLifetime` in
--      lib/domain_model/report_claim.dart). The app IGNORES expired rows on
--      every read (counts, dedupe, pin consensus, closure end-date
--      resolution) but nothing ever deletes them - they would pile up forever.
--   2. A reported temporary closure freezes the place (`status='frozen'` +
--      `closed_until`). Once the end date passes, the app treats the place as
--      available AND writes 'available' back - but only for places some
--      client happens to read. This job catches the whole table up, daily.
--      `closed_permanently` freezes (`closed_until IS NULL`) are NOT touched:
--      the standing outcome stays until a human reviews it.
--
-- The work runs in the `report-housekeeping` Edge Function
-- (supabase/functions/report-housekeeping/index.ts) with the service_role key
-- Supabase injects there. DEPLOY IT FIRST:
--   supabase functions deploy report-housekeeping --project-ref odtmtukexckfjbuqkxyo
-- or Dashboard -> Edge Functions -> Create -> name it exactly
-- `report-housekeeping` and paste index.ts. Leave *Verify JWT* enabled.
--
-- The Authorization header carries the project's PUBLISHABLE key - the same
-- pattern as 20260911000000_dish_audio_webhook_trigger.sql: that key is
-- public (it ships inside the app), so embedding it here leaks nothing, and
-- Edge Functions accept it as a valid JWT for invocation. The privileged work
-- happens INSIDE the function with the service_role key - never stored in
-- this database or in git.
--
-- Idempotent, safe to re-run. Run in the Supabase SQL editor (owner role).
-- If `create extension pg_cron` is refused here, enable *pg_cron* from
-- Dashboard -> Database -> Extensions and re-run this file.

-- ============================================================================
-- 1) Extensions - a cron runner and an HTTP client. (pg_net is already
--    enabled by the dish-audio trigger migration.)
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- An index so the daily delete never scans the whole table as claims pile up.
create index if not exists report_created_at_idx on public.report (created_at);

-- ============================================================================
-- 2) The daily schedule - pg_cron calls the Edge Function at 16:30 UTC
--    (00:30 in Malaysia, MYT = UTC+8; pg_cron always runs on UTC).
--    The app's read-time rules stay as the real-time safety net; this job is
--    the persistence cleanup.
-- ============================================================================

select cron.unschedule('report-housekeeping')
where exists (select 1 from cron.job where jobname = 'report-housekeeping');

select cron.schedule(
  'report-housekeeping',
  '30 16 * * *',
  $$
  select net.http_post(
    url := 'https://odtmtukexckfjbuqkxyo.supabase.co/functions/v1/report-housekeeping',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'sb_publishable_Z3WBHi4Q87UtlPX2-9wgxg_jspPG7uc',
      'Authorization', 'Bearer sb_publishable_Z3WBHi4Q87UtlPX2-9wgxg_jspPG7uc'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- ============================================================================
-- 3) Verify (uncomment and run pieces as needed).
-- ============================================================================

-- The job itself:
--   select jobid, jobname, schedule, active from cron.job;
-- Its run history - one row per firing, status 'succeeded' / 'failed':
--   select jobid, status, return_message, start_time
--     from cron.job_run_details order by start_time desc limit 5;
-- What the Edge Function answered (JSON summary: deleted_claims,
-- reactivated_restaurants, reactivated_landmarks):
--   select id, status_code, content, created
--     from net._http_response order by created desc limit 5;

-- Manual DRY RUN - the same call the schedule makes, but counts only,
-- writes nothing (check net._http_response a few seconds later):
--   select net.http_post(
--     url := 'https://odtmtukexckfjbuqkxyo.supabase.co/functions/v1/report-housekeeping',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'apikey', 'sb_publishable_Z3WBHi4Q87UtlPX2-9wgxg_jspPG7uc',
--       'Authorization', 'Bearer sb_publishable_Z3WBHi4Q87UtlPX2-9wgxg_jspPG7uc'
--     ),
--     body := '{"dry_run": true}'::jsonb
--   );

-- Remove the schedule entirely:
--   select cron.unschedule('report-housekeeping');

-- ============================================================================
-- 4) Alternative WITHOUT the Edge Function (same rules, pure SQL) - if you
--    ever want to drop the HTTP hop, unschedule the job above and schedule
--    this instead. The 365-day cutoff mirrors `reportClaimLifetime` exactly.
-- ============================================================================

--   select cron.schedule(
--     'report-housekeeping',
--     '30 16 * * *',
--     $job$
--       delete from public.report
--        where created_at < now() - interval '365 days';
--       update public.restaurant
--          set status = 'available', closed_until = null
--        where status = 'frozen' and closed_until is not null
--          and closed_until <= now();
--       update public.submitted_landmark
--          set status = 'available', closed_until = null
--        where status = 'frozen' and closed_until is not null
--          and closed_until <= now();
--     $job$
--   );
