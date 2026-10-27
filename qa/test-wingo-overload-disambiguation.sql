\set ON_ERROR_STOP on

-- Fresh disposable PostgreSQL only. This reproduces both existing live-shaped
-- overloads before applying the candidate: both have defaults that overlap at
-- four arguments. Nothing in this test connects to production.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $auth_uid$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$auth_uid$;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,
  role text NOT NULL
);
CREATE TABLE public.demo_game_controls (
  game_key text NOT NULL,
  duration_seconds integer NOT NULL,
  mode text NOT NULL,
  color text,
  number integer,
  result text,
  updated_by uuid,
  updated_at timestamptz,
  UNIQUE (game_key, duration_seconds)
);

-- Existing 4-argument compatibility overload with two defaults.
CREATE FUNCTION public.nplus_admin_set_wingo_demo(
  p_duration integer,
  p_mode text,
  p_color text DEFAULT NULL,
  p_number integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $four$
  SELECT jsonb_build_object('overload','four','duration',p_duration,'mode',p_mode)
$four$;

-- Existing 5-argument overload from the audited live shape: the last three
-- parameters have defaults too, making a 4-argument invocation ambiguous.
CREATE FUNCTION public.nplus_admin_set_wingo_demo(
  p_duration integer,
  p_mode text,
  p_color text DEFAULT NULL,
  p_number integer DEFAULT NULL,
  p_size text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $five_old$
  SELECT jsonb_build_object('overload','five-old','duration',p_duration,'mode',p_mode)
$five_old$;

DO $precondition$
DECLARE
  v_ambiguous boolean := false;
BEGIN
  IF (SELECT pronargdefaults FROM pg_proc
      WHERE oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'::regprocedure)
      IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: fixture does not reproduce three defaults on the existing five-argument overload';
  END IF;

  BEGIN
    EXECUTE 'SELECT public.nplus_admin_set_wingo_demo(30, ''AUTO'', NULL, NULL)';
  EXCEPTION
    WHEN ambiguous_function THEN v_ambiguous := true;
  END;

  IF NOT v_ambiguous THEN
    RAISE EXCEPTION 'FAIL: baseline fixture did not reproduce the four-argument overload ambiguity';
  END IF;

  RAISE NOTICE 'PASS: baseline fixture reproduces four-argument ambiguity before the candidate patch.';
END
$precondition$;

CREATE TEMP TABLE test_expected_wingo_owner ON COMMIT PRESERVE ROWS AS
SELECT r.rolname AS owner_name
FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
WHERE p.oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'::regprocedure;

INSERT INTO public.profiles(id,role) VALUES
  ('11111111-1111-4111-8111-111111111111','admin'),
  ('22222222-2222-4222-8222-222222222222','user');

\ir ../supabase/migrations/20261027140000_fix_wingo_admin_overload_defaults.sql

DO $shape$
BEGIN
  IF (SELECT pronargdefaults FROM pg_proc
      WHERE oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer)'::regprocedure)
      IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'FAIL: four-argument compatibility overload defaults changed';
  END IF;
  IF (SELECT pronargdefaults FROM pg_proc
      WHERE oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'::regprocedure)
      IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FAIL: five-argument overload still has defaults';
  END IF;

  IF has_function_privilege('anon','public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon retained execute privilege on the recreated five-argument Admin RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: intended authenticated/service_role execute grants were not restored';
  END IF;

  IF (SELECT r.rolname FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
      WHERE p.oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'::regprocedure)
     IS DISTINCT FROM (SELECT owner_name FROM test_expected_wingo_owner) THEN
    RAISE EXCEPTION 'FAIL: original five-argument function owner was not preserved';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid='public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'::regprocedure
      AND prosecdef
      AND 'search_path=public' = ANY(coalesce(proconfig, ARRAY[]::text[]))
  ) THEN
    RAISE EXCEPTION 'FAIL: recreated five-argument RPC is not SECURITY DEFINER with fixed search_path';
  END IF;
END
$shape$;

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

DO $resolution$
DECLARE
  v_four jsonb;
  v_five jsonb;
BEGIN
  v_four := public.nplus_admin_set_wingo_demo(30,'AUTO',NULL,NULL);
  IF v_four->>'overload' IS DISTINCT FROM 'four' THEN
    RAISE EXCEPTION 'FAIL: four-argument call did not resolve to compatibility overload';
  END IF;

  v_five := public.nplus_admin_set_wingo_demo(60,'MANUAL','GREEN',5,'BIG');
  IF coalesce((v_five->>'success')::boolean,false) IS NOT TRUE
     OR v_five->>'size' IS DISTINCT FROM 'BIG' THEN
    RAISE EXCEPTION 'FAIL: five-argument call did not resolve to strict overload';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.demo_game_controls
    WHERE game_key='WINGO' AND duration_seconds=60
      AND mode='MANUAL' AND color='GREEN' AND number=5
      AND result LIKE '%BIG'
  ) THEN
    RAISE EXCEPTION 'FAIL: five-argument overload did not persist the manual control fixture';
  END IF;

  RAISE NOTICE 'PASS: four-argument and five-argument calls resolve deterministically.';
END
$resolution$;

SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);

DO $authorization$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.nplus_admin_set_wingo_demo(60,'AUTO',NULL,NULL,'');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Admin access required.' THEN
      v_denied := true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FAIL: non-admin five-argument call was not denied';
  END IF;
  RAISE NOTICE 'PASS: non-admin is denied by the five-argument overload.';
END
$authorization$;

SELECT 'PASS: WINGO overload disambiguation candidate' AS result;
