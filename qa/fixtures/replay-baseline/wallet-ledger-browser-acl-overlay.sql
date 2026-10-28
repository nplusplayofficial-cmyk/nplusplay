-- QA-ONLY ACL PARITY OVERLAY.
-- NEVER RUN THIS FILE AGAINST PRODUCTION.
-- Current production catalog was inspected read-only on 2026-10-27:
-- anon/authenticated have no direct write grants on wallet/ledger; authenticated
-- retains SELECT only. The captured 40-row migration history does not create
-- this grant contract for the existing wallet/ledger tables.
-- This local-only ACL reconciliation is not a captured migration and is NOT a clean 40-body replay.
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
DECLARE
  v_target text := current_database();
BEGIN
  IF v_target !~ '^nplus_migration_replay_[0-9]{8}$' THEN
    RAISE EXCEPTION 'QA ACL overlay refused outside a date-suffixed local replay database.';
  END IF;
  IF current_setting('cron.database_name') <> v_target THEN
    RAISE EXCEPTION 'QA ACL overlay refused: cron.database_name does not match current database.';
  END IF;
  IF to_regclass('nplus_replay_audit.legacy_schema_bootstrap_marker') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM nplus_replay_audit.legacy_schema_bootstrap_marker
      WHERE marker='reconstructed_live_legacy_schema_2026_10_27'
    ) THEN
      RAISE EXCEPTION 'QA ACL overlay refused: reconstructed legacy-schema marker is invalid.';
    END IF;
  ELSIF to_regclass('nplus_replay_audit.manual_deposits_overlay_marker') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM nplus_replay_audit.manual_deposits_overlay_marker
      WHERE marker='manual_deposits_schema_overlay'
    ) THEN
      RAISE EXCEPTION 'QA ACL overlay refused: prior legacy-schema overlay marker is invalid.';
    END IF;
  ELSE
    RAISE EXCEPTION 'QA ACL overlay refused: neither approved local legacy-schema marker is present.';
  END IF;
  IF to_regclass('public.demo_wallets') IS NULL
     OR to_regclass('public.demo_wallet_transactions') IS NULL THEN
    RAISE EXCEPTION 'QA ACL overlay refused: wallet/ledger relations are missing.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid IN (to_regclass('public.demo_wallets'), to_regclass('public.demo_wallet_transactions'))
      AND (NOT relrowsecurity OR pg_get_userbyid(relowner) <> 'postgres')
  ) THEN
    RAISE EXCEPTION 'QA ACL overlay refused: wallet/ledger owner or RLS state is unexpected.';
  END IF;
  IF to_regclass('nplus_replay_audit.wallet_ledger_acl_snapshot') IS NOT NULL THEN
    RAISE EXCEPTION 'QA ACL overlay already applied; ACL snapshot exists. Do not run twice.';
  END IF;
  IF NOT (
    has_table_privilege('anon','public.demo_wallets','INSERT')
    OR has_table_privilege('anon','public.demo_wallets','UPDATE')
    OR has_table_privilege('authenticated','public.demo_wallets','INSERT')
    OR has_table_privilege('authenticated','public.demo_wallets','UPDATE')
    OR has_table_privilege('anon','public.demo_wallet_transactions','INSERT')
    OR has_table_privilege('anon','public.demo_wallet_transactions','UPDATE')
    OR has_table_privilege('authenticated','public.demo_wallet_transactions','INSERT')
    OR has_table_privilege('authenticated','public.demo_wallet_transactions','UPDATE')
  ) THEN
    RAISE EXCEPTION 'QA ACL overlay refused: expected broader local baseline grants were not found; inspect rather than normalizing blindly.';
  END IF;
END
$guard$;

CREATE TABLE nplus_replay_audit.wallet_ledger_acl_snapshot (
  table_name text PRIMARY KEY,
  owner_before text NOT NULL,
  relacl_before text,
  anon_select_before boolean NOT NULL,
  anon_insert_before boolean NOT NULL,
  anon_update_before boolean NOT NULL,
  anon_delete_before boolean NOT NULL,
  authenticated_select_before boolean NOT NULL,
  authenticated_insert_before boolean NOT NULL,
  authenticated_update_before boolean NOT NULL,
  authenticated_delete_before boolean NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE nplus_replay_audit.wallet_ledger_acl_snapshot OWNER TO postgres;

INSERT INTO nplus_replay_audit.wallet_ledger_acl_snapshot (
  table_name, owner_before, relacl_before,
  anon_select_before, anon_insert_before, anon_update_before, anon_delete_before,
  authenticated_select_before, authenticated_insert_before,
  authenticated_update_before, authenticated_delete_before
)
SELECT c.relname, pg_get_userbyid(c.relowner), c.relacl::text,
       has_table_privilege('anon', c.oid, 'SELECT'),
       has_table_privilege('anon', c.oid, 'INSERT'),
       has_table_privilege('anon', c.oid, 'UPDATE'),
       has_table_privilege('anon', c.oid, 'DELETE'),
       has_table_privilege('authenticated', c.oid, 'SELECT'),
       has_table_privilege('authenticated', c.oid, 'INSERT'),
       has_table_privilege('authenticated', c.oid, 'UPDATE'),
       has_table_privilege('authenticated', c.oid, 'DELETE')
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('demo_wallets','demo_wallet_transactions')
ORDER BY c.relname;

DO $precheck$
BEGIN
  IF (SELECT count(*) FROM nplus_replay_audit.wallet_ledger_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA ACL overlay refused: expected two original ACL snapshots.';
  END IF;
END
$precheck$;

REVOKE ALL ON TABLE public.demo_wallets, public.demo_wallet_transactions
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.demo_wallets, public.demo_wallet_transactions
  TO authenticated;

DO $verify$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['demo_wallets','demo_wallet_transactions'] LOOP
    IF has_table_privilege('anon','public.'||v_table,'SELECT')
       OR has_table_privilege('anon','public.'||v_table,'INSERT')
       OR has_table_privilege('anon','public.'||v_table,'UPDATE')
       OR has_table_privilege('anon','public.'||v_table,'DELETE')
       OR has_table_privilege('anon','public.'||v_table,'TRUNCATE')
       OR has_table_privilege('anon','public.'||v_table,'REFERENCES')
       OR has_table_privilege('anon','public.'||v_table,'TRIGGER')
       OR has_table_privilege('authenticated','public.'||v_table,'INSERT')
       OR has_table_privilege('authenticated','public.'||v_table,'UPDATE')
       OR has_table_privilege('authenticated','public.'||v_table,'DELETE')
       OR has_table_privilege('authenticated','public.'||v_table,'TRUNCATE')
       OR has_table_privilege('authenticated','public.'||v_table,'REFERENCES')
       OR has_table_privilege('authenticated','public.'||v_table,'TRIGGER')
       OR NOT has_table_privilege('authenticated','public.'||v_table,'SELECT') THEN
      RAISE EXCEPTION 'QA ACL overlay failed: direct browser-role wallet/ledger privileges violate the reviewed contract on public.%.', v_table;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM nplus_replay_audit.wallet_ledger_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA ACL overlay failed: original ACL snapshot is incomplete.';
  END IF;
END
$verify$;

COMMIT;

SELECT table_name, owner_before, relacl_before, anon_insert_before, anon_update_before,
       anon_delete_before, authenticated_select_before, authenticated_insert_before,
       authenticated_update_before, authenticated_delete_before
FROM nplus_replay_audit.wallet_ledger_acl_snapshot
ORDER BY table_name;

SELECT 'QA-ONLY wallet/ledger browser ACL overlay verified; not a clean 40-body replay' AS result;
