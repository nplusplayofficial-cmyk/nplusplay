\set ON_ERROR_STOP on
-- Disposable PostgreSQL test only. This migration and reward are virtual credits, never cash.
\ir ../sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql
\ir ../sql/NPLUS_PLAY_ADMIN_DEPOSIT_ACTIONS.sql
\ir ../sql/NPLUS_PLAY_DEMO_REFERRALS.sql

DO $tests$
DECLARE
  v_admin uuid := '9a000000-0000-4000-8000-000000000001';
  v_referrer uuid := '9a000000-0000-4000-8000-000000000002';
  v_invited uuid := '9a000000-0000-4000-8000-000000000003';
  v_other_referrer uuid := '9a000000-0000-4000-8000-000000000004';
  v_code text;
  v_other_code text;
  v_result jsonb;
  v_d199 jsonb;
  v_d200 jsonb;
  v_d250 jsonb;
  v_request_200 uuid;
  v_balance_before numeric(12,2);
  v_balance_after numeric(12,2);
  v_invited_before numeric(12,2);
  v_invited_after numeric(12,2);
  v_reward_rows integer;
  v_referral_status text;
  v_qualifying_amount numeric(12,2);
  v_count integer;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES
    (v_admin,'referral-admin-qa@example.invalid'),
    (v_referrer,'referral-referrer-qa@example.invalid'),
    (v_invited,'referral-invited-qa@example.invalid'),
    (v_other_referrer,'referral-other-qa@example.invalid')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles(id,uid,display_name,email,phone,role)
  VALUES
    (v_admin,'QA-REF-ADMIN','Referral Admin QA','referral-admin-qa@example.invalid','9000000091','admin'),
    (v_referrer,'QA-REF-OWNER','Referral Owner QA','referral-referrer-qa@example.invalid','9000000092','user'),
    (v_invited,'QA-REF-INVITED','Referred Member QA','referral-invited-qa@example.invalid','9000000093','user'),
    (v_other_referrer,'QA-REF-OTHER','Other Referrer QA','referral-other-qa@example.invalid','9000000094','user')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.demo_wallets(user_id,balance)
  VALUES (v_admin,108.00),(v_referrer,108.00),(v_invited,108.00),(v_other_referrer,108.00)
  ON CONFLICT (user_id) DO NOTHING;

  -- Existing and newly registered profiles must each have unique, stable codes.
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  v_result := public.nplus_demo_referral_dashboard();
  v_code := v_result->>'referral_code';
  IF v_code !~ '^NP[A-Z0-9]{10}$' THEN
    RAISE EXCEPTION 'Referrer code is missing or malformed.';
  END IF;
  IF (public.nplus_demo_referral_dashboard()->>'referral_code') IS DISTINCT FROM v_code THEN
    RAISE EXCEPTION 'Referral code was not stable across repeated reads.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_other_referrer::text,true);
  v_other_code := public.nplus_demo_referral_dashboard()->>'referral_code';
  IF v_other_code = v_code THEN RAISE EXCEPTION 'Referral codes must be unique per account.'; END IF;

  -- Self-referrals and invalid codes do not create attribution.
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason' <> 'self_referral' THEN
    RAISE EXCEPTION 'Self-referral was not rejected.';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_invited::text,true);
  v_result := public.nplus_demo_referral_apply('NP0000000000');
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason' <> 'invalid_code' THEN
    RAISE EXCEPTION 'Invalid referral code was accepted.';
  END IF;

  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR coalesce((v_result->>'applied')::boolean,false) IS NOT TRUE
     OR v_result->>'status' <> 'pending' THEN
    RAISE EXCEPTION 'Valid referral attribution was not saved.';
  END IF;

  -- The referred account cannot swap to another referrer or receive duplicate attribution.
  v_result := public.nplus_demo_referral_apply(v_other_code);
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason' <> 'already_attributed' THEN
    RAISE EXCEPTION 'Referral attribution was changeable after initial attachment.';
  END IF;
  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR coalesce((v_result->>'already_applied')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Retrying the same referral was not idempotent.';
  END IF;

  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT balance INTO v_invited_before FROM public.demo_wallets WHERE user_id=v_invited;

  -- A 199-credit virtual request may be approved, but must not qualify the referral.
  v_d199 := public.nplus_create_demo_deposit_request(199,'a9000000-0000-4000-8000-000000000199','Referral QA - below threshold');
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_approve_deposit((v_d199->>'request_id')::uuid);
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance_after IS DISTINCT FROM v_balance_before THEN
    RAISE EXCEPTION 'Below-threshold demo request incorrectly awarded a referral credit.';
  END IF;

  -- An approved >=200 virtual-credit request qualifies exactly once and awards 20 virtual credits.
  PERFORM set_config('request.jwt.claim.sub',v_invited::text,true);
  v_d200 := public.nplus_create_demo_deposit_request(200,'a9000000-0000-4000-8000-000000000200','Referral QA - qualifying virtual credits');
  v_request_200 := (v_d200->>'request_id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_approve_deposit(v_request_200);

  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance_after IS DISTINCT FROM v_balance_before + 20.00 THEN
    RAISE EXCEPTION 'Qualifying referral did not award exactly 20 virtual credits.';
  END IF;
  SELECT count(*) INTO v_reward_rows
  FROM public.demo_wallet_transactions
  WHERE user_id=v_referrer AND type='REFERRAL_CREDIT' AND source='DEMO_REFERRAL' AND delta=20.00;
  IF v_reward_rows <> 1 THEN RAISE EXCEPTION 'Expected exactly one referral reward ledger entry.'; END IF;

  SELECT status, qualifying_request_amount
  INTO v_referral_status, v_qualifying_amount
  FROM public.nplus_demo_referrals
  WHERE referred_user_id=v_invited;
  IF v_referral_status <> 'rewarded' OR v_qualifying_amount <> 200.00 THEN
    RAISE EXCEPTION 'Referral reward status or qualifying amount was not recorded.';
  END IF;

  -- Further qualifying requests for the same referred account must never pay again.
  PERFORM set_config('request.jwt.claim.sub',v_invited::text,true);
  v_d250 := public.nplus_create_demo_deposit_request(250,'a9000000-0000-4000-8000-000000000250','Referral QA - later request');
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_approve_deposit((v_d250->>'request_id')::uuid);
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_count
  FROM public.demo_wallet_transactions
  WHERE user_id=v_referrer AND type='REFERRAL_CREDIT' AND source='DEMO_REFERRAL' AND delta=20.00;
  IF v_balance_after IS DISTINCT FROM v_balance_before + 20.00 OR v_count <> 1 THEN
    RAISE EXCEPTION 'Repeated qualification generated a second referral reward.';
  END IF;

  SELECT balance INTO v_invited_after FROM public.demo_wallets WHERE user_id=v_invited;
  IF v_invited_after IS DISTINCT FROM v_invited_before + 199.00 + 200.00 + 250.00 THEN
    RAISE EXCEPTION 'Approved virtual-credit requests did not keep the referred wallet consistent.';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  v_result := public.nplus_demo_referral_dashboard();
  IF (v_result->>'total_referrals')::integer <> 1
     OR (v_result->>'rewarded_referrals')::integer <> 1
     OR (v_result->>'pending_referrals')::integer <> 0 THEN
    RAISE EXCEPTION 'Referral dashboard counts do not match recorded state.';
  END IF;

  IF has_function_privilege('anon','public.nplus_demo_referral_apply(text)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_demo_referral_dashboard()','EXECUTE')
     OR has_function_privilege('authenticated','public.nplus_demo_ensure_referral_code(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Referral RPC/helper grants are too broad.';
  END IF;
  IF NOT has_function_privilege('authenticated','public.nplus_demo_referral_apply(text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_demo_referral_dashboard()','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated referral RPC grants are missing.';
  END IF;
  IF has_table_privilege('authenticated','public.nplus_demo_referrals','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_referrals','INSERT')
     OR has_table_privilege('authenticated','public.nplus_demo_referral_codes','SELECT') THEN
    RAISE EXCEPTION 'Direct authenticated table access must remain revoked; use the guarded RPCs.';
  END IF;

  RAISE NOTICE 'PASS: unique stable referral code per account';
  RAISE NOTICE 'PASS: valid/invalid/self-referral and immutable attribution checks';
  RAISE NOTICE 'PASS: <200 virtual-credit request does not qualify';
  RAISE NOTICE 'PASS: admin-approved >=200 demo request awards exactly 20 virtual credits once';
  RAISE NOTICE 'PASS: wallet and reward ledger remain consistent';
  RAISE NOTICE 'PASS: authenticated RPC only; direct table/anon access revoked';
END
$tests$;
