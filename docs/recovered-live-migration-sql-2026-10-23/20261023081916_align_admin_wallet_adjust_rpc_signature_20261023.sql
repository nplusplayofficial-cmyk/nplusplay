BEGIN;

-- The production legacy function used the same SQL types but different parameter
-- names, so PostgREST could not match the current Admin UI's named arguments.
-- Recreate it with the repository's expected argument names and audited behavior.
DROP FUNCTION IF EXISTS public.nplus_admin_adjust_demo_wallet_audit(uuid, numeric, text);
DROP FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text);

CREATE FUNCTION public.nplus_admin_adjust_demo_wallet(
  p_target_user uuid,
  p_delta numeric,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  v_role text;
  v_before numeric(12,2);
  v_after numeric(12,2);
  v_delta numeric(12,2);
  v_note text := trim(coalesce(p_note, ''));
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required.';
  END IF;
  IF p_target_user IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Target user is required.';
  END IF;

  SELECT lower(coalesce(p.role, ''))
    INTO v_role
  FROM public.profiles p
  WHERE p.id = v_admin_id
  FOR SHARE;

  IF coalesce(v_role, '') <> 'admin' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Admin access required.';
  END IF;

  IF p_delta IS NULL
     OR p_delta::text IN ('Infinity', '-Infinity', 'NaN')
     OR p_delta = 0
     OR p_delta < -1000000
     OR p_delta > 1000000
     OR p_delta <> round(p_delta, 2) THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Adjustment must be between -1000000 and 1000000 credits, with at most two decimals.';
  END IF;

  IF length(v_note) < 4 OR length(v_note) > 300 THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Enter an adjustment reason between 4 and 300 characters.';
  END IF;

  SELECT w.balance
    INTO v_before
  FROM public.demo_wallets w
  WHERE w.user_id = p_target_user
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target wallet not found.';
  END IF;

  v_delta := p_delta;
  v_after := v_before + v_delta;
  IF v_after < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Adjustment would make the virtual balance negative.';
  END IF;

  UPDATE public.demo_wallets
  SET balance = v_after,
      updated_at = clock_timestamp()
  WHERE user_id = p_target_user;

  INSERT INTO public.demo_wallet_transactions
    (user_id, delta, balance_before, balance_after, type, source, note)
  VALUES
    (p_target_user, v_delta, v_before, v_after, 'ADMIN_ADJUSTMENT', 'NPLUS_ADMIN', v_note);

  RETURN jsonb_build_object(
    'success', true,
    'target_user', p_target_user,
    'before', v_before,
    'after', v_after,
    'delta', v_delta,
    'note', v_note
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text)
  TO authenticated, service_role;

COMMIT;