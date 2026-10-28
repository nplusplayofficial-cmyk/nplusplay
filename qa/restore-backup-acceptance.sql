-- Read-only acceptance checks for a restored COPY of the 2026-10-15 backup.
-- Run ONLY against the newly created local database, never production.
-- Expected counts come from the previous restore-lab transcript.

DO $$
DECLARE
  v_profiles bigint;
  v_wallets bigint;
  v_ledger bigint;
  v_deposits bigint;
  v_games bigint;
  v_bad_ledger bigint;
  v_negative_wallets bigint;
  v_missing_history bigint;
  v_latest_mismatch bigint;
  v_rls_tables bigint;
  v_policies bigint;
  v_vault boolean;
BEGIN
  SELECT count(*) INTO v_profiles FROM public.profiles;
  SELECT count(*) INTO v_wallets FROM public.demo_wallets;
  SELECT count(*) INTO v_ledger FROM public.demo_wallet_transactions;
  SELECT count(*) INTO v_deposits FROM public.deposit_requests;
  SELECT count(*) INTO v_games FROM public.game_settings;

  IF v_profiles <> 5 OR v_wallets <> 5 OR v_ledger <> 140
     OR v_deposits <> 5 OR v_games <> 6 THEN
    RAISE EXCEPTION
      'Backup snapshot count mismatch: profiles %, wallets %, ledger %, deposits %, game_settings %; compare with recorded 2026-10-19 baseline before acceptance',
      v_profiles, v_wallets, v_ledger, v_deposits, v_games;
  END IF;

  SELECT count(*) INTO v_bad_ledger
  FROM public.demo_wallet_transactions
  WHERE balance_before + delta IS DISTINCT FROM balance_after;

  SELECT count(*) INTO v_negative_wallets
  FROM public.demo_wallets
  WHERE balance < 0;

  SELECT count(*) INTO v_missing_history
  FROM public.demo_wallets w
  WHERE NOT EXISTS (
    SELECT 1 FROM public.demo_wallet_transactions t
    WHERE t.user_id = w.user_id
  );

  SELECT count(*) INTO v_latest_mismatch
  FROM public.demo_wallets w
  LEFT JOIN LATERAL (
    SELECT t.balance_after
    FROM public.demo_wallet_transactions t
    WHERE t.user_id = w.user_id
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT 1
  ) latest ON TRUE
  WHERE latest.balance_after IS NULL
     OR w.balance IS DISTINCT FROM latest.balance_after;

  SELECT count(*) INTO v_rls_tables
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p')
    AND c.relrowsecurity;

  SELECT count(*) INTO v_policies
  FROM pg_policies
  WHERE schemaname = 'public';

  SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'supabase_vault'
  ) INTO v_vault;

  IF v_bad_ledger <> 0 OR v_negative_wallets <> 0
     OR v_missing_history <> 0 OR v_latest_mismatch <> 0 THEN
    RAISE EXCEPTION
      'Wallet integrity failure: arithmetic %, negative wallets %, missing histories %, wallet/latest-ledger mismatches %',
      v_bad_ledger, v_negative_wallets, v_missing_history, v_latest_mismatch;
  END IF;

  IF v_rls_tables <> 7 OR v_policies <> 13 OR NOT v_vault THEN
    RAISE EXCEPTION
      'Security-object baseline mismatch: RLS-enabled public tables %, public policies %, supabase_vault present %',
      v_rls_tables, v_policies, v_vault;
  END IF;

  RAISE NOTICE 'RESTORE ACCEPTANCE CHECKS PASSED: profiles %, wallets %, ledger %, deposits %, game_settings %, wallet arithmetic mismatches %, negative wallets %, wallets without history %, wallet/latest-ledger mismatches %, RLS tables %, policies %, Vault %',
    v_profiles, v_wallets, v_ledger, v_deposits, v_games,
    v_bad_ledger, v_negative_wallets, v_missing_history, v_latest_mismatch,
    v_rls_tables, v_policies, v_vault;
END
$$;

-- Report restored owner/ACL metadata and standard Supabase role presence.
-- No account details or table data are emitted.
SELECT
  'public_relations_with_explicit_acl' AS metric,
  count(*)::text AS value
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
  AND c.relacl IS NOT NULL
UNION ALL
SELECT
  'public_functions_with_explicit_acl',
  count(*)::text
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proacl IS NOT NULL
UNION ALL
SELECT
  'public_relation_owner_count',
  count(DISTINCT c.relowner)::text
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S');

SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname IN (
  'postgres', 'supabase_admin', 'anon', 'authenticated',
  'service_role', 'authenticator', 'supabase_auth_admin',
  'supabase_storage_admin', 'dashboard_user', 'pgbouncer'
)
ORDER BY rolname;
