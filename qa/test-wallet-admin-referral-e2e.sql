\set ON_ERROR_STOP on
-- N+ PLAY wallet/Admin/referral end-to-end regression for an ISOLATED disposable
-- PostgreSQL database that already has the reconciled current schema/functions.
-- This script inserts only synthetic test identities/rows inside one transaction and
-- ends with ROLLBACK. Do NOT run this on production or a database with live user data.

BEGIN;
DO $wallet_admin_referral_e2e$
DECLARE
  v_admin uuid := 'e4111111-1111-4111-8111-111111111111';
  v_referrer uuid := 'e4222222-2222-4222-8222-222222222222';
  v_invited uuid := 'e4333333-3333-4333-8333-333333333333';
  v_other uuid := 'e4444444-4444-4444-8444-444444444444';
  v_ref_code text;
  v_other_code text;
  v_result jsonb;
  v_retry jsonb;
  v_token uuid := 'e5111111-1111-4111-8111-111111111111';
  v_token_other uuid := 'e5222222-2222-4222-8222-222222222222';
  v_withdraw_token uuid := 'e5333333-3333-4333-8333-333333333333';
  v_withdraw_retry uuid := 'e5444444-4444-4444-8444-444444444444';
  v_deposit_id uuid;
  v_reject_id uuid;
  v_withdraw_id uuid;
  v_balance_before numeric;
  v_balance_after numeric;
  v_referrer_before numeric;
  v_referrer_after numeric;
  v_ledger_before bigint;
  v_ledger_after bigint;
  v_count bigint;
  v_expected_bonus numeric;
  v_referral_status text;
  v_referral_reward numeric;
  v_referral_request uuid;
  v_referral_qualified_at timestamptz;
  v_referral_rewarded_at timestamptz;
  v_error text;
BEGIN
  -- All created users and generated profile/wallet/referral records are rolled back.
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
    (v_admin,'nplus-e2e-admin@example.invalid','{"display_name":"Wallet QA Admin"}'::jsonb),
    (v_referrer,'nplus-e2e-referrer@example.invalid','{"display_name":"Wallet QA Referrer"}'::jsonb),
    (v_invited,'nplus-e2e-invited@example.invalid','{"display_name":"Wallet QA Invitee"}'::jsonb),
    (v_other,'nplus-e2e-other@example.invalid','{"display_name":"Wallet QA Other"}'::jsonb);

  IF (SELECT count(*) FROM public.profiles WHERE id IN (v_admin,v_referrer,v_invited,v_other))<>4
     OR (SELECT count(*) FROM public.demo_wallets WHERE user_id IN (v_admin,v_referrer,v_invited,v_other))<>4 THEN
    RAISE EXCEPTION 'FAIL: Auth user trigger did not create exactly one profile and wallet per test user';
  END IF;

  -- The direct test connection is the trusted database owner. Clear the actor JWT and
  -- set a trusted DB role claim so the profile-role guard permits fixture setup.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  UPDATE public.profiles SET role='admin' WHERE id=v_admin;

  -- Stable, unique per-account referral codes, self-referral rejection and invalid code.
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  v_result := public.nplus_demo_referral_dashboard();
  v_ref_code := v_result->>'referral_code';
  IF v_ref_code IS NULL OR length(v_ref_code)<4 THEN
    RAISE EXCEPTION 'FAIL: referrer did not receive a unique referral code';
  END IF;

  v_result := public.nplus_demo_referral_apply(v_ref_code);
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'self_referral' THEN
    RAISE EXCEPTION 'FAIL: self-referral was not rejected';
  END IF;
  v_result := public.nplus_demo_referral_apply('NO_SUCH_CODE_WALLET_QA_2026');
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'code_not_found' THEN
    RAISE EXCEPTION 'FAIL: invalid referral code was not rejected';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_other::text,true);
  v_other_code := public.nplus_demo_referral_dashboard()->>'referral_code';
  IF v_other_code IS NULL OR v_other_code=v_ref_code THEN
    RAISE EXCEPTION 'FAIL: two accounts did not receive distinct referral codes';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_invited::text,true);
  v_result := public.nplus_demo_referral_apply(v_ref_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: valid referral attribution was not saved';
  END IF;
  v_retry := public.nplus_demo_referral_apply(v_ref_code);
  IF coalesce((v_retry->>'success')::boolean,true) OR v_retry->>'reason'<>'already_referred' THEN
    RAISE EXCEPTION 'FAIL: duplicate referral attribution was accepted';
  END IF;
  v_retry := public.nplus_demo_referral_apply(v_other_code);
  IF coalesce((v_retry->>'success')::boolean,true) OR v_retry->>'reason'<>'already_referred' THEN
    RAISE EXCEPTION 'FAIL: referral attribution changed after first attachment';
  END IF;

  -- Demo deposit creation is idempotent and does not immediately credit the wallet.
  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_invited;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_invited;
  v_result := public.nplus_create_demo_deposit_request(500,v_token,'Wallet QA qualifying demo request');
  v_deposit_id := (v_result->>'request_id')::uuid;
  IF v_result->>'status'<>'pending' OR coalesce((v_result->>'wallet_changed')::boolean,true) THEN
    RAISE EXCEPTION 'FAIL: a new deposit request changed wallet or did not remain pending';
  END IF;
  v_retry := public.nplus_create_demo_deposit_request(500,v_token,'Wallet QA duplicate request');
  IF coalesce((v_retry->>'duplicate_request')::boolean,false) IS NOT TRUE
     OR (v_retry->>'request_id')::uuid<>v_deposit_id THEN
    RAISE EXCEPTION 'FAIL: deposit retry did not recover the existing request';
  END IF;

  v_error := '';
  BEGIN
    PERFORM public.nplus_create_demo_deposit_request(501,v_token,'Wallet QA token amount mismatch');
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%token was already used with a different amount%' THEN
    RAISE EXCEPTION 'FAIL: deposit token reuse with a different amount was not rejected';
  END IF;

  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_invited;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_invited;
  IF v_balance_after<>v_balance_before OR v_ledger_after<>v_ledger_before THEN
    RAISE EXCEPTION 'FAIL: merely submitting/retrying a demo deposit changed wallet/ledger';
  END IF;

  -- A non-admin cannot approve a deposit. Admin approval credits the exact amount once.
  PERFORM set_config('request.jwt.claim.sub',v_other::text,true);
  v_result := public.nplus_create_demo_deposit_request(250,v_token_other,'Wallet QA rejection request');
  v_reject_id := (v_result->>'request_id')::uuid;
  v_error := '';
  BEGIN
    PERFORM public.nplus_approve_deposit(v_deposit_id);
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%Admin access required%' THEN
    RAISE EXCEPTION 'FAIL: non-admin deposit approval was not denied';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  SELECT balance INTO v_referrer_before FROM public.demo_wallets WHERE user_id=v_referrer;
  v_result := public.nplus_approve_deposit(v_deposit_id);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR (v_result->>'balance_after')::numeric<>(v_balance_before+500) THEN
    RAISE EXCEPTION 'FAIL: Admin approval did not credit exactly the requested demo amount';
  END IF;
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions
   WHERE user_id=v_invited AND type='credit' AND source='admin_deposit' AND delta=500;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: deposit approval did not create exactly one ledger row'; END IF;
  SELECT balance INTO v_referrer_after FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_referrer_after<>v_referrer_before
     OR EXISTS (SELECT 1 FROM public.demo_wallet_transactions WHERE user_id=v_referrer AND type='REFERRAL_REWARD' AND source='REFERRAL') THEN
    RAISE EXCEPTION 'FAIL: approving a deposit automatically rewarded a referrer before Admin qualification/tier claim';
  END IF;

  v_error := '';
  BEGIN
    PERFORM public.nplus_approve_deposit(v_deposit_id);
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%already been reviewed%' THEN
    RAISE EXCEPTION 'FAIL: repeated deposit approval was not rejected';
  END IF;

  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_other;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_other;
  v_result := public.nplus_reject_deposit(v_reject_id);
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_other;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_other;
  IF v_result->>'status'<>'rejected' OR v_balance_after<>v_balance_before OR v_ledger_after<>v_ledger_before THEN
    RAISE EXCEPTION 'FAIL: deposit rejection changed the wallet or ledger';
  END IF;

  -- Positive Admin wallet adjustment is authorized, bounded, and ledger-backed.
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  v_result := public.nplus_admin_adjust_demo_wallet(v_referrer,5,'E2E admin adjustment');
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR (v_result->>'after')::numeric<>v_balance_before+5 THEN
    RAISE EXCEPTION 'FAIL: Admin demo wallet adjustment did not apply the expected delta';
  END IF;
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  IF v_balance_after<>v_balance_before+5 OR v_ledger_after<>v_ledger_before+1 THEN
    RAISE EXCEPTION 'FAIL: Admin wallet adjustment did not produce one balanced ledger row';
  END IF;
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions
  WHERE user_id=v_referrer AND type='ADMIN_ADJUSTMENT' AND source='NPLUS_ADMIN' AND delta=5;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: Admin adjustment ledger entry count is not exactly one'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_other::text,true);
  v_error := '';
  BEGIN
    PERFORM public.nplus_admin_adjust_demo_wallet(v_referrer,1,'non-admin attempt');
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%Admin access required%' THEN
    RAISE EXCEPTION 'FAIL: non-admin wallet adjustment was not denied';
  END IF;

  -- Approved demo credits do not automatically pay the referrer; qualification is an
  -- explicit Admin verification step, once, after a >=500 virtual-credit check.
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result := public.nplus_demo_admin_qualify_referral(v_invited,499.99);
  IF coalesce((v_result->>'success')::boolean,true) OR v_result->>'reason'<>'qualification_below_minimum' THEN
    RAISE EXCEPTION 'FAIL: below-minimum referral qualification was accepted';
  END IF;
  v_result := public.nplus_demo_admin_qualify_referral(v_invited,500);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: Admin could not verify a qualifying referral';
  END IF;

  -- "qualified" is a verification state only. It must not count as an already-paid
  -- referral-row reward; tier claims are credited separately and once.
  SELECT status, reward_amount, qualifying_request_id, qualified_at, rewarded_at
    INTO v_referral_status, v_referral_reward, v_referral_request,
         v_referral_qualified_at, v_referral_rewarded_at
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = v_invited;
  IF v_referral_status IS DISTINCT FROM 'qualified'
     OR v_referral_reward IS DISTINCT FROM 0.00
     OR v_referral_request IS NOT NULL
     OR v_referral_qualified_at IS NULL
     OR v_referral_rewarded_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: qualified referral lifecycle state does not match contract';
  END IF;

  v_retry := public.nplus_demo_admin_qualify_referral(v_invited,500);
  IF coalesce((v_retry->>'success')::boolean,true) OR v_retry->>'reason'<>'already_qualified' THEN
    RAISE EXCEPTION 'FAIL: referral qualification was accepted more than once';
  END IF;

  -- Referral tier claim is user-scoped, event-window scoped, and exactly once.
  SELECT bonus_amount INTO v_expected_bonus
  FROM public.nplus_demo_referral_tier_rules WHERE invitee_count=1;
  IF v_expected_bonus IS NULL THEN RAISE EXCEPTION 'FAIL: one-invitee demo tier is not configured'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  v_result := public.nplus_demo_claim_referral_bonus(1);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR (v_result->>'reward_amount')::numeric<>v_expected_bonus THEN
    RAISE EXCEPTION 'FAIL: eligible one-invitee bonus tier could not be claimed';
  END IF;
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  IF v_balance_after<>v_balance_before+v_expected_bonus OR v_ledger_after<>v_ledger_before+1 THEN
    RAISE EXCEPTION 'FAIL: referral claim did not create one matching wallet/ledger update';
  END IF;
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions
  WHERE user_id=v_referrer AND type='REFERRAL_REWARD' AND source='REFERRAL' AND delta=v_expected_bonus;
  IF v_count<>1 THEN RAISE EXCEPTION 'FAIL: referral reward ledger entry count is not exactly one'; END IF;

  v_error := '';
  BEGIN
    v_retry := public.nplus_demo_claim_referral_bonus(1);
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error<>'' THEN RAISE EXCEPTION 'FAIL: repeated tier claim raised unexpectedly: %',v_error; END IF;
  IF coalesce((v_retry->>'success')::boolean,true) OR v_retry->>'reason'<>'already_claimed' THEN
    RAISE EXCEPTION 'FAIL: duplicate referral tier claim was not rejected';
  END IF;
  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  IF v_balance_before<>v_balance_after OR v_ledger_before<>v_ledger_after THEN
    RAISE EXCEPTION 'FAIL: duplicate referral tier claim changed wallet/ledger';
  END IF;

  -- Demo withdrawal is idempotent and never deducts wallet credits. Admin approve/reject
  -- is a status review only; no real payout occurs.
  v_token := 'e5555555-5555-4555-8555-555555555555';
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  v_result := public.nplus_create_demo_withdrawal_request(10,v_withdraw_token,'Wallet QA demo withdrawal');
  v_withdraw_id := (v_result->>'request_id')::uuid;
  IF v_result->>'status'<>'pending'
     OR coalesce((v_result->>'wallet_changed')::boolean,true)
     OR coalesce((v_result->>'cash_paid')::boolean,true) THEN
    RAISE EXCEPTION 'FAIL: withdrawal request changed wallet or indicated cash payout';
  END IF;
  v_retry := public.nplus_create_demo_withdrawal_request(10,v_withdraw_token,'Wallet QA retry');
  IF coalesce((v_retry->>'duplicate_request')::boolean,false) IS NOT TRUE
     OR (v_retry->>'request_id')::uuid<>v_withdraw_id THEN
    RAISE EXCEPTION 'FAIL: withdrawal retry did not recover the original request';
  END IF;

  v_error := '';
  BEGIN
    PERFORM public.nplus_create_demo_withdrawal_request(11,v_withdraw_retry,'second pending request');
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%pending demo request already exists%' THEN
    RAISE EXCEPTION 'FAIL: second pending withdrawal request was not blocked';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_other::text,true);
  v_error := '';
  BEGIN
    PERFORM public.nplus_admin_resolve_demo_withdrawal(v_withdraw_id,'approved','non-admin attempt');
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%Admin access required%' THEN
    RAISE EXCEPTION 'FAIL: non-admin withdrawal review was not denied';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result := public.nplus_admin_resolve_demo_withdrawal(v_withdraw_id,'approved','Status-only demo QA approval');
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE
     OR coalesce((v_result->>'wallet_changed')::boolean,true)
     OR coalesce((v_result->>'cash_paid')::boolean,true) THEN
    RAISE EXCEPTION 'FAIL: Admin withdrawal review was not status-only';
  END IF;
  SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_referrer;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_referrer;
  IF v_balance_after<>v_balance_before OR v_ledger_after<>v_ledger_before THEN
    RAISE EXCEPTION 'FAIL: withdrawal review changed wallet or ledger';
  END IF;

  -- The generic wallet RPC must block caller-supplied positive credits.
  PERFORM set_config('request.jwt.claim.sub',v_referrer::text,true);
  v_error := '';
  BEGIN
    PERFORM public.nplus_wallet_change(1,'GAME_WIN','QA','forged positive credit');
  EXCEPTION WHEN OTHERS THEN v_error := SQLERRM;
  END;
  IF v_error NOT ILIKE '%Generic wallet credits are disabled%' THEN
    RAISE EXCEPTION 'FAIL: generic wallet RPC did not block a positive credit';
  END IF;

  -- Invariants over synthetic fixture rows before rollback.
  SELECT count(*) INTO v_count FROM public.demo_wallet_transactions
  WHERE user_id IN (v_admin,v_referrer,v_invited,v_other)
    AND balance_after-balance_before<>delta;
  IF v_count<>0 THEN RAISE EXCEPTION 'FAIL: test produced inconsistent ledger arithmetic'; END IF;

  RAISE NOTICE 'PASS: deposit idempotency/approval/rejection and Admin authorization';
  RAISE NOTICE 'PASS: Admin wallet adjustment authorization/ledger and positive-credit protection';
  RAISE NOTICE 'PASS: referral uniqueness/self-referral/qualification/one-time tier claim';
  RAISE NOTICE 'PASS: withdrawal idempotency/status-only Admin review';
END
$wallet_admin_referral_e2e$;

ROLLBACK;
