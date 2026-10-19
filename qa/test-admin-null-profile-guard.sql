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

\ir ../sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql

INSERT INTO auth.users(id,email)
VALUES ('e1111111-1111-4111-8111-111111111111','orphan-profile-qa@example.invalid')
ON CONFLICT (id) DO NOTHING;
-- Deliberately do not insert a matching profiles row.
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
    IF v_message <> 'Admin access required.' OR v_state <> '42501' THEN
      RAISE EXCEPTION 'FAIL: % should fail closed; got % [%]', p_label, v_message, v_state;
    END IF;
  END;
END
$function$;

DO $tests$
DECLARE
  r record;
  v_count integer := 0;
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
    'select public.nplus_admin_set_wingo_demo(30, ''MANUAL'', ''RED'', 0, ''SMALL'')',
    'set WINGO demo result without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select * from public.nplus_admin_wingo_live_bets(''qa-orphan-profile'')',
    'read WINGO live bets without profiles row'
  );
  PERFORM pg_temp.expect_admin_denied(
    'select public.nplus_admin_wingo_round_summary(''qa-orphan-profile'')',
    'read WINGO round summary without profiles row'
  );

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
