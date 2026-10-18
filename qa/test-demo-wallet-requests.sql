\set ON_ERROR_STOP on
-- Runs only against the disposable CI PostgreSQL database.
\ir ../sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql

DO $tests$
DECLARE
  v_admin uuid := '52525252-5252-4252-8252-525252525252';
  v_user uuid := '63636363-6363-4363-8363-636363636363';
  v_dtoken uuid := 'd1111111-1111-4111-8111-111111111111';
  v_wtoken uuid := 'a2222222-2222-4222-8222-222222222222';
  v_second_token uuid := 'b3333333-3333-4333-8333-333333333333';
  v_d1 jsonb; v_d2 jsonb; v_w1 jsonb; v_w2 jsonb; v_w3 jsonb;
  v_balance numeric; v_before numeric; v_ledger_before bigint; v_ledger_after bigint;
  v_count bigint; v_status text; v_error text;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_admin,'demo-withdraw-admin-qa@example.invalid'),
         (v_user,'demo-withdraw-user-qa@example.invalid');

  INSERT INTO public.profiles(id,uid,display_name,email,phone,role)
  VALUES
    (v_admin,'QA-DWR-ADMIN','Demo Withdrawal Admin QA','demo-withdraw-admin-qa@example.invalid','9000000031','admin'),
    (v_user,'QA-DWR-USER','Demo Withdrawal User QA','demo-withdraw-user-qa@example.invalid','9000000032','user');

  INSERT INTO public.demo_wallets(user_id,balance) VALUES (v_user,108.00);
  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES (v_user,108.00,0.00,108.00,'INITIAL_CREDIT','QA','Initial isolated QA balance');

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  SELECT balance INTO v_before FROM public.demo_wallets WHERE user_id=v_user;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_user;

  v_d1 := public.nplus_create_demo_deposit_request(100,v_dtoken,'Isolated QA');
  v_d2 := public.nplus_create_demo_deposit_request(100,v_dtoken,'Isolated QA');
  IF v_d1->>'status' <> 'pending' OR coalesce((v_d1->>'wallet_changed')::boolean,true) THEN
    RAISE EXCEPTION 'Deposit request changed wallet or did not remain pending.';
  END IF;
  IF coalesce((v_d2->>'duplicate_request')::boolean,false) IS NOT TRUE
     OR v_d1->>'request_id' IS DISTINCT FROM v_d2->>'request_id' THEN
    RAISE EXCEPTION 'Deposit retry did not recover same request.';
  END IF;
  SELECT count(*) INTO v_count FROM public.deposit_requests WHERE user_id=v_user AND request_token=v_dtoken;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Duplicate deposit requests were created.'; END IF;

  BEGIN
    PERFORM public.nplus_create_demo_deposit_request(125,v_dtoken,'Wrong retry amount');
    RAISE EXCEPTION 'QA_ASSERT: different amount token reuse was allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error='QA_ASSERT: different amount token reuse was allowed.'
       OR position('different amount' IN v_error)=0 THEN RAISE; END IF;
  END;

  v_w1 := public.nplus_create_demo_withdrawal_request(10,v_wtoken,'Isolated QA');
  v_w2 := public.nplus_create_demo_withdrawal_request(10,v_wtoken,'Isolated QA');
  IF v_w1->>'status' <> 'pending'
     OR coalesce((v_w1->>'wallet_changed')::boolean,true)
     OR coalesce((v_w1->>'cash_paid')::boolean,true) THEN
    RAISE EXCEPTION 'Withdrawal request changed wallet or claimed cash payout.';
  END IF;
  IF coalesce((v_w2->>'duplicate_request')::boolean,false) IS NOT TRUE
     OR v_w1->>'request_id' IS DISTINCT FROM v_w2->>'request_id' THEN
    RAISE EXCEPTION 'Withdrawal retry did not recover same request.';
  END IF;
  SELECT count(*) INTO v_count FROM public.withdrawal_requests WHERE user_id=v_user AND request_token=v_wtoken;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Duplicate withdrawal requests were created.'; END IF;

  BEGIN
    PERFORM public.nplus_create_demo_withdrawal_request(5,v_second_token,'Second pending request');
    RAISE EXCEPTION 'QA_ASSERT: second pending request was allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error='QA_ASSERT: second pending request was allowed.'
       OR position('pending demo request already exists' IN v_error)=0 THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.nplus_admin_resolve_demo_withdrawal((v_w1->>'request_id')::uuid,'approved','Non-admin QA');
    RAISE EXCEPTION 'QA_ASSERT: non-admin resolved request.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error='QA_ASSERT: non-admin resolved request.'
       OR position('Admin access required.' IN v_error)=0 THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_admin_resolve_demo_withdrawal((v_w1->>'request_id')::uuid,'approved','Status-only QA approval');
  SELECT status INTO v_status FROM public.withdrawal_requests WHERE id=(v_w1->>'request_id')::uuid;
  IF v_status <> 'approved' THEN RAISE EXCEPTION 'Admin approval did not update status.'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  v_w3 := public.nplus_create_demo_withdrawal_request(12,v_second_token,'Second isolated QA request');
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_admin_resolve_demo_withdrawal((v_w3->>'request_id')::uuid,'rejected','Status-only QA rejection');
  SELECT status INTO v_status FROM public.withdrawal_requests WHERE id=(v_w3->>'request_id')::uuid;
  IF v_status <> 'rejected' THEN RAISE EXCEPTION 'Admin rejection did not update status.'; END IF;

  SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_user;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_user;
  IF v_balance IS DISTINCT FROM v_before OR v_ledger_after <> v_ledger_before THEN
    RAISE EXCEPTION 'Requests/Admin review changed wallet or ledger.';
  END IF;

  IF has_function_privilege('anon','public.nplus_create_demo_deposit_request(numeric,uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_create_demo_withdrawal_request(numeric,uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.nplus_admin_resolve_demo_withdrawal(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous EXECUTE is granted on demo RPCs.';
  END IF;
  IF NOT has_function_privilege('authenticated','public.nplus_create_demo_deposit_request(numeric,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_create_demo_withdrawal_request(numeric,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_admin_resolve_demo_withdrawal(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Expected authenticated RPC grants are missing.';
  END IF;

  RAISE NOTICE 'PASS: deposit idempotency and amount-token binding';
  RAISE NOTICE 'PASS: withdrawal idempotency and one-pending-request rule';
  RAISE NOTICE 'PASS: non-admin review blocked; Admin approve/reject status-only';
  RAISE NOTICE 'PASS: wallet balance and ledger unchanged';
  RAISE NOTICE 'PASS: anon EXECUTE revoked';
END
$tests$;
