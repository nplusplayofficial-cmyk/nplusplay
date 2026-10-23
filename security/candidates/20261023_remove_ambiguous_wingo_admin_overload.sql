-- SECURITY CANDIDATE ONLY — NOT A PRODUCTION MIGRATION.
-- Keep outside supabase/migrations until Work #1 migration source/replay review passes.
-- The live 4-arg and 5-arg overloads overlap because every trailing parameter has a
-- default. Four-argument invocation currently fails with PostgreSQL 42725 ambiguity.
-- Current Admin page supplies p_size and uses the 5-arg function.
-- Do NOT use CASCADE; an unexpected dependency should stop the migration.

BEGIN;

DO $preflight$
BEGIN
  IF to_regprocedure(
    'public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Expected 5-argument WINGO admin RPC is missing; abort cleanup';
  END IF;
END
$preflight$;

DROP FUNCTION IF EXISTS public.nplus_admin_set_wingo_demo(integer,text,text,integer);

DO $postflight$
BEGIN
  IF to_regprocedure(
    'public.nplus_admin_set_wingo_demo(integer,text,text,integer)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'Ambiguous 4-argument WINGO overload still exists';
  END IF;

  IF to_regprocedure(
    'public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)'
  ) IS NULL THEN
    RAISE EXCEPTION '5-argument WINGO admin RPC unexpectedly disappeared';
  END IF;
END
$postflight$;

COMMIT;

-- Required staging regression:
-- 1. Current Admin Reports page's 5-argument call still succeeds for admin.
-- 2. Same call is denied for a non-admin and for a JWT without a matching profile.
-- 3. Four-argument calls no longer fail with 42725; they resolve to the 5-arg overload
--    with p_size defaulted. MANUAL mode must still fail safely if p_size is omitted.
-- 4. No wallet balances, transactions, or game_settings are changed by the migration.
