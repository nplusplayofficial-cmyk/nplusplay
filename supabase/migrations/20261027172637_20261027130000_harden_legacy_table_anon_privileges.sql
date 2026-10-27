-- N+ PLAY legacy table least-privilege follow-up.
-- Candidate migration only: do not deploy until canonical backup/replay and
-- final authenticated route review pass. This migration does not change rows.
-- Current UI evidence: only admin-deposits.html SELECTs manual_deposits for
-- read-only reconciliation. No browser route queries user_bank_details or
-- withdraw_requests, and no current public RPC body references these tables.
-- Keep authenticated SELECT on manual_deposits only; revoke direct browser-role
-- grants on the other two legacy tables. RLS and policy definitions stay intact.

BEGIN;

DO $preflight$
DECLARE
  v_table text;
  v_owner text;
  v_rls boolean;
  v_policy text;
  v_expected text[];
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
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.user_bank_details
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.withdraw_requests
  FROM PUBLIC, anon, authenticated;

-- Admin legacy screen is reconciliation-only and executes SELECT, never approve/credit.
GRANT SELECT ON TABLE public.manual_deposits TO authenticated;

DO $verify$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'manual_deposits',
    'user_bank_details',
    'withdraw_requests'
  ] LOOP
    IF has_table_privilege('anon', 'public.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'public.' || v_table, 'INSERT')
       OR has_table_privilege('anon', 'public.' || v_table, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || v_table, 'DELETE')
       OR has_table_privilege('anon', 'public.' || v_table, 'TRUNCATE')
       OR has_table_privilege('anon', 'public.' || v_table, 'REFERENCES')
       OR has_table_privilege('anon', 'public.' || v_table, 'TRIGGER')
       OR has_table_privilege('anon', 'public.' || v_table, 'MAINTAIN') THEN
      RAISE EXCEPTION 'Legacy privilege hardening failed: anon retains a direct privilege on public.%.', v_table;
    END IF;

    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.' || v_table)) THEN
      RAISE EXCEPTION 'Legacy privilege hardening failed: RLS changed on public.%.', v_table;
    END IF;
  END LOOP;

  IF NOT has_table_privilege('authenticated','public.manual_deposits','SELECT')
     OR has_table_privilege('authenticated','public.manual_deposits','INSERT')
     OR has_table_privilege('authenticated','public.manual_deposits','UPDATE')
     OR has_table_privilege('authenticated','public.manual_deposits','DELETE')
     OR has_table_privilege('authenticated','public.manual_deposits','TRUNCATE')
     OR has_table_privilege('authenticated','public.manual_deposits','REFERENCES')
     OR has_table_privilege('authenticated','public.manual_deposits','TRIGGER')
     OR has_table_privilege('authenticated','public.manual_deposits','MAINTAIN')
     OR has_table_privilege('authenticated','public.user_bank_details','SELECT')
     OR has_table_privilege('authenticated','public.user_bank_details','INSERT')
     OR has_table_privilege('authenticated','public.user_bank_details','UPDATE')
     OR has_table_privilege('authenticated','public.user_bank_details','DELETE')
     OR has_table_privilege('authenticated','public.user_bank_details','TRUNCATE')
     OR has_table_privilege('authenticated','public.user_bank_details','REFERENCES')
     OR has_table_privilege('authenticated','public.user_bank_details','TRIGGER')
     OR has_table_privilege('authenticated','public.user_bank_details','MAINTAIN')
     OR has_table_privilege('authenticated','public.withdraw_requests','SELECT')
     OR has_table_privilege('authenticated','public.withdraw_requests','INSERT')
     OR has_table_privilege('authenticated','public.withdraw_requests','UPDATE')
     OR has_table_privilege('authenticated','public.withdraw_requests','DELETE')
     OR has_table_privilege('authenticated','public.withdraw_requests','TRUNCATE')
     OR has_table_privilege('authenticated','public.withdraw_requests','REFERENCES')
     OR has_table_privilege('authenticated','public.withdraw_requests','TRIGGER')
     OR has_table_privilege('authenticated','public.withdraw_requests','MAINTAIN') THEN
    RAISE EXCEPTION 'Legacy privilege hardening failed: authenticated must have SELECT-only access to manual_deposits and no direct grants on the other legacy tables.';
  END IF;
END
$verify$;

COMMIT;
