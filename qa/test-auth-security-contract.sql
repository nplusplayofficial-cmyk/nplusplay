-- Read-only Auth contract checks for N+ PLAY.
-- Safe to execute in the Supabase SQL Editor: only catalog/aggregate reads and DO assertions.
-- No insert/update/delete/DDL is performed by this file.

DO $auth_contract$
DECLARE
  v_count bigint;
  v_missing_users_profiles bigint;
  v_missing_wallets bigint;
  v_def text;
  v_idx_unique boolean;
BEGIN
  -- Supabase Auth user creation must make a profile and starting demo wallet.
  SELECT count(*) INTO v_missing_users_profiles
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE p.id IS NULL;
  IF v_missing_users_profiles <> 0 THEN
    RAISE EXCEPTION 'FAIL: % Auth users have no public profile', v_missing_users_profiles;
  END IF;

  SELECT count(*) INTO v_missing_wallets
  FROM public.profiles p
  LEFT JOIN public.demo_wallets w ON w.user_id = p.id
  WHERE w.user_id IS NULL;
  IF v_missing_wallets <> 0 THEN
    RAISE EXCEPTION 'FAIL: % profiles have no demo wallet', v_missing_wallets;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'auth'
    AND c.relname = 'users'
    AND t.tgname = 'on_auth_user_created_nplus'
    AND NOT t.tgisinternal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected Auth-user profile/wallet trigger is missing or duplicated';
  END IF;

  SELECT pg_get_functiondef('public.create_nplus_profile()'::regprocedure)
  INTO v_def;
  IF v_def NOT ILIKE '%insert into public.profiles%'
     OR v_def NOT ILIKE '%insert into public.demo_wallets%'
     OR v_def NOT ILIKE '%new.id%'
     OR v_def NOT ILIKE '%new.raw_user_meta_data%' THEN
    RAISE EXCEPTION 'FAIL: create_nplus_profile no longer matches the expected Auth metadata/profile/wallet contract';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE p.oid = 'public.create_nplus_profile()'::regprocedure
    AND p.prosecdef
    AND EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg = 'search_path=public'
    );
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: create_nplus_profile SECURITY DEFINER/search_path guard is missing';
  END IF;

  -- Phone uniqueness must be enforced atomically even when the same number is
  -- formatted in different ways. This check validates catalog configuration only.
  SELECT i.indisunique INTO v_idx_unique
  FROM pg_index i
  JOIN pg_class idx ON idx.oid = i.indexrelid
  WHERE idx.relname = 'profiles_phone_digits_unique_idx'
    AND i.indrelid = 'public.profiles'::regclass;
  IF coalesce(v_idx_unique, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: normalized phone unique index is missing';
  END IF;

  -- The old phone-existence RPC may remain as an inert function, but API roles must
  -- not execute it. This preserves privacy and avoids user enumeration.
  IF to_regprocedure('public.nplus_phone_is_registered(text)') IS NULL THEN
    RAISE EXCEPTION 'FAIL: expected retired phone-lookup function was unexpectedly removed; review deployment assumptions';
  END IF;
  IF has_function_privilege('anon', 'public.nplus_phone_is_registered(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.nplus_phone_is_registered(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon/authenticated can still execute the phone-lookup RPC';
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'profiles'
    AND t.tgname = 'nplus_guard_profile_role_update'
    AND NOT t.tgisinternal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: profile role-change guard trigger is missing';
  END IF;

  RAISE NOTICE 'PASS: Auth profile/wallet trigger, phone uniqueness, and old RPC execution lock';
END
$auth_contract$;
