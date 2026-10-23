\set ON_ERROR_STOP on

-- Read-only catalog regression. Run against an isolated staging database AFTER applying
-- the two candidate SQL files. Does not touch user rows or wallet balances.

DO $security_followup$
DECLARE
  v_auth_oid oid;
  v_policy pg_policy%ROWTYPE;
  v_expr text;
  v_count integer;
BEGIN
  SELECT oid INTO v_auth_oid FROM pg_roles WHERE rolname = 'authenticated';
  IF v_auth_oid IS NULL THEN
    RAISE EXCEPTION 'FAIL: authenticated role missing';
  END IF;

  -- Public read remains available to the Deposit page, but public writes must be gone.
  IF NOT has_table_privilege('anon','public.payment_settings','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon can no longer read public payment details';
  END IF;
  IF has_table_privilege('anon','public.payment_settings','UPDATE')
     OR has_table_privilege('anon','public.payment_settings','INSERT')
     OR has_table_privilege('anon','public.payment_settings','DELETE') THEN
    RAISE EXCEPTION 'FAIL: anon retains write privileges on payment_settings';
  END IF;
  IF NOT has_table_privilege('authenticated','public.payment_settings','SELECT')
     OR NOT has_table_privilege('authenticated','public.payment_settings','UPDATE') THEN
    RAISE EXCEPTION 'FAIL: authenticated role lacks intended table privileges';
  END IF;
  IF has_table_privilege('authenticated','public.payment_settings','INSERT')
     OR has_table_privilege('authenticated','public.payment_settings','DELETE') THEN
    RAISE EXCEPTION 'FAIL: unnecessary authenticated INSERT/DELETE privileges remain';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.payment_settings'::regclass
      AND polcmd = 'w'
      AND 0::oid = ANY(polroles)
  ) THEN
    RAISE EXCEPTION 'FAIL: PUBLIC-scoped UPDATE policy remains on payment_settings';
  END IF;

  SELECT * INTO v_policy FROM pg_policy
  WHERE polrelid = 'public.payment_settings'::regclass
    AND polname = 'payment_settings_admin_update'
    AND polcmd = 'w';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: admin-only payment-settings UPDATE policy missing';
  END IF;
  IF 0::oid = ANY(v_policy.polroles)
     OR array_length(v_policy.polroles,1) <> 1
     OR NOT v_auth_oid = ANY(v_policy.polroles) THEN
    RAISE EXCEPTION 'FAIL: payment-settings UPDATE policy is not restricted to authenticated';
  END IF;
  v_expr := coalesce(pg_get_expr(v_policy.polqual,v_policy.polrelid),'')
            || ' ' ||
            coalesce(pg_get_expr(v_policy.polwithcheck,v_policy.polrelid),'');
  IF v_expr NOT ILIKE '%nplus_is_admin%' THEN
    RAISE EXCEPTION 'FAIL: UPDATE policy does not check the current admin role';
  END IF;

  -- Anonymous table grants are unnecessary for these legacy tables.
  IF has_table_privilege('anon','public.manual_deposits','SELECT')
     OR has_table_privilege('anon','public.manual_deposits','INSERT')
     OR has_table_privilege('anon','public.user_bank_details','SELECT')
     OR has_table_privilege('anon','public.user_bank_details','INSERT')
     OR has_table_privilege('anon','public.withdraw_requests','SELECT')
     OR has_table_privilege('anon','public.withdraw_requests','INSERT') THEN
    RAISE EXCEPTION 'FAIL: one or more legacy table grants remain for anon';
  END IF;

  -- Upload policy must be authenticated-only and admin-scoped, never PUBLIC-scoped.
  SELECT * INTO v_policy FROM pg_policy
  WHERE polrelid = 'storage.objects'::regclass
    AND polname = 'payment_qr_admin_upload'
    AND polcmd = 'a';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: payment QR upload policy missing';
  END IF;
  IF 0::oid = ANY(v_policy.polroles)
     OR array_length(v_policy.polroles,1) <> 1
     OR NOT v_auth_oid = ANY(v_policy.polroles) THEN
    RAISE EXCEPTION 'FAIL: payment QR upload is not authenticated-only';
  END IF;
  v_expr := coalesce(pg_get_expr(v_policy.polwithcheck,v_policy.polrelid),'');
  IF v_expr NOT ILIKE '%payment_qr%'
     OR v_expr NOT ILIKE '%nplus_is_admin%' THEN
    RAISE EXCEPTION 'FAIL: payment QR upload policy lacks bucket/admin guard';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id='payment_qr'
      AND file_size_limit=5242880
      AND allowed_mime_types @> ARRAY['image/png','image/jpeg','image/webp']::text[]
      AND cardinality(allowed_mime_types)=3
  ) THEN
    RAISE EXCEPTION 'FAIL: payment_qr bucket size/MIME constraints are not set';
  END IF;

  -- WINGO overload cleanup must leave exactly the intended 5-arg function.
  IF to_regprocedure('public.nplus_admin_set_wingo_demo(integer,text,text,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: ambiguous 4-argument WINGO overload still exists';
  END IF;
  IF to_regprocedure('public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)') IS NULL THEN
    RAISE EXCEPTION 'FAIL: 5-argument WINGO function missing';
  END IF;
  IF has_function_privilege('anon',
       'public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: WINGO admin RPC EXECUTE grants are not expected';
  END IF;

  SELECT count(*) INTO v_count FROM public.game_settings
  WHERE upper(game_key) IN ('WINGO','K3','5D','TRX','MOTO','AVIATOR')
    AND enabled = false;
  IF v_count <> 6 THEN
    RAISE EXCEPTION 'FAIL: all six demo games must remain disabled; disabled count=%',v_count;
  END IF;

  RAISE NOTICE 'PASS: security follow-up catalog assertions';
END
$security_followup$;
