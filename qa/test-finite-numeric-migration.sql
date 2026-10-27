\set ON_ERROR_STOP on
-- Disposable PostgreSQL runtime test for the actual finite-numeric candidate migration.
-- This file creates only local synthetic schemas/rows; never run against production.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $uid$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$uid$;

CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text NOT NULL);

CREATE FUNCTION public.nplus_is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $is_admin$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role='admin')
$is_admin$;

CREATE TABLE public.deposit_requests(
  id uuid PRIMARY KEY, user_id uuid NOT NULL, amount numeric NOT NULL,
  status text NOT NULL, created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz, reviewed_by uuid
);
CREATE TABLE public.withdrawal_requests(
  id uuid PRIMARY KEY, user_id uuid NOT NULL, amount numeric NOT NULL,
  status text NOT NULL, created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz, reviewed_by uuid, review_note text
);
CREATE TABLE public.nplus_demo_gift_codes(
  code text PRIMARY KEY, amount numeric NOT NULL, active boolean NOT NULL DEFAULT true,
  max_claims integer NOT NULL, claims_count integer NOT NULL DEFAULT 0,
  expires_at timestamptz, created_by uuid
);

CREATE TABLE public.nplus_aviator_demo_rounds(
  id uuid PRIMARY KEY, round_index bigint, status text, flight_starts_at timestamptz,
  crashes_at timestamptz, crash_point numeric, crashed_at timestamptz, created_at timestamptz
);
CREATE TABLE public.nplus_aviator_demo_bets(
  id uuid PRIMARY KEY, round_id uuid, user_id uuid, request_id uuid, slot integer,
  stake numeric, auto_cashout numeric, status text, cashout_multiplier numeric,
  payout numeric, created_at timestamptz, settled_at timestamptz
);
CREATE TABLE public.nplus_moto_demo_rounds(
  id uuid PRIMARY KEY, round_index bigint, starts_at timestamptz, ends_at timestamptz,
  outcome jsonb, status text, settled_at timestamptz
);
CREATE TABLE public.nplus_moto_demo_bets(
  id uuid PRIMARY KEY, round_id uuid, user_id uuid, request_id uuid, selection jsonb,
  stake numeric, fee numeric, amount_debited numeric, payout numeric, status text,
  created_at timestamptz, settled_at timestamptz
);
CREATE TABLE public.nplus_wingo_demo_rounds(
  id uuid PRIMARY KEY, duration_seconds integer, round_index bigint, starts_at timestamptz,
  ends_at timestamptz, outcome jsonb, status text, settled_at timestamptz
);
CREATE TABLE public.nplus_wingo_demo_bets(
  id uuid PRIMARY KEY, round_id uuid, user_id uuid, request_id uuid, selection jsonb,
  stake numeric, payout numeric, status text, created_at timestamptz, settled_at timestamptz
);

-- Install the same SQL file intended for the eventual reviewed production migration.
\ir ../supabase/migrations/20261027150000_guard_finite_numeric_rpc_inputs.sql

INSERT INTO public.profiles(id,role) VALUES
  ('11111111-1111-4111-8111-111111111111','admin'),
  ('22222222-2222-4222-8222-222222222222','user');
INSERT INTO public.deposit_requests(id,user_id,amount,status)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        '22222222-2222-4222-8222-222222222222','NaN'::numeric,'pending');
INSERT INTO public.nplus_demo_gift_codes(code,amount,active,max_claims,claims_count)
VALUES ('QA-NAN','NaN'::numeric,true,5,0);

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

DO $finite_tests$
DECLARE
  v_amount numeric;
  v_label text;
  v_result jsonb;
  v_message text;
BEGIN
  -- Reject all PostgreSQL non-finite forms plus NULL before narrowing or writes.
  FOREACH v_amount IN ARRAY ARRAY['NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric,NULL::numeric] LOOP
    BEGIN
      PERFORM public.nplus_create_demo_deposit_request(v_amount,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','QA');
      RAISE EXCEPTION 'FAIL: deposit request accepted a non-finite/NULL amount';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Demo deposit amount must be finite.' THEN RAISE; END IF;
    END;

    BEGIN
      PERFORM public.nplus_create_demo_withdrawal_request(v_amount,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','QA');
      RAISE EXCEPTION 'FAIL: withdrawal request accepted a non-finite/NULL amount';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Demo withdrawal request amount must be finite.' THEN RAISE; END IF;
    END;

    v_result := public.nplus_demo_admin_create_gift_code('QA-GIFT',v_amount,5,NULL);
    IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
      RAISE EXCEPTION 'FAIL: Admin gift-code RPC accepted a non-finite/NULL amount: %', v_result;
    END IF;

    BEGIN
      PERFORM public.nplus_aviator_demo_place_bet(
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',0,v_amount,
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',1.50);
      RAISE EXCEPTION 'FAIL: Aviator RPC accepted a non-finite/NULL stake';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Demo stake must be between 1 and 100000 credits.' THEN RAISE; END IF;
    END;

    BEGIN
      PERFORM public.nplus_moto_demo_place_bet(
        '{"kind":"bike","position":"1","value":"1"}'::jsonb,v_amount,
        'ffffffff-ffff-4fff-8fff-ffffffffffff');
      RAISE EXCEPTION 'FAIL: MotoRace RPC accepted a non-finite/NULL stake';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Demo stake must be between 1 and 100000 credits.' THEN RAISE; END IF;
    END;

    BEGIN
      PERFORM public.nplus_wingo_demo_place_bet(
        60,'{"type":"number","value":"1"}'::jsonb,v_amount,
        '99999999-9999-4999-8999-999999999999');
      RAISE EXCEPTION 'FAIL: WINGO RPC accepted a non-finite/NULL stake';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
      IF v_message <> 'Demo stake must be between 1 and 100000 credits.' THEN RAISE; END IF;
    END;

    v_result := public.nplus_demo_safe_transfer('IN',v_amount);
    IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
      RAISE EXCEPTION 'FAIL: safe-transfer RPC accepted a non-finite/NULL amount: %', v_result;
    END IF;

    v_result := public.nplus_demo_admin_qualify_referral(
      '22222222-2222-4222-8222-222222222222',v_amount);
    IF v_result->>'reason' IS DISTINCT FROM 'invalid_verified_amount' THEN
      RAISE EXCEPTION 'FAIL: Admin referral RPC accepted a non-finite/NULL amount: %', v_result;
    END IF;
  END LOOP;

  -- The stored-value guards must reject bad amounts already present in request/code rows.
  BEGIN
    PERFORM public.nplus_approve_deposit('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL: Admin deposit approval accepted a stored NaN amount';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Deposit request amount is invalid.' THEN RAISE; END IF;
  END;

  v_result := public.nplus_demo_gift_redeem('QA-NAN');
  IF v_result->>'reason' IS DISTINCT FROM 'invalid_amount' THEN
    RAISE EXCEPTION 'FAIL: gift redemption accepted a stored NaN amount: %', v_result;
  END IF;

  -- Auto-cashout is separately validated, before any bet/round query.
  BEGIN
    PERFORM public.nplus_aviator_demo_place_bet(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',0,1,
      '12121212-1212-4212-8212-121212121212','Infinity'::numeric);
    RAISE EXCEPTION 'FAIL: Aviator RPC accepted a non-finite auto-cashout';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Auto cash-out must be between 1.01x and 1000x.' THEN RAISE; END IF;
  END;

  -- A normal user must still be denied by the Admin-only referral guard.
  PERFORM set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
  BEGIN
    PERFORM public.nplus_demo_admin_qualify_referral(
      '33333333-3333-4333-8333-333333333333',500);
    RAISE EXCEPTION 'FAIL: non-admin qualified a referral';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Administrator access required.' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'PASS: finite numeric migration applied in disposable PostgreSQL.';
  RAISE NOTICE 'PASS: deposit/withdrawal, gift-code, Aviator, MotoRace, WINGO, safe-transfer and referral RPCs reject NaN/±Infinity/NULL.';
  RAISE NOTICE 'PASS: stored deposit/gift amount guards and Aviator auto-cashout guard reject malformed values.';
  RAISE NOTICE 'PASS: non-admin referral qualification remains denied.';
END
$finite_tests$;

SELECT 'PASS: runtime finite numeric RPC migration regression' AS result;
