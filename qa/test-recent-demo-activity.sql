\set ON_ERROR_STOP on

-- Dedicated disposable PostgreSQL database only.
-- This tests the candidate SQL source, not any live Supabase endpoint.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$roles$;

CREATE TABLE public.nplus_wingo_demo_bets (created_at timestamptz NOT NULL);
CREATE TABLE public.nplus_moto_demo_bets (created_at timestamptz NOT NULL);
CREATE TABLE public.nplus_aviator_demo_bets (created_at timestamptz NOT NULL);

\ir ../sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql

INSERT INTO public.nplus_wingo_demo_bets(created_at) VALUES
  (statement_timestamp() - interval '1 minute'),
  (statement_timestamp() - interval '3 minutes'),
  (statement_timestamp() - interval '20 hours');
INSERT INTO public.nplus_moto_demo_bets(created_at)
VALUES (statement_timestamp() - interval '8 minutes');
INSERT INTO public.nplus_aviator_demo_bets(created_at)
VALUES (statement_timestamp() - interval '48 hours');

DO $contract$
DECLARE
  v_count bigint;
  v_result_type text;
  v_definition text;
  v_is_definer boolean;
  v_config text[];
BEGIN
  SELECT pg_get_function_result('public.nplus_recent_demo_activity(integer)'::regprocedure)
    INTO v_result_type;
  IF v_result_type <> 'TABLE(game_key text, activity_count bigint)' THEN
    RAISE EXCEPTION 'FAIL: public activity RPC must expose only game_key and activity_count; got %', v_result_type;
  END IF;

  SELECT p.prosecdef, p.proconfig, pg_get_functiondef(p.oid)
    INTO v_is_definer, v_config, v_definition
  FROM pg_proc p
  WHERE p.oid='public.nplus_recent_demo_activity(integer)'::regprocedure;

  IF v_is_definer IS DISTINCT FROM true
     OR NOT ('search_path=pg_catalog, public' = ANY(coalesce(v_config, ARRAY[]::text[]))) THEN
    RAISE EXCEPTION 'FAIL: aggregate RPC must be SECURITY DEFINER with a fixed search_path.';
  END IF;

  IF position('user_id' IN lower(v_definition)) > 0
     OR position('stake' IN lower(v_definition)) > 0
     OR position('payout' IN lower(v_definition)) > 0
     OR position('selection' IN lower(v_definition)) > 0 THEN
    RAISE EXCEPTION 'FAIL: aggregate RPC definition contains user/game-level fields.';
  END IF;

  IF NOT has_function_privilege('anon','public.nplus_recent_demo_activity(integer)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_recent_demo_activity(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: expected public feed execute grants are missing.';
  END IF;

  SELECT coalesce(sum(activity_count),0) INTO v_count
  FROM public.nplus_recent_demo_activity(0);
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: zero-minute input was not clamped to 5 minutes; expected 2, got %', v_count;
  END IF;

  SELECT coalesce(sum(activity_count),0) INTO v_count
  FROM public.nplus_recent_demo_activity(60);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FAIL: 60-minute activity window expected 3 events, got %', v_count;
  END IF;

  SELECT coalesce(sum(activity_count),0) INTO v_count
  FROM public.nplus_recent_demo_activity(100000);
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'FAIL: long window was not capped at 1440 minutes; expected 4 events, got %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.nplus_recent_demo_activity(60)
    WHERE game_key NOT IN ('WINGO','MOTORACE','AVIATOR')
       OR activity_count <= 0
  ) THEN
    RAISE EXCEPTION 'FAIL: aggregate RPC returned an unexpected key or non-positive count.';
  END IF;

  RAISE NOTICE 'PASS: activity RPC exposes only game_key/count, not user identifiers or bet details.';
  RAISE NOTICE 'PASS: fixed search_path, SECURITY DEFINER and intended anon/authenticated execute grants.';
  RAISE NOTICE 'PASS: 5-minute minimum, normal window and 1440-minute maximum are enforced.';
END
$contract$;

SET ROLE anon;
DO $anon_call$
DECLARE
  v_count bigint;
BEGIN
  SELECT coalesce(sum(activity_count),0) INTO v_count
  FROM public.nplus_recent_demo_activity(60);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FAIL: anon aggregate RPC call returned unexpected count %', v_count;
  END IF;
END
$anon_call$;
RESET ROLE;

DROP FUNCTION public.nplus_recent_demo_activity(integer);
DROP TABLE public.nplus_wingo_demo_bets;
DROP TABLE public.nplus_moto_demo_bets;
DROP TABLE public.nplus_aviator_demo_bets;
SELECT 'PASS: Recent Activity public aggregate privacy regression' AS result;
