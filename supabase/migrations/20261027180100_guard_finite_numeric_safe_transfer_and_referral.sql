-- Finite numeric guard migration: safe transfer and referral amount guards.
-- This transaction replaces RPC function bodies only; it does not rewrite wallet/user rows.
BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_demo_safe_transfer(p_direction text, p_amount numeric)
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
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_direction NOT IN ('IN','OUT') THEN RETURN jsonb_build_object('success',false,'reason','invalid_direction','message','Choose IN or OUT.'); END IF;
  IF p_amount IS NULL
     OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount > 999999999999.99
     OR p_amount <= 0
     OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a finite positive virtual amount with at most 2 decimals.');
  END IF;
  v_amount := p_amount;

  INSERT INTO public.nplus_demo_safe_balances(user_id,balance) VALUES (v_actor,0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT balance INTO v_wallet FROM public.demo_wallets WHERE user_id=v_actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;
  SELECT balance INTO v_safe FROM public.nplus_demo_safe_balances WHERE user_id=v_actor FOR UPDATE;

  IF v_direction='IN' THEN
    IF v_wallet < v_amount THEN RETURN jsonb_build_object('success',false,'reason','insufficient_wallet','message','Not enough virtual wallet points.'); END IF;
    UPDATE public.demo_wallets SET balance=balance-v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_wallet;
    UPDATE public.nplus_demo_safe_balances SET balance=balance+v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_safe;
    INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
      VALUES(v_actor,-v_amount,v_wallet+v_amount,v_wallet,'SAFE_TRANSFER','SAFE','Moved virtual points into safe');
  ELSE
    IF v_safe < v_amount THEN RETURN jsonb_build_object('success',false,'reason','insufficient_safe','message','Not enough virtual safe points.'); END IF;
    UPDATE public.nplus_demo_safe_balances SET balance=balance-v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_safe;
    UPDATE public.demo_wallets SET balance=balance+v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance-v_amount,balance INTO v_before,v_wallet;
    INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
      VALUES(v_actor,v_amount,v_before,v_wallet,'SAFE_TRANSFER','SAFE','Moved virtual points out of safe');
  END IF;

  INSERT INTO public.nplus_demo_safe_transfers(user_id,direction,amount,wallet_after,safe_after)
  VALUES(v_actor,v_direction,v_amount,v_wallet,v_safe);

  RETURN jsonb_build_object('success',true,'direction',v_direction,'amount',v_amount,
    'wallet_balance',v_wallet,'safe_balance',v_safe,
    'message','Virtual demo points transferred successfully. No interest is calculated.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral(p_referred_user_id uuid, p_verified_virtual_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_referrer uuid;
  v_status text;
BEGIN
  IF NOT coalesce(public.nplus_is_admin(), false) THEN
    RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501';
  END IF;
  IF p_referred_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.');
  END IF;

  IF p_verified_virtual_amount IS NULL
     OR p_verified_virtual_amount::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_verified_amount',
      'message', 'Verified amount must be a finite numeric value.');
  END IF;

  IF p_verified_virtual_amount < 500.00 THEN
    RETURN jsonb_build_object('success', false, 'reason', 'qualification_below_minimum',
      'message', 'Verify at least 500 virtual demo points for this invited account.');
  END IF;

  SELECT user_id, status INTO v_referrer, v_status
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = p_referred_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.');
  END IF;
  IF v_status = 'qualified' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.');
  END IF;
  IF v_status <> 'pending' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_status',
      'message', 'Only a pending invitation can be verified.');
  END IF;

  INSERT INTO public.nplus_demo_referral_qualifications
    (referred_user_id, referrer_user_id, qualifying_virtual_amount, verified_by, verified_at)
  VALUES (p_referred_user_id, v_referrer, p_verified_virtual_amount, v_actor, now())
  ON CONFLICT (referred_user_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.');
  END IF;

  UPDATE public.nplus_demo_referrals
  SET status = 'qualified', reward_amount = 0, qualifying_request_id = NULL, qualified_at = now()
  WHERE referred_user_id = p_referred_user_id AND status = 'pending';

  RETURN jsonb_build_object('success', true, 'reason', 'qualified',
    'referrer_user_id', v_referrer, 'referred_user_id', p_referred_user_id,
    'verified_virtual_amount', p_verified_virtual_amount,
    'message', 'Invited account verified for the Daman-reference demo bonus tiers.');
END;
$function$;

COMMIT;
