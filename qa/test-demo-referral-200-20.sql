\set ON_ERROR_STOP on

-- Isolated PostgreSQL regression for the approved 200/20 virtual demo referral rule.
-- The trigger is exercised with synthetic records; the entire synthetic transaction rolls back.

DO $roles$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY,email text);
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $uid$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $uid$;

CREATE TABLE IF NOT EXISTS public.profiles(
 id uuid PRIMARY KEY REFERENCES auth.users(id),
 uid text NOT NULL,
 display_name text,
 email text,
 phone text,
 role text NOT NULL DEFAULT 'user'
);
CREATE TABLE IF NOT EXISTS public.demo_wallets(
 user_id uuid PRIMARY KEY REFERENCES auth.users(id),
 balance numeric(18,2) NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.demo_wallet_transactions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL,
 delta numeric(18,2) NOT NULL,
 balance_before numeric(18,2) NOT NULL,
 balance_after numeric(18,2) NOT NULL,
 type text NOT NULL,
 source text,
 note text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.deposit_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 amount numeric(12,2) NOT NULL,
 status text NOT NULL DEFAULT 'pending',
 created_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz,
 reviewed_by uuid,
 request_token uuid,
 payment_method text NOT NULL DEFAULT 'DEMO_CREDIT',
 request_note text
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_codes(
 user_id uuid PRIMARY KEY REFERENCES public.profiles(id),
 code text NOT NULL UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now(),
 referral_code text UNIQUE
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_referrals(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 referrer_user_id uuid NOT NULL REFERENCES public.profiles(id),
 referred_user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id),
 referral_code text NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','qualified','rewarded')),
 qualifying_request_id uuid UNIQUE REFERENCES public.deposit_requests(id) ON DELETE SET NULL,
 qualifying_request_amount numeric(12,2),
 reward_credits numeric(12,2) NOT NULL DEFAULT 20 CHECK(reward_credits=20),
 created_at timestamptz NOT NULL DEFAULT now(),
 qualified_at timestamptz,
 rewarded_at timestamptz,
 user_id uuid,
 reward_amount numeric(12,2) NOT NULL DEFAULT 0,
 awarded_at timestamptz,
 CONSTRAINT nplus_demo_referrals_reward_state_check CHECK (
  (status='pending' AND qualifying_request_id IS NULL AND qualified_at IS NULL AND rewarded_at IS NULL AND reward_amount=0)
  OR (status='qualified' AND qualifying_request_id IS NULL AND qualified_at IS NOT NULL AND rewarded_at IS NULL AND reward_amount=0)
  OR (status='rewarded' AND qualifying_request_id IS NOT NULL AND qualified_at IS NOT NULL AND rewarded_at IS NOT NULL AND reward_amount=20)
 )
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_qualifications(
 referred_user_id uuid PRIMARY KEY REFERENCES public.profiles(id),
 referrer_user_id uuid NOT NULL REFERENCES public.profiles(id),
 qualifying_virtual_amount numeric(14,2) NOT NULL,
 verified_by uuid NOT NULL REFERENCES public.profiles(id),
 verified_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_bonus_claims(user_id uuid, invitee_count integer, reward_amount numeric);
CREATE TABLE IF NOT EXISTS public.nplus_demo_gift_codes(code text);
CREATE TABLE IF NOT EXISTS public.nplus_demo_gift_claims(id uuid);
CREATE TABLE IF NOT EXISTS public.nplus_demo_attendance_claims(id uuid);

CREATE OR REPLACE FUNCTION public.nplus_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $fn$ SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND lower(coalesce(role,''))='admin') $fn$;
CREATE OR REPLACE FUNCTION public.nplus_demo_ensure_referral_code(p_user_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $fn$ SELECT referral_code FROM public.nplus_demo_referral_codes WHERE user_id=p_user_id $fn$;

\ir ../supabase/migrations/20261028120100_demo_referral_200_20_rule.sql

BEGIN;
DO $tests$
DECLARE
 v_admin uuid := 'cc111111-1111-4111-8111-111111111111';
 v_referrer uuid := 'cc222222-2222-4222-8222-222222222222';
 v_invited uuid := 'cc333333-3333-4333-8333-333333333333';
 v_other_invited uuid := 'cc444444-4444-4444-8444-444444444444';
 v_other_referrer uuid := 'cc555555-5555-4555-8555-555555555555';
 v_result jsonb;
 v_request uuid;
 v_before numeric;
 v_after numeric;
 v_ledger_before bigint;
 v_ledger_after bigint;
 v_count bigint;
 v_status text;
BEGIN
 INSERT INTO auth.users(id,email) VALUES
  (v_admin,'demo-ref-admin@example.invalid'),
  (v_referrer,'demo-referrer@example.invalid'),
  (v_invited,'demo-invitee@example.invalid'),
  (v_other_invited,'demo-invitee2@example.invalid'),
  (v_other_referrer,'demo-referrer2@example.invalid');
 INSERT INTO public.profiles(id,uid,display_name,email,role) VALUES
  (v_admin,'REFADMIN','Referral Admin','demo-ref-admin@example.invalid','admin'),
  (v_referrer,'REFERRER','Demo Referrer','demo-referrer@example.invalid','user'),
  (v_invited,'INVITEE','Demo Invitee','demo-invitee@example.invalid','user'),
  (v_other_invited,'INVITEE2','Demo Invitee 2','demo-invitee2@example.invalid','user'),
  (v_other_referrer,'REFERRER2','Demo Referrer 2','demo-referrer2@example.invalid','user');
 INSERT INTO public.demo_wallets(user_id,balance) VALUES
  (v_referrer,50),(v_invited,500),(v_other_referrer,60),(v_other_invited,50);
 INSERT INTO public.nplus_demo_referral_codes(user_id,code,referral_code) VALUES
  (v_referrer,'NPREFERRER01','NPREFERRER01'),(v_other_referrer,'NPREFERRER02','NPREFERRER02');

 -- Valid attribution, self-referral denial, and a second code cannot replace a saved referrer.
 PERFORM set_config('request.jwt.claim.sub',v_invited::text,true);
 v_result:=public.nplus_demo_referral_apply('NPREFERRER01');
 IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE OR v_result->>'status'<>'pending'
    OR (v_result->>'qualifying_virtual_credits')::numeric<>200
    OR (v_result->>'reward_virtual_points')::numeric<>20 THEN
  RAISE EXCEPTION 'FAIL: referral attribution did not expose the approved 200/20 demo contract.';
 END IF;
 v_result:=public.nplus_demo_referral_apply('NPREFERRER02');
 IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'already_referred' THEN
  RAISE EXCEPTION 'FAIL: existing referral attribution was replaced.';
 END IF;
 PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
 v_result:=public.nplus_demo_referral_apply('NPREFERRER01');
 IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'self_referral' THEN
  RAISE EXCEPTION 'FAIL: self-referral was not rejected.';
 END IF;

 -- An unapproved request does not pay; a 199.99 approved request does not pay.
 INSERT INTO public.deposit_requests(id,user_id,amount,status,payment_method)
 VALUES ('cc611111-1111-4111-8111-111111111111',v_invited,250,'pending','DEMO_CREDIT');
 SELECT balance INTO v_before FROM public.demo_wallets WHERE user_id=v_referrer;
 UPDATE public.deposit_requests SET status='approved',reviewed_by=v_admin,reviewed_at=now()
 WHERE id='cc611111-1111-4111-8111-111111111111';
 SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_referrer;
 IF v_after<>v_before+20 THEN RAISE EXCEPTION 'FAIL: qualifying amount did not award exactly 20'; END IF;

 -- Retry by changing other request columns cannot pay twice, even if status is named again.
 SELECT count(*) INTO v_count FROM public.demo_wallet_transactions
 WHERE user_id=v_referrer AND type='REFERRAL_REWARD' AND source='REFERRAL';
 UPDATE public.deposit_requests SET status='approved',request_note='retry update'
 WHERE id='cc611111-1111-4111-8111-111111111111';
 SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_referrer;
 SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions
 WHERE user_id=v_referrer AND type='REFERRAL_REWARD' AND source='REFERRAL';
 IF v_after<>v_before+20 OR v_ledger_after<>v_count THEN
  RAISE EXCEPTION 'FAIL: duplicate request update issued a second referral reward.';
 END IF;
 SELECT status,qualifying_request_id INTO v_status,v_request
 FROM public.nplus_demo_referrals WHERE referred_user_id=v_invited;
 IF v_status<>'rewarded' OR v_request<>'cc611111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'FAIL: qualifying referral did not persist the rewarded state/request ID.';
 END IF;
 IF (SELECT qualifying_request_amount FROM public.nplus_demo_referrals WHERE referred_user_id=v_invited)<>250
    OR (SELECT reward_amount FROM public.nplus_demo_referrals WHERE referred_user_id=v_invited)<>20 THEN
  RAISE EXCEPTION 'FAIL: qualifying amount/reward amount not stored.';
 END IF;

 -- 200+ amounts using other methods and historical already-qualified referrals are not auto-paid.
 INSERT INTO public.nplus_demo_referrals(user_id,referrer_user_id,referred_user_id,referral_code,status,reward_amount,reward_credits,qualified_at)
 VALUES (v_other_referrer,v_other_referrer,v_other_invited,'NPREFERRER02','qualified',0,20,now());
 INSERT INTO public.deposit_requests(id,user_id,amount,status,payment_method)
 VALUES ('cc622222-2222-4222-8222-222222222222',v_other_invited,500,'pending','CASH');
 SELECT balance INTO v_before FROM public.demo_wallets WHERE user_id=v_other_referrer;
 UPDATE public.deposit_requests SET status='approved',reviewed_by=v_admin,reviewed_at=now()
 WHERE id='cc622222-2222-4222-8222-222222222222';
 SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_other_referrer;
 IF v_after<>v_before OR EXISTS(SELECT 1 FROM public.demo_wallet_transactions WHERE user_id=v_other_referrer AND type='REFERRAL_REWARD') THEN
  RAISE EXCEPTION 'FAIL: non-DEMO_CREDIT or already-qualified referral was paid.';
 END IF;

 -- Manual qualification and old tier claims no longer mint or release virtual points.
 PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
 v_result:=public.nplus_demo_admin_qualify_referral(v_other_invited,500);
 IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'approval_driven' THEN
  RAISE EXCEPTION 'FAIL: manual qualification is not disabled.';
 END IF;
 v_result:=public.nplus_demo_claim_referral_bonus(1);
 IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'tier_claims_disabled' THEN
  RAISE EXCEPTION 'FAIL: old tier claim path still issues rewards.';
 END IF;
 IF has_function_privilege('authenticated','public.nplus_demo_claim_referral_bonus(integer)','EXECUTE') THEN
  RAISE EXCEPTION 'FAIL: signed-in users can execute the obsolete tier-claim RPC.';
 END IF;

 -- Dashboard totals must use the live referral rows, not the obsolete tier-claims table.
 PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
 v_result:=public.nplus_demo_referral_dashboard();
 IF (v_result->>'referral_count')::integer<>1
    OR (v_result->>'rewarded_count')::integer<>1
    OR (v_result->>'total_rewards')::numeric<>20 THEN
  RAISE EXCEPTION 'FAIL: member referral dashboard totals do not match 200/20 reward state.';
 END IF;
 PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
 v_result:=public.nplus_demo_admin_vip_dashboard();
 IF (v_result->>'referrals_rewarded')::integer<>1
    OR (v_result->>'referral_points_awarded')::numeric<>20 THEN
  RAISE EXCEPTION 'FAIL: Admin referral summary does not use current rewarded referral rows.';
 END IF;

 SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_referrer;
 IF v_after<>70 OR
    (SELECT count(*) FROM public.demo_wallet_transactions WHERE user_id=v_referrer AND type='REFERRAL_REWARD' AND source='REFERRAL' AND delta=20)<>1 OR
    EXISTS(SELECT 1 FROM public.demo_wallet_transactions WHERE user_id=v_referrer AND balance_after-balance_before<>delta) THEN
  RAISE EXCEPTION 'FAIL: final wallet/ledger reward invariant failed.';
 END IF;

 RAISE NOTICE 'PASS: 200-point approved DEMO_CREDIT request awards 20 virtual points once';
 RAISE NOTICE 'PASS: self/duplicate referral protection, method/threshold gating, and no back-credit for old qualified status';
 RAISE NOTICE 'PASS: obsolete tier/manual qualification paths cannot mint rewards';
 RAISE NOTICE 'PASS: member/Admin dashboards report referral-row rewards accurately';
END
$tests$;
ROLLBACK;
