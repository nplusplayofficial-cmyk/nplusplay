-- N+ PLAY release preflight (READ-ONLY).
-- Run against an isolated Supabase staging database before production rollout.
-- This file intentionally contains SELECT statements only; it never changes data,
-- grants, schema, game settings or wallet balances.
WITH target_admin_functions AS (
  SELECT p.oid, p.oid::regprocedure::text AS signature,
         lower(pg_get_functiondef(p.oid)) AS definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND p.proname = ANY (ARRAY[
      'nplus_admin_clear_wingo_manual',
      'nplus_admin_commission_summary',
      'nplus_admin_deposit_summary',
      'nplus_admin_save_wingo_manual',
      'nplus_admin_set_wingo_demo',
      'nplus_admin_wingo_live_bets',
      'nplus_admin_wingo_round_summary',
      'nplus_set_game_status'
    ])
),
guard_pattern AS (
  SELECT
    'if coalesce(v_role, ' || quote_literal('') || ') <> ' ||
    quote_literal('admin') || ' then' AS text
),
checks AS (
  SELECT
    'Server-settlement tables'::text AS check_name,
    (to_regclass('public.nplus_wingo_demo_rounds') IS NOT NULL
     AND to_regclass('public.nplus_moto_demo_rounds') IS NOT NULL
     AND to_regclass('public.nplus_aviator_demo_rounds') IS NOT NULL) AS passed,
    'WINGO, MotoRace and Aviator settlement tables must all exist before matching frontends are enabled.'::text AS detail

  UNION ALL
  SELECT
    'Phone lookup RPC revoked',
    NOT coalesce(has_function_privilege('anon',
      to_regprocedure('public.nplus_phone_is_registered(text)'), 'EXECUTE'), false)
    AND NOT coalesce(has_function_privilege('authenticated',
      to_regprocedure('public.nplus_phone_is_registered(text)'), 'EXECUTE'), false),
    'PASS only after the deployed signup flow no longer calls the legacy phone-existence endpoint.'

  UNION ALL
  SELECT
    'Generic wallet credit guard active',
    coalesce(position(
      'positive virtual credits must be awarded by server-authoritative settlement or admin approval.'
      IN lower(pg_get_functiondef(to_regprocedure('public.nplus_wallet_change(numeric,text,text,text)')))
    ) > 0, false)
    AND coalesce(position(
      'game bets must use server-authoritative settlement rpcs.'
      IN lower(pg_get_functiondef(to_regprocedure('public.nplus_wallet_change(numeric,text,text,text)')))
    ) > 0, false)
    AND coalesce(has_function_privilege('authenticated',
      to_regprocedure('public.nplus_wallet_change(numeric,text,text,text)'), 'EXECUTE'), false),
    'PASS only when the guarded function rejects generic positive credits and GAME_BET debits; authenticated execution remains so documented negative non-game adjustments can continue.'

  UNION ALL
  SELECT
    'Admin NULL-safe role guard installed',
    (SELECT count(*) = 9
       FROM target_admin_functions f, guard_pattern g
      WHERE position(g.text IN f.definition) > 0),
    'Both WINGO setter overloads must be present, with nine targeted RPC signatures using explicit NULL-safe Admin checks.'

  UNION ALL
  SELECT
    'Profile-role trigger present',
    EXISTS (
      SELECT 1 FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'profiles'
        AND t.tgname = 'nplus_guard_profile_role_update'
        AND NOT t.tgisinternal
    ),
    'The trigger must block non-admin role changes on profiles.'

  UNION ALL
  SELECT
    'Wallet and ledger RLS enabled',
    (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.demo_wallets'))
    AND (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.demo_wallet_transactions')),
    'Both wallet and transaction tables must have row-level security enabled.'

  UNION ALL
  SELECT
    'Browser direct wallet writes revoked',
    NOT coalesce(has_table_privilege('anon', 'public.demo_wallets', 'INSERT,UPDATE,DELETE'), false)
    AND NOT coalesce(has_table_privilege('authenticated', 'public.demo_wallets', 'INSERT,UPDATE,DELETE'), false)
    AND NOT coalesce(has_table_privilege('anon', 'public.demo_wallet_transactions', 'INSERT,UPDATE,DELETE'), false)
    AND NOT coalesce(has_table_privilege('authenticated', 'public.demo_wallet_transactions', 'INSERT,UPDATE,DELETE'), false),
    'All wallet and ledger mutations must use authorized RPCs, not direct browser-role table writes.'

  UNION ALL
  SELECT
    'Public schema CREATE privilege restricted',
    NOT has_schema_privilege('anon', 'public', 'CREATE')
    AND NOT has_schema_privilege('authenticated', 'public', 'CREATE')
    AND NOT has_schema_privilege('public', 'public', 'CREATE'),
    'Prevents browser roles from creating objects in the exposed public schema.'

  UNION ALL
  SELECT
    'Unsupported game keys paused',
    (SELECT count(*) = 3
       FROM public.game_settings
      WHERE upper(game_key) IN ('K3','5D','TRX')
        AND enabled = false),
    'K3, 5D and TRX must stay disabled until payout rules and server settlement are reviewed.'
)
SELECT
  check_name,
  CASE WHEN passed THEN 'PASS' ELSE 'BLOCK' END AS status,
  detail
FROM checks
ORDER BY CASE WHEN passed THEN 1 ELSE 0 END, check_name;

-- Separate Auth dashboard checks (cannot be reliably verified by this SQL):
-- 1. Confirm email ON only after matching OTP signup frontend is deployed.
-- 2. Leaked-password protection is enabled, or its limitation is explicitly accepted.
-- 3. Signup OTP delivery and password recovery have been tested in a staging browser.
-- 4. Existing backup has been restored successfully into an isolated database.
