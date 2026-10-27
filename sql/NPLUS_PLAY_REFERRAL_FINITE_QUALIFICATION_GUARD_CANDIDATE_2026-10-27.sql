-- Candidate-only input validation for the Admin-verified demo referral qualification RPC.
-- Production catalog review on 2026-10-27 confirmed numeric NaN compares >= 500 and fits
-- numeric(14,2), so the existing threshold-only check can accept a malformed amount.
-- This CREATE OR REPLACE keeps the existing function identity/owner/ACL; it changes no
-- rows, grants, game flags, wallet balances, or migration history.
-- NOT a canonical migration. Do not apply to production before canonical replay and review.

BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral(
  p_referred_user_id uuid,
  p_verified_virtual_amount numeric
)
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
    RETURN jsonb_build_object(
      'success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.'
    );
  END IF;

  -- PostgreSQL numeric NaN sorts above ordinary numbers; -Infinity and Infinity are
  -- special numeric values too. Reject all three before threshold comparison or writes.
  IF p_verified_virtual_amount IS NULL
     OR p_verified_virtual_amount::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'invalid_verified_amount',
      'message', 'Verified amount must be a finite numeric value.'
    );
  END IF;

  IF p_verified_virtual_amount < 500.00 THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'qualification_below_minimum',
      'message', 'Verify at least 500 virtual demo points for this invited account.'
    );
  END IF;

  SELECT user_id, status
    INTO v_referrer, v_status
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = p_referred_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.'
    );
  END IF;

  IF v_status = 'qualified' THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.'
    );
  END IF;

  IF v_status <> 'pending' THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'invalid_status',
      'message', 'Only a pending invitation can be verified.'
    );
  END IF;

  INSERT INTO public.nplus_demo_referral_qualifications
    (referred_user_id, referrer_user_id, qualifying_virtual_amount, verified_by, verified_at)
  VALUES
    (p_referred_user_id, v_referrer, p_verified_virtual_amount, v_actor, now())
  ON CONFLICT (referred_user_id) DO NOTHING;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.'
    );
  END IF;

  UPDATE public.nplus_demo_referrals
  SET status = 'qualified',
      reward_amount = 0,
      qualifying_request_id = NULL,
      qualified_at = now()
  WHERE referred_user_id = p_referred_user_id
    AND status = 'pending';

  RETURN jsonb_build_object(
    'success', true, 'reason', 'qualified',
    'referrer_user_id', v_referrer,
    'referred_user_id', p_referred_user_id,
    'verified_virtual_amount', p_verified_virtual_amount,
    'message', 'Invited account verified for the Daman-reference demo bonus tiers.'
  );
END;
$function$;

COMMIT;
