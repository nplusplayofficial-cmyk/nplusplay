\set ON_ERROR_STOP on
-- READ-ONLY live/integration contract assertions for N+ PLAY wallet/admin/referral.
-- Safe for a live SQL editor: catalog and aggregate reads only; no inserts, updates,
-- deletes, DDL, grants, migration edits, or wallet operations are performed.
-- Use qa/test-wallet-admin-referral-e2e.sql only on an isolated disposable database.

DO $wallet_admin_referral_contract$
DECLARE
  v_count bigint;
BEGIN
  -- Every existing profile should have its server-owned demo wallet.
  SELECT count(*) INTO v_count
  FROM public.profiles p
  LEFT JOIN public.demo_wallets w ON w.user_id=p.id
  WHERE w.user_id IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % profile(s) have no demo wallet',v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.demo_wallets WHERE balance < 0;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % negative demo-wallet balance(s)',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.demo_wallet_transactions
  WHERE balance_after - balance_before <> delta;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % wallet transaction(s) violate before + delta = after',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.demo_wallet_transactions t
  LEFT JOIN public.demo_wallets w ON w.user_id=t.user_id
  WHERE w.user_id IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % wallet ledger row(s) have no wallet',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.demo_wallets w
  JOIN (
    SELECT DISTINCT ON (user_id) user_id,balance_after
    FROM public.demo_wallet_transactions
    ORDER BY user_id,created_at DESC,id DESC
  ) t USING(user_id)
  WHERE w.balance <> t.balance_after;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % current wallet(s) do not match their latest ledger entry',v_count;
  END IF;

  -- Requests must enter through server RPCs; client roles cannot directly create
  -- withdrawal requests or mutate/insert/deletes on the deposit queue.
  IF has_table_privilege('anon','public.deposit_requests','INSERT')
     OR has_table_privilege('authenticated','public.deposit_requests','INSERT')
     OR has_table_privilege('authenticated','public.deposit_requests','UPDATE')
     OR has_table_privilege('authenticated','public.deposit_requests','DELETE') THEN
    RAISE EXCEPTION 'FAIL: API role has direct write privilege on deposit_requests';
  END IF;
  IF has_table_privilege('anon','public.withdrawal_requests','INSERT')
     OR has_table_privilege('authenticated','public.withdrawal_requests','INSERT')
     OR has_table_privilege('authenticated','public.withdrawal_requests','UPDATE')
     OR has_table_privilege('authenticated','public.withdrawal_requests','DELETE') THEN
    RAISE EXCEPTION 'FAIL: API role has direct write privilege on withdrawal_requests';
  END IF;

  IF has_function_privilege('anon','public.nplus_approve_deposit(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_reject_deposit(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_admin_adjust_demo_wallet(uuid,numeric,text)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_admin_resolve_demo_withdrawal(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute one or more Admin wallet/request RPCs';
  END IF;

  IF NOT has_function_privilege('authenticated','public.nplus_create_demo_deposit_request(numeric,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_create_demo_withdrawal_request(numeric,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_approve_deposit(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_reject_deposit(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_admin_resolve_demo_withdrawal(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: an expected authenticated RPC EXECUTE grant is missing';
  END IF;

  -- Client reads of internal referral state stay behind SECURITY DEFINER RPCs.
  IF has_table_privilege('anon','public.nplus_demo_referrals','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_referrals','SELECT')
     OR has_table_privilege('anon','public.nplus_demo_referral_codes','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_referral_codes','SELECT')
     OR has_table_privilege('anon','public.nplus_demo_referral_bonus_claims','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_referral_bonus_claims','SELECT') THEN
    RAISE EXCEPTION 'FAIL: direct referral storage read is exposed to an API role';
  END IF;

  IF has_function_privilege('anon','public.nplus_demo_referral_apply(text)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_demo_referral_dashboard()','EXECUTE')
     OR has_function_privilege('anon','public.nplus_demo_claim_referral_bonus(integer)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_demo_admin_qualify_referral(uuid,numeric)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon can execute a referral RPC';
  END IF;

  SELECT count(*) INTO v_count FROM public.nplus_demo_referral_tier_rules
  WHERE invitee_count > 0 AND qualification_amount > 0 AND bonus_amount > 0;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: no valid referral tiers are configured';
  END IF;

  -- Every demo referral reward ledger row should correspond to a one-time tier claim.
  SELECT count(*) INTO v_count
  FROM public.demo_wallet_transactions t
  LEFT JOIN public.nplus_demo_referral_bonus_claims c
    ON c.user_id=t.user_id AND c.reward_amount=t.delta
  WHERE t.source='REFERRAL' AND t.type='REFERRAL_REWARD' AND c.user_id IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % referral reward ledger row(s) lack a matching tier claim',v_count;
  END IF;

  RAISE NOTICE 'PASS: read-only wallet, Admin RPC, referral privilege, and ledger invariants';
END
$wallet_admin_referral_contract$;
