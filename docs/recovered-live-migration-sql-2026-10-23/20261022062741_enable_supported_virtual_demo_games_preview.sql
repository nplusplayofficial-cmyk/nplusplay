BEGIN;

DO $preflight$
DECLARE
  v_expected_games integer;
BEGIN
  IF to_regclass('public.game_settings') IS NULL
     OR to_regclass('public.demo_wallets') IS NULL
     OR to_regclass('public.demo_wallet_transactions') IS NULL
     OR to_regclass('public.nplus_wingo_demo_rounds') IS NULL
     OR to_regclass('public.nplus_wingo_demo_bets') IS NULL
     OR to_regclass('public.nplus_moto_demo_rounds') IS NULL
     OR to_regclass('public.nplus_moto_demo_bets') IS NULL
     OR to_regclass('public.nplus_aviator_demo_rounds') IS NULL
     OR to_regclass('public.nplus_aviator_demo_bets') IS NULL
     OR to_regclass('public.nplus_aviator_worker_health') IS NULL THEN
    RAISE EXCEPTION 'Required server-side demo game schema is missing; no games enabled.';
  END IF;

  IF to_regprocedure('public.nplus_wingo_demo_current_round(integer)') IS NULL
     OR to_regprocedure('public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)') IS NULL
     OR to_regprocedure('public.nplus_wingo_demo_settle_round(integer,bigint)') IS NULL
     OR to_regprocedure('public.nplus_moto_demo_current_round()') IS NULL
     OR to_regprocedure('public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)') IS NULL
     OR to_regprocedure('public.nplus_moto_demo_settle_round(bigint)') IS NULL
     OR to_regprocedure('public.nplus_aviator_demo_current_round()') IS NULL
     OR to_regprocedure('public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)') IS NULL
     OR to_regprocedure('public.nplus_aviator_demo_cashout(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Required authenticated server RPC is missing; no games enabled.';
  END IF;

  IF has_function_privilege('anon','public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)','EXECUTE') THEN
    RAISE EXCEPTION 'Game RPC least-privilege grants failed; no games enabled.';
  END IF;

  IF has_function_privilege('anon','public.nplus_phone_is_registered(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.nplus_phone_is_registered(text)','EXECUTE') THEN
    RAISE EXCEPTION 'Phone enumeration privileges are still present; no games enabled.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM cron.job j
    JOIN LATERAL (
      SELECT max(d.end_time) AS last_success
      FROM cron.job_run_details d
      WHERE d.jobid = j.jobid AND d.status = 'succeeded'
    ) r ON true
    WHERE j.jobname = 'nplus-aviator-worker'
      AND j.active
      AND r.last_success > clock_timestamp() - interval '15 seconds'
  ) THEN
    RAISE EXCEPTION 'Aviator worker is not recently succeeding; no games enabled.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname = 'nplus-aviator-job-history-cleanup' AND active
  ) THEN
    RAISE EXCEPTION 'Aviator cron history cleanup is not active; no games enabled.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.game_settings
    WHERE game_key IN ('WINGO','MOTO','AVIATOR')
  ) OR (SELECT count(*) FROM public.game_settings WHERE game_key IN ('WINGO','MOTO','AVIATOR')) <> 3 THEN
    RAISE EXCEPTION 'Expected three supported demo game settings; no games enabled.';
  END IF;
END
$preflight$;

UPDATE public.game_settings
SET enabled = CASE
  WHEN game_key IN ('WINGO','MOTO','AVIATOR') THEN true
  ELSE false
END,
updated_at = clock_timestamp()
WHERE game_key IN ('WINGO','MOTO','AVIATOR','K3','5D','TRX');

DO $verify$
DECLARE
  v_rows integer;
  v_enabled integer;
  v_hard_paused integer;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE enabled AND game_key IN ('WINGO','MOTO','AVIATOR')),
         count(*) FILTER (WHERE NOT enabled AND game_key IN ('K3','5D','TRX'))
    INTO v_rows, v_enabled, v_hard_paused
  FROM public.game_settings
  WHERE game_key IN ('WINGO','MOTO','AVIATOR','K3','5D','TRX');

  IF v_rows <> 6 OR v_enabled <> 3 OR v_hard_paused <> 3 THEN
    RAISE EXCEPTION 'Final game-toggle assertion failed; rollback.';
  END IF;
END
$verify$;

COMMIT;