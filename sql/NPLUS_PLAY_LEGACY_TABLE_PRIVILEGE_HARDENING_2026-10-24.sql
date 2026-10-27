-- Candidate-only least-privilege hardening for legacy wallet/request tables.
-- Review against the canonical migration chain before deployment.
-- This file is not in supabase/migrations and has NOT been run on production.
-- It revokes privileges from PUBLIC/anon only; authenticated grants and RLS policies
-- are preserved so owner-scoped legacy access is not silently changed.
-- Read-only production review (2026-10-27) found these three relations owned by
-- postgres with RLS enabled and explicit anon grants. The preflight below refuses
-- a mismatched owner, missing table, disabled RLS, or missing expected policies.

\set ON_ERROR_STOP on
BEGIN;

DO $preflight$
DECLARE
  v_table text;
  v_owner text;
  v_rls boolean;
  v_expected text[];
  v_policy text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'manual_deposits',
    'user_bank_details',
    'withdraw_requests'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION 'Legacy privilege hardening refused: public.% does not exist.', v_table;
    END IF;

    SELECT pg_get_userbyid(c.relowner), c.relrowsecurity
      INTO v_owner, v_rls
    FROM pg_class c
    WHERE c.oid = to_regclass('public.' || v_table);

    IF v_owner IS DISTINCT FROM 'postgres' THEN
      RAISE EXCEPTION 'Legacy privilege hardening refused: public.% owner is %, expected postgres.',
        v_table, coalesce(v_owner, '<null>');
    END IF;
    IF v_rls IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Legacy privilege hardening refused: RLS is not enabled on public.%.', v_table;
    END IF;
  END LOOP;

  v_expected := ARRAY[
    'manual_deposits_owner_admin_read',
    'Users can insert own deposit',
    'Users can view own bank',
    'Users can insert own bank',
    'Users can update own bank',
    'Users can view own withdraw',
    'Users can insert own withdraw'
  ];

  FOREACH v_policy IN ARRAY v_expected LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public'
        AND policyname=v_policy
        AND tablename = CASE
          WHEN v_policy IN ('manual_deposits_owner_admin_read','Users can insert own deposit') THEN 'manual_deposits'
          WHEN v_policy IN ('Users can view own bank','Users can insert own bank','Users can update own bank') THEN 'user_bank_details'
          ELSE 'withdraw_requests'
        END
        AND 'authenticated' = ANY(roles)
    ) THEN
      RAISE EXCEPTION 'Legacy privilege hardening refused: expected authenticated owner policy "%" is missing.', v_policy;
    END IF;
  END LOOP;
END
$preflight$;

REVOKE ALL PRIVILEGES ON TABLE public.manual_deposits
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON TABLE public.user_bank_details
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON TABLE public.withdraw_requests
  FROM PUBLIC, anon;

DO $verify$
DECLARE
  v_table text;
  v_required text[];
  v_priv text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'manual_deposits',
    'user_bank_details',
    'withdraw_requests'
  ] LOOP
    IF has_table_privilege('anon', 'public.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'public.' || v_table, 'INSERT')
       OR has_table_privilege('anon', 'public.' || v_table, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || v_table, 'DELETE') THEN
      RAISE EXCEPTION 'Legacy privilege hardening failed: anon retains a direct privilege on public.%.', v_table;
    END IF;

    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.' || v_table)) THEN
      RAISE EXCEPTION 'Legacy privilege hardening failed: RLS changed on public.%.', v_table;
    END IF;
  END LOOP;

  -- Preserve existing authenticated app contracts. The table grants stay broad
  -- for compatibility, while owner-scoped RLS policies remain the row boundary.
  IF NOT has_table_privilege('authenticated','public.manual_deposits','SELECT')
     OR NOT has_table_privilege('authenticated','public.manual_deposits','INSERT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','SELECT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','INSERT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','UPDATE')
     OR NOT has_table_privilege('authenticated','public.withdraw_requests','SELECT')
     OR NOT has_table_privilege('authenticated','public.withdraw_requests','INSERT') THEN
    RAISE EXCEPTION 'Legacy privilege hardening failed: authenticated grants differ from reviewed contract.';
  END IF;
END
$verify$;

COMMIT;
