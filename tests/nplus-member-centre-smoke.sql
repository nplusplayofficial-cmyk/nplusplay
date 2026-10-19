-- Runs against the disposable PostgreSQL database after applying the feature migration.
DO $qa$
DECLARE
  v_referrer uuid := '00000000-0000-0000-0000-000000000001';
  v_invitee uuid := '00000000-0000-0000-0000-000000000002';
  v_admin uuid := '00000000-0000-0000-0000-000000000003';
  v_code text;
  v_own_code text;
  v_result jsonb;
  v_request uuid;
  v_ticket uuid;
  v_balance numeric;
  v_safe numeric;
BEGIN
  INSERT INTO public.profiles(id,uid,display_name,email,phone,role) VALUES
    (v_referrer,'NPLUS-QA-REFERRER','QA Referrer','referrer@example.test','+910000000001','user'),
    (v_invitee,'NPLUS-QA-INVITEE','QA Invitee','invitee@example.test','+910000000002','user'),
    (v_admin,'NPLUS-QA-ADMIN','QA Admin','admin@example.test','+910000000003','admin');

  INSERT INTO public.demo_wallets(user_id,balance) VALUES (v_referrer,108),(v_invitee,108);
  SELECT referral_code INTO v_code FROM public.nplus_demo_referral_codes WHERE user_id=v_referrer;
  SELECT referral_code INTO v_own_code FROM public.nplus_demo_referral_codes WHERE user_id=v_invitee;
  IF v_code IS NULL OR v_own_code IS NULL OR v_code=v_own_code THEN
    RAISE EXCEPTION 'FAIL: unique per-account referral codes were not generated';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_invitee::text, true);
  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: valid referral code was not attached: %',v_result;
  END IF;

  v_result := public.nplus_demo_referral_apply(v_own_code);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE
     OR v_result->>'reason' NOT IN ('self_referral','already_referred') THEN
    RAISE EXCEPTION 'FAIL: self/duplicate referral was not rejected: %',v_result;
  END IF;

  INSERT INTO public.deposit_requests(user_id,amount,status) VALUES(v_invitee,200,'pending') RETURNING id INTO v_request;
  UPDATE public.deposit_requests SET status='approved', reviewed_at=now(), reviewed_by=v_admin WHERE id=v_request;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 128 THEN
    RAISE EXCEPTION 'FAIL: qualifying approved referral should credit exactly 20 points; balance=%',v_balance;
  END IF;

  -- Repeating an approved update must not award the same referral twice.
  UPDATE public.deposit_requests SET status='approved', reviewed_at=now(), reviewed_by=v_admin WHERE id=v_request;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 128 THEN RAISE EXCEPTION 'FAIL: referral reward was duplicated'; END IF;

  v_result := public.nplus_demo_gift_redeem('NPLUS50');
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE OR (v_result->>'amount')::numeric <> 50 THEN
    RAISE EXCEPTION 'FAIL: gift code did not award its virtual amount: %',v_result;
  END IF;
  v_result := public.nplus_demo_gift_redeem('NPLUS50');
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'already_claimed' THEN
    RAISE EXCEPTION 'FAIL: duplicate gift redemption was not rejected: %',v_result;
  END IF;

  v_result := public.nplus_demo_safe_transfer('IN',50);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: safe transfer in failed: %',v_result; END IF;
  v_result := public.nplus_demo_safe_transfer('OUT',20);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: safe transfer out failed: %',v_result; END IF;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_invitee;
  SELECT balance INTO v_safe FROM public.nplus_demo_safe_balances WHERE user_id=v_invitee;
  IF v_balance <> 128 OR v_safe <> 30 THEN RAISE EXCEPTION 'FAIL: safe transfer ledger mismatch wallet=% safe=%',v_balance,v_safe; END IF;

  v_result := public.nplus_demo_attendance_claim();
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE OR (v_result->>'reward_amount')::numeric <> 4 THEN
    RAISE EXCEPTION 'FAIL: first daily attendance claim failed: %',v_result;
  END IF;
  v_result := public.nplus_demo_attendance_claim();
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'already_claimed' THEN
    RAISE EXCEPTION 'FAIL: duplicate daily attendance claim was not rejected: %',v_result;
  END IF;

  v_result := public.nplus_demo_support_submit('feedback','QA support request','Testing authenticated support request submission.');
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: support ticket submission failed: %',v_result; END IF;
  v_ticket := (v_result->>'request_id')::uuid;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_result := public.nplus_demo_admin_vip_dashboard();
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: admin VIP dashboard failed: %',v_result; END IF;
  v_result := public.nplus_demo_admin_referrals(100);
  IF v_result IS NULL THEN RAISE EXCEPTION 'FAIL: admin referral report returned NULL'; END IF;
  v_result := public.nplus_demo_admin_create_gift_code('QA-CAMPAIGN',100,2,NULL);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: admin gift-code creation failed: %',v_result; END IF;
  v_result := public.nplus_demo_admin_support_list(100);
  IF v_result IS NULL THEN RAISE EXCEPTION 'FAIL: admin support list returned NULL'; END IF;
  v_result := public.nplus_demo_admin_support_update(v_ticket,'in_review','QA ticket checked.');
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: admin support update failed: %',v_result; END IF;

  -- Direct access to new feature tables must not be granted to browser roles.
  IF has_table_privilege('authenticated','public.nplus_demo_referrals','SELECT') THEN
    RAISE EXCEPTION 'FAIL: authenticated users can read referral table directly';
  END IF;
  IF has_function_privilege('anon','public.nplus_demo_admin_vip_dashboard()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute the admin VIP RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.nplus_demo_referral_dashboard()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated cannot execute referral dashboard RPC';
  END IF;
END;
$qa$;

SELECT 'N+ VIP/referral/gift/safe/attendance/support DB smoke QA passed' AS result;
