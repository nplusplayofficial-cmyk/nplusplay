BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $scheduler$
DECLARE
    v_job_id bigint;
BEGIN
    FOR v_job_id IN
        SELECT jobid
        FROM cron.job
        WHERE jobname = 'nplus-aviator-worker'
          AND database = current_database()
    LOOP
        PERFORM cron.unschedule(v_job_id);
    END LOOP;

    PERFORM cron.schedule(
        'nplus-aviator-worker',
        '1 seconds',
        'SELECT public.nplus_aviator_demo_worker_tick();'
    );
END
$scheduler$;

-- Supabase documents that job_run_details grows indefinitely unless cleaned.
-- Keep the most recent seven days of history while the 1-second worker runs.
DO $history_cleanup$
DECLARE
    v_job_id bigint;
BEGIN
    FOR v_job_id IN
        SELECT jobid
        FROM cron.job
        WHERE jobname = 'nplus-aviator-job-history-cleanup'
          AND database = current_database()
    LOOP
        PERFORM cron.unschedule(v_job_id);
    END LOOP;

    PERFORM cron.schedule(
        'nplus-aviator-job-history-cleanup',
        '17 3 * * *',
        'DELETE FROM cron.job_run_details WHERE end_time < now() - interval ''7 days'''
    );
END
$history_cleanup$;

COMMIT;