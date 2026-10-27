\set ON_ERROR_STOP on
-- Disposable PostgreSQL regression. Uses synthetic auth/users and a test UUID function.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;
CREATE SCHEMA auth;
CREATE SCHEMA extensions;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text);
CREATE OR REPLACE FUNCTION extensions.uuid_generate_v4()
RETURNS uuid LANGUAGE sql VOLATILE AS $$ SELECT gen_random_uuid(); $$;

\ir fixtures/replay-baseline/reconstructed-live-legacy-schema-bootstrap.sql

DO $assertions$
DECLARE v_name text;
BEGIN
  IF (SELECT count(*) FROM nplus_replay_audit.legacy_schema_bootstrap_marker
      WHERE marker='reconstructed_live_legacy_schema_2026_10_27') <> 1 THEN
    RAISE EXCEPTION 'FAIL: reconstructed baseline marker missing';
  END IF;
  IF (SELECT count(*) FROM public.manual_deposits)<>0
     OR (SELECT count(*) FROM public.user_bank_details)<>0
     OR (SELECT count(*) FROM public.withdraw_requests)<>0 THEN
    RAISE EXCEPTION 'FAIL: baseline unexpectedly created table rows';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='manual_deposits')<>6
     OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='user_bank_details')<>8
     OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='withdraw_requests')<>5 THEN
    RAISE EXCEPTION 'FAIL: column shape differs from the live snapshot';
  END IF;
  IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.manual_deposits'::regclass AND conname IN ('manual_deposits_pkey','manual_deposits_user_id_fkey'))<>2
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='public.user_bank_details'::regclass AND conname IN ('user_bank_details_pkey','user_bank_details_user_id_fkey','user_bank_details_user_id_key'))<>3
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='public.withdraw_requests'::regclass AND conname IN ('withdraw_requests_pkey','withdraw_requests_user_id_fkey'))<>2 THEN
    RAISE EXCEPTION 'FAIL: key/FK constraints differ from the live snapshot';
  END IF;
  FOREACH v_name IN ARRAY ARRAY['manual_deposits','user_bank_details','withdraw_requests'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.'||v_name))
       OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid=to_regclass('public.'||v_name))<>'postgres' THEN
      RAISE EXCEPTION 'FAIL: owner/RLS mismatch for %',v_name;
    END IF;
    IF NOT has_table_privilege('anon','public.'||v_name,'SELECT')
       OR NOT has_table_privilege('authenticated','public.'||v_name,'SELECT') THEN
      RAISE EXCEPTION 'FAIL: pre-history ACL seed mismatch for %',v_name;
    END IF;
    IF (SELECT count(*) FROM pg_policy WHERE polrelid=to_regclass('public.'||v_name))<>0 THEN
      RAISE EXCEPTION 'FAIL: later recorded migration policies should not be pre-created';
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS: reconstructed legacy schema shape, owner, RLS, ACL seed, and zero-row invariants.';
END
$assertions$;
