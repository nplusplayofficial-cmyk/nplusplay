-- QA-ONLY RECONSTRUCTED PRE-HISTORY BASELINE.
-- NEVER RUN AGAINST PRODUCTION.
-- Derived from a read-only live catalog snapshot captured 2026-10-27.
-- This is NOT original historical DDL and does NOT prove table-creation provenance.
-- It creates only empty schema shapes on a disposable restored-backup clone so the
-- 40 captured historical migration bodies can be replayed without inventing row data.
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
DECLARE v_relation text;
BEGIN
  IF current_database() !~ '^nplus_migration_replay_[0-9]{8}$' THEN
    RAISE EXCEPTION 'Reconstructed legacy baseline refused outside nplus_migration_replay_YYYYMMDD.';
  END IF;
  IF to_regclass('auth.users') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regprocedure('extensions.uuid_generate_v4()') IS NULL THEN
    RAISE EXCEPTION 'Reconstructed baseline refused: auth.users/profiles/UUID dependencies are missing.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='role'
  ) THEN
    RAISE EXCEPTION 'Reconstructed baseline refused: public.profiles.role is missing.';
  END IF;
  FOREACH v_relation IN ARRAY ARRAY['manual_deposits','user_bank_details','withdraw_requests'] LOOP
    IF to_regclass('public.' || v_relation) IS NOT NULL THEN
      RAISE EXCEPTION 'Reconstructed baseline refused: public.% already exists; nothing was changed.', v_relation;
    END IF;
  END LOOP;
  IF to_regnamespace('nplus_replay_audit') IS NOT NULL THEN
    RAISE EXCEPTION 'Reconstructed baseline refused: replay audit schema already exists.';
  END IF;
END
$guard$;

CREATE SCHEMA nplus_replay_audit;
ALTER SCHEMA nplus_replay_audit OWNER TO postgres;
CREATE TABLE nplus_replay_audit.legacy_schema_bootstrap_marker (
  marker text PRIMARY KEY,
  schema_snapshot_date date NOT NULL DEFAULT DATE '2026-10-27',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE nplus_replay_audit.legacy_schema_bootstrap_marker OWNER TO postgres;
INSERT INTO nplus_replay_audit.legacy_schema_bootstrap_marker(marker)
VALUES ('reconstructed_live_legacy_schema_2026_10_27');

-- Indexes/policies subsequently created/replaced by recorded migration body
-- 20261023092858 are intentionally left to that body.
CREATE TABLE public.manual_deposits (
  id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL,
  amount numeric NOT NULL,
  utr text NOT NULL,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT manual_deposits_pkey PRIMARY KEY (id),
  CONSTRAINT manual_deposits_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.manual_deposits OWNER TO postgres;
ALTER TABLE public.manual_deposits ENABLE ROW LEVEL SECURITY;
GRANT ALL PRIVILEGES ON TABLE public.manual_deposits TO anon, authenticated, postgres, service_role;

CREATE TABLE public.user_bank_details (
  id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL,
  account_holder text,
  account_number text,
  ifsc_code text,
  bank_name text,
  upi_id text,
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT user_bank_details_pkey PRIMARY KEY (id),
  CONSTRAINT user_bank_details_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_bank_details_user_id_key UNIQUE (user_id)
);
ALTER TABLE public.user_bank_details OWNER TO postgres;
ALTER TABLE public.user_bank_details ENABLE ROW LEVEL SECURITY;
GRANT ALL PRIVILEGES ON TABLE public.user_bank_details TO anon, authenticated, postgres, service_role;

CREATE TABLE public.withdraw_requests (
  id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL,
  amount numeric NOT NULL,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT withdraw_requests_pkey PRIMARY KEY (id),
  CONSTRAINT withdraw_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.withdraw_requests OWNER TO postgres;
ALTER TABLE public.withdraw_requests ENABLE ROW LEVEL SECURITY;
GRANT ALL PRIVILEGES ON TABLE public.withdraw_requests TO anon, authenticated, postgres, service_role;

COMMIT;

DO $verify$
DECLARE v_table text; v_rows bigint;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['manual_deposits','user_bank_details','withdraw_requests'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.' || v_table))
       OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid=to_regclass('public.' || v_table)) <> 'postgres'
       OR has_table_privilege('anon','public.' || v_table,'SELECT') IS FALSE
       OR has_table_privilege('authenticated','public.' || v_table,'SELECT') IS FALSE
       OR (SELECT count(*) FROM pg_policy WHERE polrelid=to_regclass('public.' || v_table)) <> 0 THEN
      RAISE EXCEPTION 'Reconstructed legacy baseline verification failed for public.%.', v_table;
    END IF;
    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_rows;
    IF v_rows <> 0 THEN
      RAISE EXCEPTION 'Reconstructed baseline must contain zero rows in public.%.', v_table;
    END IF;
  END LOOP;
END
$verify$;
