BEGIN;

-- Legacy RPC was SECURITY DEFINER, had no role check, and was executable by PUBLIC.
-- Disable browser access to it. Keep service-role execution only for any trusted
-- server-side compatibility calls; the app uses the audited RPC below.
REVOKE ALL ON FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.nplus_admin_adjust_demo_wallet_audit(
  p_target_user uuid,
  p_delta numeric,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  v_role text;
  v_before numeric;
  v_after numeric;
  v_note text := trim(coalesce(p_note, ''));
  v_type text;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required.';
  END IF;

  SELECT lower(coalesce(role, ''))
    INTO v_role
  FROM public.profiles
  WHERE id = v_admin_id
  FOR SHARE;

  IF coalesce(v_role, '') <> 'admin' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Admin access required.';
  END IF;

  IF p_target_user IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Target user is required.';
  END IF;

  IF p_delta IS NULL
     OR p_delta = 'Infinity'::numeric
     OR p_delta = '-Infinity'::numeric
     OR p_delta = 'NaN'::numeric
     OR p_delta = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Enter a valid non-zero adjustment.';
  END IF;

  IF char_length(v_note) < 4 OR char_length(v_note) > 180 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Reason must be between 4 and 180 characters.';
  END IF;

  SELECT balance
    INTO v_before
  FROM public.demo_wallets
  WHERE user_id = p_target_user
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target wallet not found.';
  END IF;

  v_after := v_before + p_delta;
  IF v_after < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Adjustment cannot make the virtual balance negative.';
  END IF;

  UPDATE public.demo_wallets
  SET balance = v_after,
      updated_at = clock_timestamp()
  WHERE user_id = p_target_user;

  v_type := CASE WHEN p_delta > 0 THEN 'ADMIN_DEMO_CREDIT' ELSE 'ADMIN_DEMO_DEBIT' END;

  INSERT INTO public.demo_wallet_transactions
    (user_id, delta, balance_before, balance_after, type, source, note)
  VALUES
    (p_target_user, p_delta, v_before, v_after, v_type, 'NPLUS_ADMIN', v_note);

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_target_user,
    'before', v_before,
    'after', v_after,
    'delta', p_delta,
    'type', v_type,
    'source', 'NPLUS_ADMIN'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_admin_adjust_demo_wallet_audit(uuid, numeric, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_admin_adjust_demo_wallet_audit(uuid, numeric, text)
  TO authenticated, service_role;

COMMIT;