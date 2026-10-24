-- Read-only release invariants after replaying the 40 captured migration bodies
-- on a separate disposable copy of the 2026-10-15 backup.
-- This file must NEVER be run against Supabase production.
\set ON_ERROR_STOP on

DO $assertions$
DECLARE
  v_count bigint;
  v_body text;
  v_result text;
BEGIN
  IF (SELECT count(*) FROM public.game_settings
      WHERE upper(game_key) IN ('WINGO','K3','5D','TRX','MOTO','AVIATOR')) <> 6 THEN
    RAISE EXCEPTION 'Replay invariant failed: six expected game-setting keys are not present.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.game_settings
    WHERE upper(game_key) IN ('WINGO','K3','5D','TRX','MOTO','AVIATOR')
      AND enabled IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Replay invariant failed: one or more of the six game keys are not disabled.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relkind IN ('r','p')
      AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Replay invariant failed: one or more public tables/partitions have RLS disabled.';
  END IF;

  IF has_table_privilege('anon','public.demo_wallets','INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.demo_wallets','INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon','public.demo_wallet_transactions','INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.demo_wallet_transactions','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Replay invariant failed: browser roles retain direct wallet/ledger write privileges.';
  END IF;

  IF has_table_privilege('anon','public.deposit_requests','INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.deposit_requests','UPDATE,DELETE')
     OR has_table_privilege('anon','public.withdrawal_requests','INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.withdrawal_requests','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Replay invariant failed: request-table direct-write grants differ from the audited contract.';
  END IF;

  IF has_function_privilege('anon','public.nplus_phone_is_registered(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.nplus_phone_is_registered(text)','EXECUTE') THEN
    RAISE EXCEPTION 'Replay invariant failed: browser roles can execute phone-enumeration RPC.';
  END IF;

  IF to_regprocedure('public.nplus_wallet_change(numeric,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Replay invariant failed: generic wallet RPC is missing.';
  END IF;
  v_body := pg_get_functiondef('public.nplus_wallet_change(numeric,text,text,text)'::regprocedure);
  IF position('Generic wallet credits are disabled' in v_body)=0
     OR position('Game wallet changes must use the server-authoritative game RPC' in v_body)=0 THEN
    RAISE EXCEPTION 'Replay invariant failed: generic positive/game wallet-credit guard is missing.';
  END IF;

  IF to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NULL THEN
    RAISE EXCEPTION 'Replay invariant failed: Aviator worker-tick function is missing.';
  END IF;
  IF has_function_privilege('anon','public.nplus_aviator_demo_worker_tick()','EXECUTE')
     OR has_function_privilege('authenticated','public.nplus_aviator_demo_worker_tick()','EXECUTE') THEN
    RAISE EXCEPTION 'Replay invariant failed: browser roles can execute the privileged Aviator worker.';
  END IF;

  IF to_regclass('cron.job') IS NULL OR NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname='nplus-aviator-worker'
      AND database=current_database()
      AND active
      AND schedule='1 seconds'
      AND position('nplus_aviator_demo_worker_tick' in command)>0
  ) THEN
    RAISE EXCEPTION 'Replay invariant failed: expected active local Aviator cron job was not created.';
  END IF;

  IF (SELECT count(*) FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public'
        AND p.proname='nplus_admin_set_wingo_demo'
        AND p.pronargs IN (4,5)
        AND position('Admin access required.' in pg_get_functiondef(p.oid))>0) <> 2 THEN
    RAISE EXCEPTION 'Replay invariant failed: the expected authenticated Admin checks are missing from one or both WINGO overloads.';
  END IF;

  IF to_regprocedure('public.nplus_recent_demo_activity(integer)') IS NULL THEN
    RAISE EXCEPTION 'Replay invariant failed: aggregate recent activity RPC is missing.';
  END IF;
  SELECT pg_get_function_result(p.oid)
    INTO v_result
  FROM pg_proc p
  WHERE p.oid='public.nplus_recent_demo_activity(integer)'::regprocedure;
  IF v_result <> 'TABLE(game_key text, activity_count bigint)'
     OR NOT has_function_privilege('anon','public.nplus_recent_demo_activity(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'Replay invariant failed: recent activity RPC output/grants do not match the aggregate-only contract.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.demo_wallet_transactions
  WHERE balance_before + delta IS DISTINCT FROM balance_after;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Replay invariant failed: % ledger arithmetic mismatch(es).', v_count;
  END IF;

  RAISE NOTICE 'PASS: all six games remain disabled.';
  RAISE NOTICE 'PASS: public tables have RLS enabled; browser roles cannot directly write wallet/ledger/request tables.';
  RAISE NOTICE 'PASS: phone-enumeration RPC is not executable by browser roles.';
  RAISE NOTICE 'PASS: generic wallet positive/game-credit guard exists.';
  RAISE NOTICE 'PASS: Aviator worker function is server-only and expected local cron job is installed.';
  RAISE NOTICE 'PASS: both WINGO Admin overloads include explicit Admin authorization.';
  RAISE NOTICE 'PASS: recent activity RPC exposes only aggregate counts under the reviewed contract.';
  RAISE NOTICE 'PASS: wallet ledger arithmetic remains consistent.';
END
$assertions$;

-- Print object counts for comparison with the read-only production snapshot.
-- Count differences are evidence to investigate; do not auto-create or drop objects.
SELECT 'public_tables' AS metric,
       count(*)::text AS value
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p')
UNION ALL
SELECT 'public_rls_enabled_tables', count(*)::text
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity
UNION ALL
SELECT 'public_functions', count(*)::text
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
UNION ALL
SELECT 'public_security_definer_functions', count(*)::text
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
UNION ALL
SELECT 'public_rls_policies', count(*)::text
FROM pg_policies WHERE schemaname='public'
UNION ALL
SELECT 'wallet_ledger_rows', count(*)::text FROM public.demo_wallet_transactions
UNION ALL
SELECT 'wallet_rows', count(*)::text FROM public.demo_wallets
UNION ALL
SELECT 'profile_rows', count(*)::text FROM public.profiles
UNION ALL
SELECT 'game_settings_disabled', count(*)::text FROM public.game_settings
WHERE upper(game_key) IN ('WINGO','K3','5D','TRX','MOTO','AVIATOR') AND enabled=false
ORDER BY metric;
