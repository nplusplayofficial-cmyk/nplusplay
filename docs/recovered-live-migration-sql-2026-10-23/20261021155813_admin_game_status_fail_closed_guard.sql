BEGIN;
CREATE OR REPLACE FUNCTION public.nplus_set_game_status(p_game_key text, p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text;
  v_key text := upper(trim(coalesce(p_game_key, '')));
  v_name text;
  v_worker_scheduled boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT lower(coalesce(p.role, ''))
    INTO v_role
  FROM public.profiles AS p
  WHERE p.id = v_user_id;

  IF coalesce(v_role, '') <> 'admin' THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  IF p_enabled IS NULL THEN
    RAISE EXCEPTION 'Enabled status must be true or false.';
  END IF;

  IF v_key NOT IN ('WINGO', 'K3', '5D', 'TRX', 'AVIATOR', 'MOTO') THEN
    RAISE EXCEPTION 'Invalid game.';
  END IF;

  IF v_key IN ('K3', '5D', 'TRX') AND p_enabled THEN
    RAISE EXCEPTION 'Payout rules pending; this game cannot be enabled.';
  END IF;

  IF p_enabled AND v_key = 'WINGO' AND (
    to_regclass('public.nplus_wingo_demo_rounds') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_current_round(integer)') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_settle_round(integer,bigint)') IS NULL
  ) THEN
    RAISE EXCEPTION 'WINGO server settlement is not installed.';
  END IF;

  IF p_enabled AND v_key = 'MOTO' AND (
    to_regclass('public.nplus_moto_demo_rounds') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_current_round()') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_settle_round(bigint)') IS NULL
  ) THEN
    RAISE EXCEPTION 'MotoRace server settlement is not installed.';
  END IF;

  IF p_enabled AND v_key = 'AVIATOR' AND (
    to_regclass('public.nplus_aviator_demo_rounds') IS NULL
    OR to_regclass('public.nplus_aviator_worker_health') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_current_round()') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NULL
  ) THEN
    RAISE EXCEPTION 'Aviator server settlement and worker are not installed.';
  END IF;

  IF p_enabled AND v_key = 'AVIATOR' THEN
    IF to_regclass('cron.job') IS NULL THEN
      RAISE EXCEPTION 'Aviator scheduler is not installed.';
    END IF;

    EXECUTE
      'SELECT EXISTS (
         SELECT 1 FROM cron.job
         WHERE jobname = $1
           AND database = current_database()
           AND active
       )'
      INTO v_worker_scheduled
      USING 'nplus-aviator-worker';

    IF NOT v_worker_scheduled THEN
      RAISE EXCEPTION 'Aviator scheduler is not active.';
    END IF;
  END IF;

  UPDATE public.game_settings
  SET enabled = p_enabled,
      updated_at = clock_timestamp(),
      updated_by = v_user_id
  WHERE game_key = v_key
  RETURNING game_name INTO v_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Game setting not found.';
  END IF;

  RETURN jsonb_build_object(
    'game_key', v_key,
    'game_name', v_name,
    'enabled', p_enabled,
    'updated_by', v_user_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_set_game_status(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_set_game_status(text, boolean) TO authenticated, service_role;
COMMIT;