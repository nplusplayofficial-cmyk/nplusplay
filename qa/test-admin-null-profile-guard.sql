\set ON_ERROR_STOP on

-- Disposable PostgreSQL regression only. Apply candidate patch, then verify that
-- authenticated users without a profiles row cannot call Admin-only SECURITY DEFINER RPCs.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

-- Capture wallet invariants before applying a DDL-only authorization patch.
CREATE TEMP TABLE qa_null_guard_wallet_snapshot AS
SELECT user_id, balance FROM public.demo_wallets;
CREATE TEMP TABLE qa_null_guard_ledger_snapshot AS
SELECT user_id, count(*)::bigint AS row_count
FROM public.demo_wallet_transactions
GROUP BY user_id;

\ir ../sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql
\ir ../sql/NPLUS_PLAY_WINGO_OVERLOAD_DEFAULT_FIX_CANDIDATE_2026-10-24.sql

INSERT INTO auth.users(id,email)
VALUES
  ('e1111111-1111-4111-8111-111111111111','orphan-profile-qa@example.invalid'),
  ('e2222222-2222-4222-8222-222222222222','nonadmin-profile-qa@example.invalid')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles(id,uid,display_name,email,phone,role)
VALUES ('e2222222-2222-4222-8222-222222222222','QA-NULL-GUARD-USER','Null Guard QA User','nonadmin-profile-qa@example.invalid','9000000998','user')
ON CONFLICT (id) DO UPDATE SET role='user';
-- Deliberately do not insert a matching profiles row for e111...; it tests the missing-profile case.
SELECT set_config('request.jwt.claim.sub','e1111111-1111-4111-8111-111111111111',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);

CREATE TEMP TABLE qa_temp_schema_bootstrap (id integer);
DROP TABLE qa_temp_schema_bootstrap;
CREATE OR REPLACE FUNCTION pg_temp.expect_admin_denied(p_sql text, p_label text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_message text;
  v_state text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'QA_ASSERT: % unexpectedly succeeded', p_label;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
    IF v_message <> 'Admin access required.' THEN
      RAISE EXCEPTION 'FAIL: % should fail closed; got % [%]', p_label, v_message, v_state;
    END IF;
  END;
END
$function$;

DO $tests$
DECLARE
  r record;
  v_count integer := 0;
  v_admin_report jsonb;
BEGIN
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_set_game_status(''WINGO'', false)',
    'game status change without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_clear_wingo_manual(30, ''qa-orphan-profile'')',
    'clear WINGO manual result without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_commission_summary()',
    'commission report without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_deposit_summary()',
    'deposit report without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_save_wingo_manual(30, ''qa-orphan-profile'', ''RED'', 0, ''SMALL'')',
    'save WINGO manual result without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_set_wingo_demo(30::integer, ''MANUAL''::text, ''RED''::text, 0::integer)',
    'four-argument WINGO setter without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_set_wingo_demo(30::integer, ''MANUAL''::text, ''RED''::text, 0::integer, ''SMALL''::text)',
    'five-argument WINGO setter without profiles row'
  );

  -- Both WINGO overloads must also reject a normal authenticated profile.
  PERFORM set_config('request.jwt.claim.sub','e2222222-2222-4222-8222-222222222222',false);
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_set_wingo_demo(30::integer, ''MANUAL''::text, ''RED''::text, 0::integer)',
    'four-argument WINGO setter for normal non-admin profile'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_set_wingo_demo(30::integer, ''MANUAL''::text, ''RED''::text, 0::integer, ''SMALL''::text)',
    'five-argument WINGO setter for normal non-admin profile'
  );
  PERFORM set_config('request.jwt.claim.sub','e1111111-1111-4111-8111-111111111111',false);
  PERFORM pg_temp.expect_admin_denied(
    'select * from public.nplus_admin_wingo_live_bets(''qa-orphan-profile'')',
    'read WINGO live bets without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_wingo_round_summary(''qa-orphan-profile'')',
    'read WINGO round summary without profiles row'
  );

  -- A valid admin profile must still be allowed through the guarded report RPC.
  PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
  v_admin_report := public.nplus_admin_commission_summary();
  IF jsonb_typeof(v_admin_report) <> 'object' THEN
    RAISE EXCEPTION 'A valid admin was unexpectedly blocked from the commission report.';
  END IF;
  PERFORM set_config('request.jwt.claim.sub','e1111111-1111-4111-8111-111111111111',false);

  -- This patch is DDL/grants only: existing demo balances and ledger row counts must not change.
  IF EXISTS (
    SELECT 1
    FROM qa_null_guard_wallet_snapshot s
    FULL JOIN public.demo_wallets w USING (user_id)
    WHERE s.user_id IS NULL OR w.user_id IS NULL OR s.balance IS DISTINCT FROM w.balance
  ) THEN
    RAISE EXCEPTION 'Admin guard migration changed or removed an existing demo wallet balance.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM qa_null_guard_ledger_snapshot s
    FULL JOIN (
      SELECT user_id, count(*)::bigint AS row_count
      FROM public.demo_wallet_transactions
      GROUP BY user_id
    ) t USING (user_id)
    WHERE s.user_id IS NULL OR t.user_id IS NULL OR s.row_count IS DISTINCT FROM t.row_count
  ) THEN
    RAISE EXCEPTION 'Admin guard migration changed existing wallet ledger row counts.';
  END IF;

  -- Both overloaded WINGO demo setters and every targeted function must carry
  -- the explicit NULL-safe test, not merely rely on the runtime cases above.
  FOR r IN
    SELECT p.oid, p.oid::regprocedure::text AS signature,
           pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND p.proname = ANY(ARRAY[
        'nplus_admin_clear_wingo_manual',
        'nplus_admin_commission_summary',
        'nplus_admin_deposit_summary',
        'nplus_admin_save_wingo_manual',
        'nplus_admin_set_wingo_demo',
        'nplus_admin_wingo_live_bets',
        'nplus_admin_wingo_round_summary',
        'nplus_set_game_status'
      ])
  LOOP
    IF position('if coalesce(v_role, ' IN lower(r.definition)) = 0 THEN
      RAISE EXCEPTION 'Function % is missing a NULL-safe admin role guard.', r.signature;
    END IF;
    IF has_function_privilege('anon',r.oid,'EXECUTE')
       OR NOT has_function_privilege('authenticated',r.oid,'EXECUTE')
       OR NOT has_function_privilege('service_role',r.oid,'EXECUTE') THEN
      RAISE EXCEPTION 'Function % has unexpected browser/server EXECUTE grants.', r.signature;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  IF v_count <> 9 THEN
    RAISE EXCEPTION 'Expected 9 protected RPC signatures, checked %.', v_count;
  END IF;

  RAISE NOTICE 'PASS: an authenticated account without a profiles row is rejected by all tested Admin RPCs';
  RAISE NOTICE 'PASS: null-safe guard and least-privilege grants verified across 9 RPC signatures';
END
$tests$;

SELECT 'PASS: Admin null-profile bypass regression' AS result;
