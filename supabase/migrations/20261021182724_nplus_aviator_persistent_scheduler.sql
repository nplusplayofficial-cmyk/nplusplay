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

COMMIT;