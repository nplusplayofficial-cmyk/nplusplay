-- Candidate-only fix for non-finite amounts in the user-owned virtual Safe.
-- Read-only production catalog probe confirmed numeric NaN bypasses the previous
-- v_amount <= 0 and v_amount <> round(v_amount,2) checks. The previous declaration
-- cast p_amount to numeric(14,2) before validating it, which can round extra decimals.
-- Do not apply to production before canonical replay and reviewed release approval.

BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_demo_safe_transfer(
  p_direction text,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_direction text := upper(trim(coalesce(p_direction,'')));
  v_amount numeric(14,2);
  v_wallet numeric(14,2);
  v_safe numeric(14,2);
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF v_direction NOT IN ('IN','OUT') THEN
    RETURN jsonb_build_object(
      'success',false,'reason','invalid_direction',
      'message','Choose IN or OUT.'
    );
  END IF;

  -- Reject special numeric values BEFORE assigning into numeric(14,2), and
  -- validate precision against the original argument before the narrowing cast.
  IF p_amount IS NULL
     OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN
    RETURN jsonb_build_object(
      'success',false,'reason','invalid_amount',
      'message','Enter a finite positive virtual amount with at most 2 decimals.'
    );
  END IF;

  IF p_amount > 999999999999.99
     OR p_amount <= 0
     OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object(
      'success',false,'reason','invalid_amount',
      'message','Enter a finite positive virtual amount with at most 2 decimals.'
    );
  END IF;

  v_amount := p_amount;

  INSERT INTO public.nplus_demo_safe_balances(user_id,balance)
  VALUES (v_actor,0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT balance INTO v_wallet
  FROM public.demo_wallets
  WHERE user_id=v_actor
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Demo wallet not found.';
  END IF;

  SELECT balance INTO v_safe
  FROM public.nplus_demo_safe_balances
  WHERE user_id=v_actor
  FOR UPDATE;

  IF v_direction='IN' THEN
    IF v_wallet < v_amount THEN
      RETURN jsonb_build_object(
        'success',false,'reason','insufficient_wallet',
        'message','Not enough virtual wallet points.'
      );
    END IF;

    UPDATE public.demo_wallets
    SET balance=balance-v_amount,updated_at=now()
    WHERE user_id=v_actor
    RETURNING balance INTO v_wallet;

    UPDATE public.nplus_demo_safe_balances
    SET balance=balance+v_amount,updated_at=now()
    WHERE user_id=v_actor
    RETURNING balance INTO v_safe;

    INSERT INTO public.demo_wallet_transactions
      (user_id,delta,balance_before,balance_after,type,source,note)
    VALUES
      (v_actor,-v_amount,v_wallet+v_amount,v_wallet,
       'SAFE_TRANSFER','SAFE','Moved virtual points into safe');
  ELSE
    IF v_safe < v_amount THEN
      RETURN jsonb_build_object(
        'success',false,'reason','insufficient_safe',
        'message','Not enough virtual safe points.'
      );
    END IF;

    UPDATE public.nplus_demo_safe_balances
    SET balance=balance-v_amount,updated_at=now()
    WHERE user_id=v_actor
    RETURNING balance INTO v_safe;

    UPDATE public.demo_wallets
    SET balance=balance+v_amount,updated_at=now()
    WHERE user_id=v_actor
    RETURNING balance-v_amount,balance INTO v_before,v_wallet;

    INSERT INTO public.demo_wallet_transactions
      (user_id,delta,balance_before,balance_after,type,source,note)
    VALUES
      (v_actor,v_amount,v_before,v_wallet,
       'SAFE_TRANSFER','SAFE','Moved virtual points out of safe');
  END IF;

  INSERT INTO public.nplus_demo_safe_transfers
    (user_id,direction,amount,wallet_after,safe_after)
  VALUES (v_actor,v_direction,v_amount,v_wallet,v_safe);

  RETURN jsonb_build_object(
    'success',true,'direction',v_direction,'amount',v_amount,
    'wallet_balance',v_wallet,'safe_balance',v_safe,
    'message','Virtual demo points transferred successfully. No interest is calculated.'
  );
END;
$function$;

COMMIT;
