\set ON_ERROR_STOP on
-- Dedicated disposable PostgreSQL test only; do not run on production.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $uid$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$uid$;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,
  role text NOT NULL
);
CREATE TABLE public.nplus_demo_referrals (
  user_id uuid NOT NULL,
  referred_user_id uuid PRIMARY KEY,
  status text NOT NULL,
  reward_amount numeric(14,2) NOT NULL DEFAULT 0,
  qualifying_request_id uuid,
  qualified_at timestamptz,
  rewarded_at timestamptz
);
CREATE TABLE public.nplus_demo_referral_qualifications (
  referred_user_id uuid PRIMARY KEY,
  referrer_user_id uuid NOT NULL,
  qualifying_virtual_amount numeric(14,2) NOT NULL,
  verified_by uuid NOT NULL,
  verified_at timestamptz NOT NULL
);

CREATE OR REPLACE FUNCTION public.nplus_is_admin()
RETURNS boolean
LANGUAGE sql STABLE
AS $is_admin$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND lower(role) = 'admin'
  )
$is_admin$;

\ir ../sql/NPLUS_PLAY_REFERRAL_FINITE_QUALIFICATION_GUARD_CANDIDATE_2026-10-27.sql

-- Match the reviewed live execute-grant contract for this isolated fixture.
REVOKE ALL ON FUNCTION public.nplus_demo_admin_qualify_referral(uuid,numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_qualify_referral(uuid,numeric)
  TO authenticated, service_role;

INSERT INTO public.profiles(id, role) VALUES
  ('e6111111-1111-4111-8111-111111111111','admin'),
  ('e6222222-2222-4222-8222-222222222222','user'),
  ('e6333333-3333-4333-8333-333333333333','user');
INSERT INTO public.nplus_demo_referrals(user_id,referred_user_id,status)
VALUES
  ('e6222222-2222-4222-8222-222222222222','e6333333-3333-4333-8333-333333333333','pending');

SELECT set_config('request.jwt.claim.sub','e6111111-1111-4111-8111-111111111111',false);

DO $finite_tests$
DECLARE
  v_admin uuid := 'e6111111-1111-4111-8111-111111111111';
  v_user uuid := 'e6222222-2222-4222-8222-222222222222';
  v_invited uuid := 'e6333333-3333-4333-8333-333333333333';
  v_result jsonb;
  v_denied boolean := false;
BEGIN
  v_result := public.nplus_demo_admin_qualify_referral(v_invited, 'NaN'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_verified_amount' THEN
    RAISE EXCEPTION 'FAIL: NaN qualification amount was not rejected as invalid.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, 'Infinity'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_verified_amount' THEN
    RAISE EXCEPTION 'FAIL: positive infinity qualification amount was not rejected.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, '-Infinity'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_verified_amount' THEN
    RAISE EXCEPTION 'FAIL: negative infinity qualification amount was not rejected.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, NULL::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_verified_amount' THEN
    RAISE EXCEPTION 'FAIL: NULL qualification amount was not rejected as invalid.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, 499.99);
  IF v_result->>'reason' IS DISTINCT FROM 'qualification_below_minimum' THEN
    RAISE EXCEPTION 'FAIL: below-minimum qualification amount was not rejected.';
  END IF;

  IF (SELECT status FROM public.nplus_demo_referrals WHERE referred_user_id=v_invited) <> 'pending'
     OR EXISTS (SELECT 1 FROM public.nplus_demo_referral_qualifications WHERE referred_user_id=v_invited) THEN
    RAISE EXCEPTION 'FAIL: an invalid amount changed referral state or wrote a qualification.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, 500.00);
  IF coalesce((v_result->>'success')::boolean, false) IS NOT TRUE
     OR v_result->>'reason' IS DISTINCT FROM 'qualified' THEN
    RAISE EXCEPTION 'FAIL: valid finite 500-point qualification was rejected.';
  END IF;

  IF (SELECT status FROM public.nplus_demo_referrals WHERE referred_user_id=v_invited) <> 'qualified'
     OR (SELECT count(*) FROM public.nplus_demo_referral_qualifications WHERE referred_user_id=v_invited) <> 1
     OR (SELECT qualifying_virtual_amount FROM public.nplus_demo_referral_qualifications WHERE referred_user_id=v_invited) <> 500.00 THEN
    RAISE EXCEPTION 'FAIL: valid qualification did not persist exactly one 500-point record.';
  END IF;

  v_result := public.nplus_demo_admin_qualify_referral(v_invited, 900.00);
  IF v_result->>'reason' IS DISTINCT FROM 'already_qualified' THEN
    RAISE EXCEPTION 'FAIL: repeated qualification was not rejected.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_user::text,false);
  BEGIN
    PERFORM public.nplus_demo_admin_qualify_referral(v_invited, 1000.00);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Administrator access required.' THEN
      v_denied := true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FAIL: non-admin qualified an invited account.';
  END IF;

  RAISE NOTICE 'PASS: NaN, Infinity, -Infinity, NULL and below-minimum referral amounts rejected.';
  RAISE NOTICE 'PASS: valid finite qualification persists exactly once.';
  RAISE NOTICE 'PASS: non-admin qualification request denied.';
END
$finite_tests$;

SELECT 'PASS: finite Admin referral qualification guard' AS result;
