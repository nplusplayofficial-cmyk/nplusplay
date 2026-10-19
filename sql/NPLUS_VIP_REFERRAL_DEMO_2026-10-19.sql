-- N+ PLAY VIP + referral demo services
-- Intended for LOCAL STAGING first. Review and test against a restored/test database
-- before applying to any shared/production Supabase project.
-- All balances are virtual demo credits only. No interest or cash withdrawal is implemented.

BEGIN;

-- One unique referral code per profile. IF NOT EXISTS keeps this compatible with
-- the initial local-staging referral prototype while adding any missing columns.
CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_codes (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  referral_code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.nplus_demo_referral_codes
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referral_codes_user_uidx
  ON public.nplus_demo_referral_codes(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referral_codes_code_uidx
  ON public.nplus_demo_referral_codes(upper(referral_code))
  WHERE referral_code IS NOT NULL;

-- Each new account may attach one inviter. Rewards are applied only after an
-- administrator approves a qualifying virtual-credit request of 200 points.
CREATE TABLE IF NOT EXISTS public.nplus_demo_referrals (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referral_code text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  reward_amount numeric(12,2) NOT NULL DEFAULT 0.00,
  qualifying_request_id uuid REFERENCES public.deposit_requests(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  qualified_at timestamptz,
  awarded_at timestamptz
);
ALTER TABLE public.nplus_demo_referrals
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS referred_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reward_amount numeric(12,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS qualifying_request_id uuid REFERENCES public.deposit_requests(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS qualified_at timestamptz,
  ADD COLUMN IF NOT EXISTS awarded_at timestamptz;
ALTER TABLE public.nplus_demo_referrals ALTER COLUMN reward_amount SET DEFAULT 0.00;

DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.nplus_demo_referrals
    WHERE referred_user_id IS NOT NULL
    GROUP BY referred_user_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate referred_user_id values exist in nplus_demo_referrals; review local-staging data before applying this migration.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.nplus_demo_referral_codes
    WHERE referral_code IS NOT NULL
    GROUP BY upper(referral_code) HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate referral codes exist; review local-staging data before applying this migration.';
  END IF;
END;
$preflight$;

CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referrals_referred_uidx
  ON public.nplus_demo_referrals(referred_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referrals_request_uidx
  ON public.nplus_demo_referrals(qualifying_request_id)
  WHERE qualifying_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS nplus_demo_referrals_inviter_created_idx
  ON public.nplus_demo_referrals(user_id, created_at DESC);

-- Invitation reward tiers copied from the user-provided Daman reference screenshots.
-- Figures are represented as virtual demo points in N+; they are not cash amounts.
CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_tier_rules (
  invitee_count integer PRIMARY KEY CHECK (invitee_count > 0),
  qualification_amount numeric(14,2) NOT NULL DEFAULT 500.00 CHECK (qualification_amount = 500.00),
  bonus_amount numeric(14,2) NOT NULL CHECK (bonus_amount > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.nplus_demo_referral_tier_rules(invitee_count, qualification_amount, bonus_amount)
VALUES
  (1, 500.00, 55.00),
  (3, 500.00, 155.00),
  (10, 500.00, 555.00),
  (30, 500.00, 1555.00),
  (50, 500.00, 2555.00),
  (70, 500.00, 3355.00),
  (100, 500.00, 5555.00),
  (200, 500.00, 10955.00),
  (500, 500.00, 25555.00),
  (1000, 500.00, 48555.00),
  (5000, 500.00, 355555.00),
  (10000, 500.00, 755555.00),
  (20000, 500.00, 1555555.00),
  (50000, 500.00, 3555555.00),
  (100000, 500.00, 7555555.00)
ON CONFLICT (invitee_count) DO UPDATE
SET qualification_amount = EXCLUDED.qualification_amount,
    bonus_amount = EXCLUDED.bonus_amount,
    updated_at = now();

-- VIP experience is demo progression only. It is not based on client-submitted bets.
CREATE TABLE IF NOT EXISTS public.nplus_demo_vip_state (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  experience_points bigint NOT NULL DEFAULT 0 CHECK (experience_points >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Virtual safe account has no interest calculation and cannot be withdrawn as cash.
CREATE TABLE IF NOT EXISTS public.nplus_demo_safe_balances (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance numeric(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_safe_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('IN','OUT')),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  wallet_after numeric(14,2) NOT NULL,
  safe_after numeric(14,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nplus_demo_safe_transfers_user_created_idx
  ON public.nplus_demo_safe_transfers(user_id, created_at DESC);

-- Gift codes award only virtual credits. Each account may redeem a given code once.
CREATE TABLE IF NOT EXISTS public.nplus_demo_gift_codes (
  code text PRIMARY KEY,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  active boolean NOT NULL DEFAULT true,
  max_claims integer NOT NULL DEFAULT 100000,
  claims_count integer NOT NULL DEFAULT 0,
  expires_at timestamptz,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_gift_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  code text NOT NULL REFERENCES public.nplus_demo_gift_codes(code),
  amount numeric(12,2) NOT NULL,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, code)
);
CREATE INDEX IF NOT EXISTS nplus_demo_gift_claims_user_date_idx
  ON public.nplus_demo_gift_claims(user_id, claimed_at DESC);

INSERT INTO public.nplus_demo_gift_codes(code, amount, active, max_claims)
VALUES ('NPLUS50', 50.00, true, 100000), ('WELCOME20', 20.00, true, 100000)
ON CONFLICT (code) DO NOTHING;

-- Daily attendance is capped at one claim per account per day and requires at
-- least one administrator-approved virtual-credit request, matching the demo rules.
CREATE TABLE IF NOT EXISTS public.nplus_demo_attendance_claims (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  claim_date date NOT NULL,
  streak_day integer NOT NULL CHECK (streak_day BETWEEN 1 AND 7),
  reward_amount numeric(12,2) NOT NULL CHECK (reward_amount >= 0),
  claimed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, claim_date)
);
CREATE INDEX IF NOT EXISTS nplus_demo_attendance_user_date_idx
  ON public.nplus_demo_attendance_claims(user_id, claim_date DESC);

-- Member feedback/customer support requests. User records stay private; admins use RPCs.
CREATE TABLE IF NOT EXISTS public.nplus_demo_support_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category text NOT NULL DEFAULT 'other',
  subject text NOT NULL,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  admin_note text NOT NULL DEFAULT '',
  handled_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nplus_demo_support_user_created_idx
  ON public.nplus_demo_support_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nplus_demo_support_status_created_idx
  ON public.nplus_demo_support_requests(status, created_at DESC);

-- Private RPC helper: ensures the caller's account has exactly one unique code.
CREATE OR REPLACE FUNCTION public.nplus_demo_ensure_referral_code(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_code text;
  v_attempt integer := 0;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id
  ) THEN
    RAISE EXCEPTION 'A valid N+ profile is required.';
  END IF;

  SELECT referral_code INTO v_code
  FROM public.nplus_demo_referral_codes
  WHERE user_id = p_user_id;

  IF FOUND AND v_code IS NOT NULL THEN
    RETURN v_code;
  END IF;

  LOOP
    v_attempt := v_attempt + 1;
    IF v_attempt > 10 THEN
      RAISE EXCEPTION 'Unable to generate a unique referral code. Please retry.';
    END IF;

    v_code := 'NPLUS' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    INSERT INTO public.nplus_demo_referral_codes(user_id, referral_code, created_at)
    VALUES (p_user_id, v_code, now())
    ON CONFLICT DO NOTHING
    RETURNING referral_code INTO v_code;

    IF FOUND THEN
      RETURN v_code;
    END IF;

    SELECT referral_code INTO v_code
    FROM public.nplus_demo_referral_codes
    WHERE user_id = p_user_id;

    IF FOUND AND v_code IS NOT NULL THEN
      RETURN v_code;
    END IF;
  END LOOP;
END;
$function$;

-- Extend the existing local-staging profile trigger (if present) so new profiles
-- receive their unique referral code, VIP state and safe account.
CREATE OR REPLACE FUNCTION public.nplus_demo_on_profile_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  PERFORM public.nplus_demo_ensure_referral_code(NEW.id);
  INSERT INTO public.nplus_demo_vip_state(user_id) VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.nplus_demo_safe_balances(user_id, balance) VALUES (NEW.id, 0)
    ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS nplus_demo_profile_referral_code ON public.profiles;
CREATE TRIGGER nplus_demo_profile_referral_code
AFTER INSERT ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.nplus_demo_on_profile_created();

-- Backfill existing local-staging profiles idempotently.
DO $backfill$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.profiles LOOP
    PERFORM public.nplus_demo_ensure_referral_code(r.id);
    INSERT INTO public.nplus_demo_vip_state(user_id) VALUES (r.id)
      ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.nplus_demo_safe_balances(user_id, balance) VALUES (r.id, 0)
      ON CONFLICT (user_id) DO NOTHING;
  END LOOP;
END;
$backfill$;

CREATE OR REPLACE FUNCTION public.nplus_demo_referral_apply(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_referrer uuid;
BEGIN
  IF v_actor IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'authentication_required',
      'message', 'Please sign in before applying a referral code.');
  END IF;
  IF v_code = '' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_code',
      'message', 'No referral code was supplied.');
  END IF;

  SELECT user_id INTO v_referrer
  FROM public.nplus_demo_referral_codes
  WHERE upper(referral_code) = v_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'code_not_found',
      'message', 'Referral code was not found.');
  END IF;
  IF v_referrer = v_actor THEN
    RETURN jsonb_build_object('success', false, 'reason', 'self_referral',
      'message', 'You cannot use your own referral code.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.nplus_demo_referrals WHERE referred_user_id = v_actor) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_referred',
      'message', 'A referral code has already been attached to this account.');
  END IF;

  INSERT INTO public.nplus_demo_referrals
    (user_id, referred_user_id, referral_code, status, reward_amount, created_at)
  VALUES (v_referrer, v_actor, v_code, 'pending', 0.00, now())
  ON CONFLICT DO NOTHING;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_referred',
      'message', 'A referral code has already been attached to this account.');
  END IF;

  RETURN jsonb_build_object('success', true, 'reason', 'attached',
    'message', 'Referral code attached. Invitation bonuses follow the published tier rules and are not auto-awarded on deposit-request approval.');
END;
$function$;

-- Deliberately disable the old per-referral 200/20 auto-award logic.
-- The Daman reference uses invitation-count tiers and a 500-per-invite qualification
-- amount. Do not connect rewards to the generic deposit_requests table: it may
-- represent a real-money workflow. A verified demo-only qualification/claim RPC
-- must be implemented and tested separately before any tier credits are issued.
CREATE OR REPLACE FUNCTION public.nplus_demo_award_referral_on_approved_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS nplus_demo_referral_approved_request ON public.deposit_requests;

CREATE OR REPLACE FUNCTION public.nplus_demo_referral_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text;
  v_payload jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  v_code := public.nplus_demo_ensure_referral_code(v_actor);

  SELECT jsonb_build_object(
    'success', true,
    'referral_code', v_code,
    'referral_link', 'auth.html?ref=' || v_code,
    'referral_count', count(*),
    'pending_count', count(*) FILTER (WHERE r.status = 'pending'),
    'rewarded_count', count(*) FILTER (WHERE r.status = 'rewarded'),
    'total_rewards', coalesce(sum(r.reward_amount) FILTER (WHERE r.status = 'rewarded'), 0),
    'referrals', coalesce(
      jsonb_agg(jsonb_build_object(
        'uid', p.uid,
        'display_name', coalesce(nullif(p.display_name, ''), 'N+ member'),
        'status', r.status,
        'reward_points', r.reward_amount,
        'created_at', r.created_at,
        'awarded_at', r.awarded_at
      ) ORDER BY r.created_at DESC) FILTER (WHERE r.referred_user_id IS NOT NULL),
      '[]'::jsonb
    )
  ) INTO v_payload
  FROM public.nplus_demo_referrals r
  LEFT JOIN public.profiles p ON p.id = r.referred_user_id
  WHERE r.user_id = v_actor;

  RETURN coalesce(v_payload, jsonb_build_object(
    'success', true, 'referral_code', v_code, 'referral_link', 'auth.html?ref=' || v_code,
    'referral_count', 0, 'pending_count', 0, 'rewarded_count', 0,
    'total_rewards', 0, 'referrals', '[]'::jsonb
  ));
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_vip_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_exp bigint;
  v_wallet numeric(14,2);
  v_tier integer;
  v_next bigint;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;

  INSERT INTO public.nplus_demo_vip_state(user_id) VALUES (v_actor)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT experience_points INTO v_exp
  FROM public.nplus_demo_vip_state WHERE user_id = v_actor;
  SELECT balance INTO v_wallet
  FROM public.demo_wallets WHERE user_id = v_actor;

  v_tier := CASE
    WHEN v_exp >= 2500000 THEN 10
    WHEN v_exp >= 1000000 THEN 9
    WHEN v_exp >= 500000 THEN 8
    WHEN v_exp >= 250000 THEN 7
    WHEN v_exp >= 100000 THEN 6
    WHEN v_exp >= 50000 THEN 5
    WHEN v_exp >= 20000 THEN 4
    WHEN v_exp >= 5000 THEN 3
    WHEN v_exp >= 1000 THEN 2
    ELSE 1 END;

  v_next := CASE v_tier
    WHEN 1 THEN 1000 WHEN 2 THEN 5000 WHEN 3 THEN 20000 WHEN 4 THEN 50000
    WHEN 5 THEN 100000 WHEN 6 THEN 250000 WHEN 7 THEN 500000 WHEN 8 THEN 1000000
    WHEN 9 THEN 2500000 ELSE 2500000 END;

  RETURN jsonb_build_object(
    'success', true, 'tier', v_tier, 'experience_points', coalesce(v_exp,0),
    'next_tier_exp', v_next, 'points_to_next', greatest(0, v_next - coalesce(v_exp,0)),
    'wallet_balance', coalesce(v_wallet,0),
    'notice', 'Demo EXP is awarded only for eligible virtual rewards; no cash value.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_gift_redeem(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code,'')));
  v_amount numeric(12,2);
  v_max integer;
  v_count integer;
  v_expires timestamptz;
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_code = '' THEN RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Enter a gift code.'); END IF;

  SELECT amount, max_claims, claims_count, expires_at
    INTO v_amount, v_max, v_count, v_expires
    FROM public.nplus_demo_gift_codes
   WHERE code = v_code AND active = true
   FOR UPDATE;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','not_found','message','Gift code is invalid or inactive.'); END IF;
  IF v_expires IS NOT NULL AND v_expires <= now() THEN
    RETURN jsonb_build_object('success',false,'reason','expired','message','This demo gift code has expired.');
  END IF;
  IF v_count >= v_max THEN RETURN jsonb_build_object('success',false,'reason','fully_claimed','message','This demo gift code has reached its claim limit.'); END IF;

  INSERT INTO public.nplus_demo_gift_claims(user_id, code, amount)
  VALUES (v_actor, v_code, v_amount)
  ON CONFLICT (user_id, code) DO NOTHING;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','already_claimed','message','This code was already redeemed on this account.'); END IF;

  UPDATE public.nplus_demo_gift_codes SET claims_count = claims_count + 1 WHERE code = v_code;

  INSERT INTO public.demo_wallets(user_id, balance) VALUES (v_actor, 0)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.demo_wallets SET balance = balance + v_amount, updated_at = now()
    WHERE user_id = v_actor RETURNING balance - v_amount, balance INTO v_before, v_after;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;

  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES (v_actor,v_amount,v_before,v_after,'GIFT_REWARD','GIFT',format('Demo gift code %s',v_code));

  INSERT INTO public.nplus_demo_vip_state(user_id,experience_points)
  VALUES (v_actor,v_amount::bigint)
  ON CONFLICT (user_id) DO UPDATE
    SET experience_points = public.nplus_demo_vip_state.experience_points + EXCLUDED.experience_points,
        updated_at = now();

  RETURN jsonb_build_object('success',true,'code',v_code,'amount',v_amount,
    'wallet_balance',v_after,'message',format('Added %s virtual demo points.',v_amount));
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_gift_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  RETURN jsonb_build_object(
    'success',true,
    'claims',coalesce((
      SELECT jsonb_agg(jsonb_build_object('code',code,'amount',amount,'claimed_at',claimed_at) ORDER BY claimed_at DESC)
      FROM public.nplus_demo_gift_claims WHERE user_id=v_actor
    ),'[]'::jsonb),
    'available_demo_codes',jsonb_build_array('NPLUS50','WELCOME20')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_safe_transfer(p_direction text, p_amount numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_direction text := upper(trim(coalesce(p_direction,'')));
  v_amount numeric(14,2) := p_amount;
  v_wallet numeric(14,2);
  v_safe numeric(14,2);
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_direction NOT IN ('IN','OUT') THEN RETURN jsonb_build_object('success',false,'reason','invalid_direction','message','Choose IN or OUT.'); END IF;
  IF v_amount IS NULL OR v_amount <= 0 OR v_amount <> round(v_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a positive virtual amount with up to 2 decimals.');
  END IF;

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

CREATE OR REPLACE FUNCTION public.nplus_demo_safe_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  RETURN jsonb_build_object(
    'success',true,
    'wallet_balance',coalesce((SELECT balance FROM public.demo_wallets WHERE user_id=v_actor),0),
    'safe_balance',coalesce((SELECT balance FROM public.nplus_demo_safe_balances WHERE user_id=v_actor),0),
    'transfers',coalesce((
      SELECT jsonb_agg(jsonb_build_object('direction',direction,'amount',amount,
        'wallet_after',wallet_after,'safe_after',safe_after,'created_at',created_at) ORDER BY created_at DESC)
      FROM (SELECT * FROM public.nplus_demo_safe_transfers WHERE user_id=v_actor ORDER BY created_at DESC LIMIT 20) t
    ),'[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_attendance_claim()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_previous_day integer;
  v_streak integer;
  v_reward numeric(12,2);
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.deposit_requests WHERE user_id=v_actor AND status='approved') THEN
    RETURN jsonb_build_object('success',false,'reason','demo_credit_required',
      'message','Attendance demo requires an administrator-approved virtual-credit request.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor AND claim_date=current_date) THEN
    RETURN jsonb_build_object('success',false,'reason','already_claimed','message','Attendance was already claimed today.');
  END IF;

  SELECT streak_day INTO v_previous_day
  FROM public.nplus_demo_attendance_claims
  WHERE user_id=v_actor AND claim_date=current_date-1;

  v_streak := CASE WHEN v_previous_day IS NULL THEN 1 ELSE (v_previous_day % 7) + 1 END;
  v_reward := CASE v_streak WHEN 1 THEN 4 WHEN 2 THEN 20 WHEN 3 THEN 65 WHEN 4 THEN 180
    WHEN 5 THEN 450 WHEN 6 THEN 2200 ELSE 6000 END;

  INSERT INTO public.nplus_demo_attendance_claims(user_id,claim_date,streak_day,reward_amount)
  VALUES(v_actor,current_date,v_streak,v_reward)
  ON CONFLICT (user_id,claim_date) DO NOTHING;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','already_claimed','message','Attendance was already claimed today.'); END IF;

  INSERT INTO public.demo_wallets(user_id,balance) VALUES(v_actor,0)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.demo_wallets SET balance=balance+v_reward,updated_at=now()
  WHERE user_id=v_actor RETURNING balance-v_reward,balance INTO v_before,v_after;

  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES(v_actor,v_reward,v_before,v_after,'ATTENDANCE_REWARD','ATTENDANCE',format('Day %s demo attendance reward',v_streak));

  INSERT INTO public.nplus_demo_vip_state(user_id,experience_points)
  VALUES(v_actor,v_reward::bigint)
  ON CONFLICT (user_id) DO UPDATE
    SET experience_points=public.nplus_demo_vip_state.experience_points+EXCLUDED.experience_points,
        updated_at=now();

  RETURN jsonb_build_object('success',true,'streak_day',v_streak,'reward_amount',v_reward,
    'wallet_balance',v_after,'message',format('Day %s attendance claimed: %s virtual points.',v_streak,v_reward));
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_attendance_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_last_date date;
  v_streak integer;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT max(claim_date) INTO v_last_date FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor;
  SELECT streak_day INTO v_streak FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor AND claim_date=v_last_date;
  IF v_last_date IS NULL OR v_last_date < current_date-1 THEN v_streak:=0; END IF;
  RETURN jsonb_build_object(
    'success',true,
    'today_claimed',exists(SELECT 1 FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor AND claim_date=current_date),
    'streak_day',coalesce(v_streak,0),
    'total_rewards',coalesce((SELECT sum(reward_amount) FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor),0),
    'history',coalesce((
      SELECT jsonb_agg(jsonb_build_object('claim_date',claim_date,'streak_day',streak_day,
        'reward_amount',reward_amount,'claimed_at',claimed_at) ORDER BY claim_date DESC)
      FROM (SELECT * FROM public.nplus_demo_attendance_claims WHERE user_id=v_actor ORDER BY claim_date DESC LIMIT 14) t
    ),'[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_vip_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'success',true,
    'users', (SELECT count(*) FROM public.profiles WHERE lower(coalesce(role,'user')) <> 'admin'),
    'referrals_total', (SELECT count(*) FROM public.nplus_demo_referrals),
    'referrals_pending', (SELECT count(*) FROM public.nplus_demo_referrals WHERE status='pending'),
    'referrals_rewarded', (SELECT count(*) FROM public.nplus_demo_referrals WHERE status='rewarded'),
    'referral_points_awarded', (SELECT coalesce(sum(reward_amount),0) FROM public.nplus_demo_referrals WHERE status='rewarded'),
    'gift_codes', (SELECT count(*) FROM public.nplus_demo_gift_codes),
    'gift_claims', (SELECT count(*) FROM public.nplus_demo_gift_claims),
    'attendance_claims', (SELECT count(*) FROM public.nplus_demo_attendance_claims),
    'notice', 'All numbers are virtual demo credits only.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_referrals(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'referrer_uid', inviter.uid,
      'referred_uid', invitee.uid,
      'referral_code', r.referral_code,
      'status', r.status,
      'reward_points', r.reward_amount,
      'created_at', r.created_at,
      'awarded_at', r.awarded_at
    ) ORDER BY r.created_at DESC)
    FROM (
      SELECT * FROM public.nplus_demo_referrals ORDER BY created_at DESC
      LIMIT greatest(1, least(coalesce(p_limit,100),500))
    ) r
    LEFT JOIN public.profiles inviter ON inviter.id=r.user_id
    LEFT JOIN public.profiles invitee ON invitee.id=r.referred_user_id
  ),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_create_gift_code(
  p_code text, p_amount numeric, p_max_claims integer DEFAULT 1000, p_expires_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_code text := upper(trim(coalesce(p_code,'')));
  v_actor uuid := auth.uid();
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  IF v_code !~ '^[A-Z0-9_-]{4,24}$' THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Use 4–24 letters, digits, underscores, or hyphens.');
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 1000000 OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a positive demo amount up to 1,000,000.');
  END IF;
  IF coalesce(p_max_claims,0) < 1 OR p_max_claims > 1000000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_limit','message','Claim limit must be between 1 and 1,000,000.');
  END IF;
  INSERT INTO public.nplus_demo_gift_codes(code,amount,active,max_claims,expires_at,created_by)
  VALUES(v_code,p_amount,true,p_max_claims,p_expires_at,v_actor);
  RETURN jsonb_build_object('success',true,'code',v_code,'amount',p_amount,'max_claims',p_max_claims);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('success',false,'reason','already_exists','message','That gift code already exists.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_support_submit(p_category text, p_subject text, p_message text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_category text := lower(trim(coalesce(p_category,'other')));
  v_subject text := trim(coalesce(p_subject,''));
  v_message text := trim(coalesce(p_message,''));
  v_id uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_category NOT IN ('feedback','account','virtual_credit','gift_code','bug','other') THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_category','message','Choose a valid support category.');
  END IF;
  IF length(v_subject) < 3 OR length(v_subject) > 100 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_subject','message','Subject must be 3–100 characters.');
  END IF;
  IF length(v_message) < 10 OR length(v_message) > 3000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_message','message','Message must be 10–3,000 characters.');
  END IF;
  INSERT INTO public.nplus_demo_support_requests(user_id,category,subject,message)
  VALUES(v_actor,v_category,v_subject,v_message)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('success',true,'request_id',v_id,'message','Support request submitted.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_support_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  RETURN jsonb_build_object(
    'success',true,
    'requests',coalesce((
      SELECT jsonb_agg(jsonb_build_object('id',id,'category',category,'subject',subject,
        'status',status,'admin_note',admin_note,'created_at',created_at,'updated_at',updated_at)
        ORDER BY created_at DESC)
      FROM (SELECT * FROM public.nplus_demo_support_requests WHERE user_id=v_actor ORDER BY created_at DESC LIMIT 50) q
    ),'[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_support_list(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object('id',q.id,'uid',p.uid,'category',q.category,
      'subject',q.subject,'message',q.message,'status',q.status,'admin_note',q.admin_note,
      'created_at',q.created_at,'updated_at',q.updated_at) ORDER BY q.created_at DESC)
    FROM (SELECT * FROM public.nplus_demo_support_requests ORDER BY created_at DESC
      LIMIT greatest(1,least(coalesce(p_limit,100),500))) q
    LEFT JOIN public.profiles p ON p.id=q.user_id
  ),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_support_update(p_ticket_id uuid, p_status text, p_admin_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_status text := lower(trim(coalesce(p_status,'')));
  v_actor uuid := auth.uid();
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  IF v_status NOT IN ('open','in_review','closed') THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_status','message','Choose open, in_review, or closed.');
  END IF;
  UPDATE public.nplus_demo_support_requests
     SET status=v_status, admin_note=left(coalesce(p_admin_note,''),2000),
         handled_by=v_actor, updated_at=now()
   WHERE id=p_ticket_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','not_found','message','Support request not found.'); END IF;
  RETURN jsonb_build_object('success',true,'message','Support request updated.');
END;
$function$;

-- Keep every new table server-owned. Browser clients interact through narrowly scoped RPCs.
ALTER TABLE public.nplus_demo_referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_referral_tier_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_vip_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_safe_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_safe_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_gift_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_gift_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_attendance_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_support_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.nplus_demo_referral_codes, public.nplus_demo_referrals, public.nplus_demo_referral_tier_rules,
  public.nplus_demo_vip_state, public.nplus_demo_safe_balances, public.nplus_demo_safe_transfers,
  public.nplus_demo_gift_codes, public.nplus_demo_gift_claims, public.nplus_demo_attendance_claims,
  public.nplus_demo_support_requests
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.nplus_demo_ensure_referral_code(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_on_profile_created() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_award_referral_on_approved_request() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_apply(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_vip_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_gift_redeem(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_gift_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_safe_transfer(text,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_safe_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_attendance_claim() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_attendance_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_vip_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_referrals(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_create_gift_code(text,numeric,integer,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_support_submit(text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_support_dashboard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_support_list(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_support_update(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_apply(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_vip_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_gift_redeem(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_gift_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_safe_transfer(text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_safe_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_attendance_claim() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_attendance_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_vip_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_referrals(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_create_gift_code(text,numeric,integer,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_support_submit(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_support_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_support_list(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_support_update(uuid,text,text) TO authenticated;

COMMIT;

-- Before deployment: test signup/OTP/referral attribution, request approval and one-time award,
-- two simultaneous reward attempts, gift claim duplication, safe transfers and daily claim race
-- against LOCAL STAGING. Do not apply directly to production without a verified backup and review.