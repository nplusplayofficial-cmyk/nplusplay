-- N+ PLAY DEMO referral tracking only.
-- No real-money deposit, payment or cash payout is performed by this migration.
-- A referral earns 20 virtual demo credits once after the referred user has a
-- >=200-credit DEMO_CREDIT request approved by N+ ADMIN.
-- Candidate-only: test locally and in an isolated DB; do not apply to production without release approval.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.demo_wallets') IS NULL
     OR to_regclass('public.demo_wallet_transactions') IS NULL
     OR to_regclass('public.deposit_requests') IS NULL THEN
    RAISE EXCEPTION 'Apply the N+ PLAY core schema and demo-wallet request SQL before the referral migration.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='deposit_requests' AND column_name='payment_method'
  ) THEN
    RAISE EXCEPTION 'Apply sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql first. Referrals qualify only on DEMO_CREDIT requests.';
  END IF;
END
$preflight$;

CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_codes (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE CHECK (code ~ '^NP[A-Z0-9]{10}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS public.nplus_demo_referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  referral_code text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','rewarded')),
  qualifying_request_id uuid UNIQUE REFERENCES public.deposit_requests(id) ON DELETE SET NULL,
  qualifying_request_amount numeric(12,2),
  reward_credits numeric(12,2) NOT NULL DEFAULT 20.00 CHECK (reward_credits = 20.00),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  qualified_at timestamptz,
  rewarded_at timestamptz,
  CONSTRAINT nplus_demo_referrals_no_self_referral CHECK (referrer_user_id <> referred_user_id),
  CONSTRAINT nplus_demo_referrals_reward_state_check CHECK (
    (status='pending' AND qualifying_request_id IS NULL AND qualified_at IS NULL AND rewarded_at IS NULL)
    OR
    (status='rewarded' AND qualifying_request_id IS NOT NULL AND qualified_at IS NOT NULL AND rewarded_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS nplus_demo_referrals_referrer_created_idx
  ON public.nplus_demo_referrals(referrer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nplus_demo_referrals_pending_idx
  ON public.nplus_demo_referrals(referred_user_id, status);

ALTER TABLE public.nplus_demo_referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_referrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nplus_demo_referral_codes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.nplus_demo_referrals FROM PUBLIC, anon, authenticated;

-- Generate one stable, unique code for each account. Existing accounts are backfilled below.
CREATE OR REPLACE FUNCTION public.nplus_demo_ensure_referral_code(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_code text;
  v_attempt integer;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required.';
  END IF;

  SELECT code INTO v_code
  FROM public.nplus_demo_referral_codes
  WHERE user_id = p_user_id;

  IF FOUND THEN
    RETURN v_code;
  END IF;

  FOR v_attempt IN 1..20 LOOP
    v_code := 'NP' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    BEGIN
      INSERT INTO public.nplus_demo_referral_codes(user_id, code)
      VALUES (p_user_id, v_code)
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION WHEN unique_violation THEN
      -- An extremely unlikely code collision: generate another code.
      NULL;
    END;

    SELECT code INTO v_code
    FROM public.nplus_demo_referral_codes
    WHERE user_id = p_user_id;

    IF FOUND THEN
      RETURN v_code;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'Unable to generate a unique demo referral code. Try again.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_on_profile_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  PERFORM public.nplus_demo_ensure_referral_code(NEW.id);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS nplus_demo_profile_referral_code ON public.profiles;
CREATE TRIGGER nplus_demo_profile_referral_code
AFTER INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.nplus_demo_on_profile_created();

DO $backfill$
DECLARE
  v_profile record;
BEGIN
  FOR v_profile IN SELECT id FROM public.profiles LOOP
    PERFORM public.nplus_demo_ensure_referral_code(v_profile.id);
  END LOOP;
END
$backfill$;

-- Called after email OTP verification. Attribution is server validated and permanent.
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
  v_existing_referrer uuid;
  v_rows integer;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;
  IF v_code = '' OR v_code !~ '^NP[A-Z0-9]{10}$' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_code', 'message', 'Referral code is invalid. No referral was attached.');
  END IF;

  SELECT user_id INTO v_referrer
  FROM public.nplus_demo_referral_codes
  WHERE code = v_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_code', 'message', 'Referral code was not found. No referral was attached.');
  END IF;
  IF v_referrer = v_actor THEN
    RETURN jsonb_build_object('success', false, 'reason', 'self_referral', 'message', 'You cannot use your own referral code.');
  END IF;

  INSERT INTO public.nplus_demo_referrals(referrer_user_id, referred_user_id, referral_code)
  VALUES (v_referrer, v_actor, v_code)
  ON CONFLICT (referred_user_id) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 1 THEN
    RETURN jsonb_build_object(
      'success', true, 'applied', true, 'status', 'pending',
      'reward_credits', 20, 'qualifying_virtual_credits', 200,
      'message', 'Demo referral attached. Reward is pending the qualifying virtual-credit request being approved.'
    );
  END IF;

  SELECT referrer_user_id INTO v_existing_referrer
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = v_actor;

  IF v_existing_referrer = v_referrer THEN
    RETURN jsonb_build_object(
      'success', true, 'applied', false, 'already_applied', true,
      'status', (SELECT status FROM public.nplus_demo_referrals WHERE referred_user_id = v_actor),
      'message', 'This referral is already attached to your account.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', false, 'reason', 'already_attributed',
    'message', 'A referral is already attached to this account. It cannot be changed.'
  );
END;
$function$;

-- Return only the signed-in user's own code and referral rows.
CREATE OR REPLACE FUNCTION public.nplus_demo_referral_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text;
  v_total integer;
  v_pending integer;
  v_rewarded integer;
  v_referrals jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  v_code := public.nplus_demo_ensure_referral_code(v_actor);

  SELECT count(*)::integer,
         count(*) FILTER (WHERE status='pending')::integer,
         count(*) FILTER (WHERE status='rewarded')::integer
  INTO v_total, v_pending, v_rewarded
  FROM public.nplus_demo_referrals
  WHERE referrer_user_id = v_actor;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'display_name', coalesce(p.display_name, 'N+ PLAY Member'),
      'status', r.status,
      'created_at', r.created_at,
      'reward_credits', CASE WHEN r.status='rewarded' THEN 20 ELSE 0 END
    ) ORDER BY r.created_at DESC
  ), '[]'::jsonb)
  INTO v_referrals
  FROM public.nplus_demo_referrals r
  JOIN public.profiles p ON p.id = r.referred_user_id
  WHERE r.referrer_user_id = v_actor;

  RETURN jsonb_build_object(
    'success', true,
    'demo_only', true,
    'referral_code', v_code,
    'qualifying_virtual_credits', 200,
    'reward_virtual_credits', 20,
    'total_referrals', coalesce(v_total,0),
    'pending_referrals', coalesce(v_pending,0),
    'rewarded_referrals', coalesce(v_rewarded,0),
    'referrals', coalesce(v_referrals,'[]'::jsonb)
  );
END;
$function$;

-- Award only from the server when N+ ADMIN approves a DEMO_CREDIT request >= 200.
-- The referral row transition and wallet/ledger write occur in the same transaction.
CREATE OR REPLACE FUNCTION public.nplus_demo_award_referral_on_approved_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_referral_id uuid;
  v_referrer_id uuid;
  v_before numeric(12,2);
  v_after numeric(12,2);
BEGIN
  IF NEW.status IS DISTINCT FROM 'approved'
     OR OLD.status IS NOT DISTINCT FROM NEW.status
     OR OLD.status = 'approved'
     OR NEW.amount < 200
     OR coalesce(NEW.payment_method, '') <> 'DEMO_CREDIT' THEN
    RETURN NEW;
  END IF;

  SELECT id, referrer_user_id
  INTO v_referral_id, v_referrer_id
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = NEW.user_id
    AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  UPDATE public.nplus_demo_referrals
  SET status = 'rewarded',
      qualifying_request_id = NEW.id,
      qualifying_request_amount = round(NEW.amount,2),
      qualified_at = clock_timestamp(),
      rewarded_at = clock_timestamp()
  WHERE id = v_referral_id
    AND status = 'pending'
  RETURNING referrer_user_id INTO v_referrer_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT balance INTO v_before
  FROM public.demo_wallets
  WHERE user_id = v_referrer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Referrer demo wallet not found; referral reward was not applied.';
  END IF;

  v_after := v_before + 20.00;

  UPDATE public.demo_wallets
  SET balance = v_after,
      updated_at = clock_timestamp()
  WHERE user_id = v_referrer_id;

  INSERT INTO public.demo_wallet_transactions(
    user_id, delta, balance_before, balance_after, type, source, note
  )
  VALUES (
    v_referrer_id, 20.00, v_before, v_after,
    'REFERRAL_CREDIT', 'DEMO_REFERRAL',
    'Demo-only referral reward: qualifying virtual-credit request approved; no cash value.'
  );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS nplus_demo_referral_approved_request ON public.deposit_requests;
CREATE TRIGGER nplus_demo_referral_approved_request
AFTER UPDATE OF status ON public.deposit_requests
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status='approved')
EXECUTE FUNCTION public.nplus_demo_award_referral_on_approved_request();

REVOKE ALL ON FUNCTION public.nplus_demo_ensure_referral_code(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_on_profile_created() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_apply(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_dashboard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_award_referral_on_approved_request() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_apply(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_dashboard() TO authenticated;

COMMIT;
