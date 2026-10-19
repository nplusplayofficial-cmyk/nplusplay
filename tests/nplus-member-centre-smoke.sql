-- Runs against the disposable PostgreSQL database after applying the feature migration.
DO $qa$
DECLARE
  v_referrer uuid := '00000000-0000-0000-0000-000000000001';
  v_invitee uuid := '00000000-0000-0000-0000-000000000002';
  v_invitee2 uuid := '00000000-0000-0000-0000-000000000004';
  v_invitee3 uuid := '00000000-0000-0000-0000-000000000005';
  v_admin uuid := '00000000-0000-0000-0000-000000000003';
  v_code text;
  v_own_code text;
  v_code2 text;
  v_code3 text;
  v_result jsonb;
  v_tier jsonb;
  v_request uuid;
  v_ticket uuid;
  v_balance numeric;
  v_safe numeric;
BEGIN
  INSERT INTO public.profiles(id,uid,display_name,email,phone,role) VALUES
    (v_referrer,'NPLUS-QA-REFERRER','QA Referrer','referrer@example.test','+910000000001','user'),
    (v_invitee,'NPLUS-QA-INVITEE','QA Invitee','invitee@example.test','+910000000002','user'),
    (v_invitee2,'NPLUS-QA-INVITEE2','QA Invitee 2','invitee2@example.test','+910000000004','user'),
    (v_invitee3,'NPLUS-QA-INVITEE3','QA Invitee 3','invitee3@example.test','+910000000005','user'),
    (v_admin,'NPLUS-QA-ADMIN','QA Admin','admin@example.test','+910000000003','admin');

  INSERT INTO public.demo_wallets(user_id,balance) VALUES (v_referrer,108),(v_invitee,108),(v_invitee2,108),(v_invitee3,108);
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

  SELECT referral_code INTO v_code2 FROM public.nplus_demo_referral_codes WHERE user_id=v_invitee2;
  SELECT referral_code INTO v_code3 FROM public.nplus_demo_referral_codes WHERE user_id=v_invitee3;
  IF v_code2 IS NULL OR v_code3 IS NULL OR v_code2=v_code OR v_code3=v_code OR v_code2=v_code3 THEN
    RAISE EXCEPTION 'FAIL: each invited account must have a unique referral code';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_invitee2::text, true);
  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: second invitee could not attach referrer code: %',v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_invitee3::text, true);
  v_result := public.nplus_demo_referral_apply(v_code);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: third invitee could not attach referrer code: %',v_result;
  END IF;

  -- Approval in the generic deposit_requests table must NOT trigger an invitation payout.
  -- This avoids coupling a possible real-money deposit workflow to demo reward logic.
  INSERT INTO public.deposit_requests(user_id,amount,status) VALUES(v_invitee,500,'pending') RETURNING id INTO v_request;
  UPDATE public.deposit_requests SET status='approved', reviewed_at=now(), reviewed_by=v_admin WHERE id=v_request;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 108 THEN
    RAISE EXCEPTION 'FAIL: a generic deposit request incorrectly triggered a referral reward; balance=%',v_balance;
  END IF;
  IF (SELECT status FROM public.nplus_demo_referrals WHERE referred_user_id=v_invitee) <> 'pending' THEN
    RAISE EXCEPTION 'FAIL: generic deposit approval incorrectly changed referral qualification status';
  END IF;
  UPDATE public.deposit_requests SET status='approved', reviewed_at=now(), reviewed_by=v_admin WHERE id=v_request;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 108 THEN RAISE EXCEPTION 'FAIL: repeated deposit approval changed inviter balance'; END IF;

  -- Dedicated Admin qualification requires 500 virtual demo points and is independent
  -- of the generic deposit approval above.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_result := public.nplus_demo_admin_qualify_referral(v_invitee,499);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'qualification_below_minimum' THEN
    RAISE EXCEPTION 'FAIL: qualification below the screenshot 500-point threshold was not rejected: %',v_result;
  END IF;
  v_result := public.nplus_demo_admin_qualify_referral(v_invitee,500);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: 500-point virtual demo qualification failed: %',v_result;
  END IF;
  v_result := public.nplus_demo_admin_qualify_referral(v_invitee,500);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'already_qualified' THEN
    RAISE EXCEPTION 'FAIL: invitee qualification replay was not rejected: %',v_result;
  END IF;
  v_result := public.nplus_demo_admin_qualify_referral(v_invitee2,500);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: second invitee qualification failed: %',v_result;
  END IF;
  v_result := public.nplus_demo_admin_qualify_referral(v_invitee3,500);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: third invitee qualification failed: %',v_result;
  END IF;

  -- Inviter gets one independently claimable bonus per tier, only when every invite
  -- in that tier is verified. The screenshot values are virtual demo points only.
  PERFORM set_config('request.jwt.claim.sub', v_referrer::text, true);
  v_result := public.nplus_demo_referral_bonus_dashboard();
  IF (v_result->>'invited_count')::integer <> 3 OR (v_result->>'qualified_count')::integer <> 3 THEN
    RAISE EXCEPTION 'FAIL: referral dashboard invitation qualification totals are incorrect: %',v_result;
  END IF;
  SELECT value INTO v_tier FROM jsonb_array_elements(v_result->'tiers') WHERE (value->>'invitee_count')::integer=3;
  IF v_tier IS NULL OR coalesce((v_tier->>'claimable')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: 3-invite tier should be claimable after 3 verified invites: %',v_tier;
  END IF;
  SELECT value INTO v_tier FROM jsonb_array_elements(v_result->'tiers') WHERE (value->>'invitee_count')::integer=10;
  IF v_tier IS NULL OR coalesce((v_tier->>'claimable')::boolean,true) IS TRUE THEN
    RAISE EXCEPTION 'FAIL: 10-invite tier must remain unavailable with only 3 invited accounts: %',v_tier;
  END IF;

  v_result := public.nplus_demo_claim_referral_bonus(1);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE OR (v_result->>'reward_amount')::numeric <> 55 THEN
    RAISE EXCEPTION 'FAIL: screenshot tier 1 must credit 55 virtual demo points: %',v_result;
  END IF;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 163 THEN RAISE EXCEPTION 'FAIL: tier 1 demo balance should be 163, got %',v_balance; END IF;
  v_result := public.nplus_demo_claim_referral_bonus(1);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'already_claimed' THEN
    RAISE EXCEPTION 'FAIL: repeat tier 1 claim must be rejected: %',v_result;
  END IF;
  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 163 THEN RAISE EXCEPTION 'FAIL: repeat tier 1 claim changed the wallet balance'; END IF;

  v_result := public.nplus_demo_claim_referral_bonus(3);
  IF coalesce((v_result->>'success')::boolean,false) IS NOT TRUE OR (v_result->>'reward_amount')::numeric <> 155 THEN
    RAISE EXCEPTION 'FAIL: screenshot tier 3 must credit 155 virtual demo points: %',v_result;
  END IF;
  v_result := public.nplus_demo_claim_referral_bonus(3);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'already_claimed' THEN
    RAISE EXCEPTION 'FAIL: repeat tier 3 claim must be rejected: %',v_result;
  END IF;
  v_result := public.nplus_demo_claim_referral_bonus(10);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'not_eligible' THEN
    RAISE EXCEPTION 'FAIL: tier 10 must not be claimable with only 3 qualified invites: %',v_result;
  END IF;

  -- Screenshot rule: a tier cannot be claimed outside the promotion period.
  UPDATE public.nplus_demo_referral_campaign
  SET ends_at = now() - interval '1 minute'
  WHERE campaign_id = 1;
  v_result := public.nplus_demo_claim_referral_bonus(10);
  IF coalesce((v_result->>'success')::boolean,true) IS TRUE OR v_result->>'reason' <> 'event_expired' THEN
    RAISE EXCEPTION 'FAIL: invitation claim must be rejected after the event ends: %',v_result;
  END IF;
  UPDATE public.nplus_demo_referral_campaign
  SET starts_at = '2000-01-01 00:00:00+00', ends_at = '2099-01-01 00:00:00+00'
  WHERE campaign_id = 1;

  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_referrer;
  IF v_balance <> 318 THEN RAISE EXCEPTION 'FAIL: tier claims should award exactly 210 demo points once each; balance=%',v_balance; END IF;
  IF (SELECT count(*) FROM public.demo_wallet_transactions WHERE user_id=v_referrer AND type='REFERRAL_REWARD') <> 2 THEN
    RAISE EXCEPTION 'FAIL: tier claims should write exactly two referral reward ledger records';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_invitee::text, true);
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
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_result) AS report_row
    WHERE report_row->>'referred_user_id' = v_invitee::text
  ) THEN
    RAISE EXCEPTION 'FAIL: Admin referral report must expose the actual invited profile UUID for qualification.';
  END IF;
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
  IF has_table_privilege('authenticated','public.nplus_demo_referral_qualifications','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_referral_bonus_claims','SELECT') THEN
    RAISE EXCEPTION 'FAIL: authenticated users can read private qualification or claim tables directly';
  END IF;
  IF has_function_privilege('anon','public.nplus_demo_admin_qualify_referral(uuid,numeric)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute Admin qualification RPC';
  END IF;
  IF has_function_privilege('anon','public.nplus_demo_claim_referral_bonus(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute referral claim RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.nplus_demo_claim_referral_bonus(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated users cannot call their own referral claim RPC';
  END IF;
END;
$qa$;

SELECT 'N+ Daman-tier referral, duplicate-claim, gift, safe, attendance, and support DB smoke QA passed' AS result;
