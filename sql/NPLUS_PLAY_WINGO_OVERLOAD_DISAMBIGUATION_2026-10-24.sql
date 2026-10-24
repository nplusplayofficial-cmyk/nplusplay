-- Candidate-only fix for overlapping PostgreSQL function defaults.
-- This file is NOT a canonical migration and has NOT been applied to production.
-- Apply only after clean backup restore/replay, source review, and explicit release approval.
-- Preserve the 4-argument compatibility overload; make every argument required on the
-- 5-argument overload so 4-argument RPC calls resolve deterministically.

CREATE OR REPLACE FUNCTION public.nplus_admin_set_wingo_demo(
  p_duration integer,
  p_mode text,
  p_color text,
  p_number integer,
  p_size text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
  v_mode text := upper(trim(coalesce(p_mode, 'AUTO')));
  v_color text := upper(trim(coalesce(p_color, '')));
  v_size text := upper(trim(coalesce(p_size, '')));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT lower(coalesce(role, ''))
    INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF coalesce(v_role, '') <> 'admin' THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  IF p_duration NOT IN (30,60,180,300) THEN
    RAISE EXCEPTION 'Invalid WINGO duration.';
  END IF;

  IF v_mode NOT IN ('AUTO','MANUAL','RANDOM') THEN
    RAISE EXCEPTION 'Invalid WINGO mode.';
  END IF;

  IF v_mode = 'MANUAL' THEN
    IF v_color NOT IN ('GREEN','VIOLET','RED') THEN
      RAISE EXCEPTION 'Manual WINGO color is required.';
    END IF;

    IF p_number IS NULL OR p_number < 0 OR p_number > 9 THEN
      RAISE EXCEPTION 'Manual WINGO number must be between 0 and 9.';
    END IF;

    IF v_size NOT IN ('BIG','SMALL') THEN
      RAISE EXCEPTION 'Manual WINGO size is required.';
    END IF;
  END IF;

  INSERT INTO public.demo_game_controls (
    game_key, duration_seconds, mode, color, number, result, updated_by, updated_at
  )
  VALUES (
    'WINGO',
    p_duration,
    v_mode,
    nullif(v_color, ''),
    p_number,
    CASE
      WHEN v_mode = 'MANUAL'
        THEN v_color || ' ' || p_number::text || U&' \00B7 ' || v_size
      WHEN v_mode = 'RANDOM' THEN 'RANDOM DEMO'
      ELSE 'AUTO'
    END,
    auth.uid(),
    now()
  )
  ON CONFLICT (game_key, duration_seconds)
  DO UPDATE SET
    mode = excluded.mode,
    color = excluded.color,
    number = excluded.number,
    result = excluded.result,
    updated_by = auth.uid(),
    updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'duration', p_duration,
    'mode', v_mode,
    'color', nullif(v_color, ''),
    'number', p_number,
    'size', nullif(v_size, ''),
    'result',
      CASE
        WHEN v_mode = 'MANUAL'
          THEN v_color || ' ' || p_number::text || U&' \00B7 ' || v_size
        WHEN v_mode = 'RANDOM' THEN 'RANDOM DEMO'
        ELSE 'AUTO'
      END
  );
END;
$function$;
