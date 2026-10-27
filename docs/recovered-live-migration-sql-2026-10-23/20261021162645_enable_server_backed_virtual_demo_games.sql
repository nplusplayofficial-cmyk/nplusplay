BEGIN;
DO $enable_demo_games$
DECLARE
  v_admin uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_admin
  FROM public.profiles
  WHERE lower(coalesce(role,''))='admin'
  ORDER BY id
  LIMIT 1;

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'No Admin profile available; refusing to enable demo games.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.nplus_set_game_status('WINGO', true);
  IF coalesce((v_result->>'enabled')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'WINGO was not enabled.';
  END IF;

  v_result := public.nplus_set_game_status('MOTO', true);
  IF coalesce((v_result->>'enabled')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'MotoRace was not enabled.';
  END IF;

  v_result := public.nplus_set_game_status('AVIATOR', true);
  IF coalesce((v_result->>'enabled')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Aviator was not enabled.';
  END IF;
END
$enable_demo_games$;
COMMIT;