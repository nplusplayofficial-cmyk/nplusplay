\set ON_ERROR_STOP on
-- Dedicated disposable PostgreSQL runtime regression; never run on production.
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

CREATE TABLE public.demo_wallets (
  user_id uuid PRIMARY KEY,
  balance numeric(18,2) NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.nplus_demo_safe_balances (
  user_id uuid PRIMARY KEY,
  balance numeric(14,2) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.demo_wallet_transactions (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  delta numeric(18,2) NOT NULL,
  balance_before numeric(18,2) NOT NULL,
  balance_after numeric(18,2) NOT NULL,
  type text NOT NULL,
  source text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.nplus_demo_safe_transfers (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  direction text NOT NULL,
  amount numeric(14,2) NOT NULL,
  wallet_after numeric(14,2) NOT NULL,
  safe_after numeric(14,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

\ir ../sql/NPLUS_PLAY_SAFE_TRANSFER_FINITE_AMOUNT_GUARD_CANDIDATE_2026-10-27.sql

-- Match the reviewed current browser-role ACL contract in this disposable fixture only.
REVOKE ALL ON FUNCTION public.nplus_demo_safe_transfer(text,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_safe_transfer(text,numeric) TO authenticated, service_role;

INSERT INTO public.demo_wallets(user_id,balance)
VALUES ('e7111111-1111-4111-8111-111111111111',100.00);
SELECT set_config('request.jwt.claim.sub','e7111111-1111-4111-8111-111111111111',false);

DO $tests$
DECLARE
  v_actor uuid := 'e7111111-1111-4111-8111-111111111111';
  v_result jsonb;
  v_wallet numeric(18,2);
  v_safe numeric(14,2);
  v_count bigint;
BEGIN
  v_result := public.nplus_demo_safe_transfer('IN','NaN'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: NaN was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN','Infinity'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: positive infinity was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN','-Infinity'::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: negative infinity was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',NULL::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: NULL was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',10.001);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: more than two decimal places was not rejected before narrowing cast.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',999999999999999999999999::numeric);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: amount exceeding numeric(14,2) range was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',0);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: zero was not rejected.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',-1);
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: negative amount was not rejected.';
  END IF;

  SELECT balance INTO v_wallet FROM public.demo_wallets WHERE user_id=v_actor;
  SELECT coalesce((SELECT balance FROM public.nplus_demo_safe_balances WHERE user_id=v_actor),0) INTO v_safe;
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions WHERE user_id=v_actor;
  IF v_wallet<>100.00 OR v_safe<>0.00 OR v_count<>0
     OR EXISTS (SELECT 1 FROM public.nplus_demo_safe_transfers WHERE user_id=v_actor) THEN
    RAISE EXCEPTION 'FAIL: invalid amounts changed wallet/safe balance or wrote transfer history.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',10.00);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: valid IN transfer was not accepted.';
  END IF;
  SELECT balance INTO v_wallet FROM public.demo_wallets WHERE user_id=v_actor;
  SELECT balance INTO v_safe FROM public.nplus_demo_safe_balances WHERE user_id=v_actor;
  IF v_wallet<>90.00 OR v_safe<>10.00 THEN
    RAISE EXCEPTION 'FAIL: valid IN transfer produced wrong balances.';
  END IF;

  v_result := public.nplus_demo_safe_transfer('OUT',5.00);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: valid OUT transfer was not accepted.';
  END IF;
  SELECT balance INTO v_wallet FROM public.demo_wallets WHERE user_id=v_actor;
  SELECT balance INTO v_safe FROM public.nplus_demo_safe_balances WHERE user_id=v_actor;
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions WHERE user_id=v_actor;
  IF v_wallet<>95.00 OR v_safe<>5.00 OR v_count<>2
     OR (SELECT count(*) FROM public.nplus_demo_safe_transfers WHERE user_id=v_actor)<>2 THEN
    RAISE EXCEPTION 'FAIL: valid OUT transfer produced wrong balances/history.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','',false);
  BEGIN
    PERFORM public.nplus_demo_safe_transfer('IN',1.00);
    RAISE EXCEPTION 'TEST_FAILURE: unauthenticated transfer unexpectedly succeeded.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Authentication required.' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'PASS: NaN, infinities, NULL, zero, negative, overflow and excess precision rejected without writes.';
  RAISE NOTICE 'PASS: valid IN/OUT transfers keep wallet, safe balance and both ledgers consistent.';
  RAISE NOTICE 'PASS: unauthenticated transfer denied.';
END
$tests$;

SELECT 'PASS: finite safe-transfer amount guard' AS result;
