-- QA-ONLY FIXTURE. NEVER RUN THIS FILE AGAINST PRODUCTION.
-- This is not a canonical migration and contains NO production user rows.
-- Read-only catalog review (2026-10-27) found public.manual_deposits in the
-- current live database (owner postgres, RLS enabled, six columns, PK/FK),
-- but absent from the restored 2026-10-15 backup-derived replay baseline.
-- None of the 40 captured migration bodies creates this table; version
-- 20261023092858 only references it. Therefore strict clean replay remains
-- blocked by historical baseline/schema drift.
--
-- This fixture creates the minimal empty table shape needed to rehearse only
-- versions 39-40 in the already-partial LOCAL replay database. It does NOT
-- prove a clean 40-row replay or reconstruct the table's previous policy state.
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
DECLARE
  v_relation text;
BEGIN
  IF current_database() <> 'nplus_migration_replay_20261026' THEN
    RAISE EXCEPTION 'QA overlay refused outside nplus_migration_replay_20261026.';
  END IF;
  IF current_setting('cron.database_name') <> current_database() THEN
    RAISE EXCEPTION 'QA overlay refused: local pg_cron database does not match replay DB.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'QA overlay refused: replay database pg_cron setup is not ready.';
  END IF;
  IF to_regclass('public.nplus_aviator_worker_health') IS NULL
     OR to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NULL THEN
    RAISE EXCEPTION 'QA overlay refused: expected versions 1-38 are not present.';
  END IF;
  IF to_regclass('public.manual_deposits') IS NOT NULL THEN
    RAISE EXCEPTION 'QA overlay refused: public.manual_deposits already exists.';
  END IF;
  IF to_regnamespace('nplus_replay_audit') IS NOT NULL THEN
    RAISE EXCEPTION 'QA overlay refused: replay-audit marker schema already exists.';
  END IF;
  IF to_regprocedure('extensions.uuid_generate_v4()') IS NULL
     OR to_regclass('auth.users') IS NULL
     OR to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'QA overlay refused: required auth/UUID dependencies are missing.';
  END IF;

  FOREACH v_relation IN ARRAY ARRAY[
    'nplus_demo_gift_claims',
    'nplus_demo_gift_codes',
    'nplus_demo_referral_bonus_claims',
    'nplus_demo_referral_qualifications',
    'nplus_demo_support_requests',
    'withdraw_requests',
    'withdrawal_requests',
    'user_bank_details',
    'user_preferences'
  ] LOOP
    IF to_regclass('public.' || v_relation) IS NULL THEN
      RAISE EXCEPTION 'QA overlay refused: expected relation public.% is missing.', v_relation;
    END IF;
  END LOOP;
END
$guard$;

CREATE SCHEMA nplus_replay_audit;
CREATE TABLE nplus_replay_audit.manual_deposits_overlay_marker (
  marker text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO nplus_replay_audit.manual_deposits_overlay_marker(marker)
VALUES ('manual_deposits_schema_overlay');

CREATE TABLE public.manual_deposits (
  id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL,
  amount numeric NOT NULL,
  utr text NOT NULL,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT manual_deposits_pkey PRIMARY KEY (id),
  CONSTRAINT manual_deposits_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id)
);

ALTER TABLE public.manual_deposits OWNER TO postgres;
ALTER TABLE public.manual_deposits ENABLE ROW LEVEL SECURITY;

-- Reproduce observed table-level ACLs only on this empty disposable fixture.
-- Current production grants on this legacy table need separate least-privilege
-- review (PR #20); this QA fixture must never be deployed.
GRANT ALL PRIVILEGES ON TABLE public.manual_deposits
  TO anon, authenticated, postgres, service_role;

COMMIT;

SELECT current_database() AS local_database,
       'empty schema-only manual_deposits overlay created' AS result,
       (SELECT count(*) FROM public.manual_deposits) AS copied_user_rows;
