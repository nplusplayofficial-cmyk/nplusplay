-- QA-ONLY REQUEST-TABLE ACL PARITY OVERLAY.
-- NEVER RUN THIS FILE AGAINST PRODUCTION.
-- Read-only production catalog review on 2026-10-27 showed authenticated
-- SELECT only and no anon privileges on deposit_requests/withdrawal_requests.
-- The captured history did not explicitly reconcile baseline table ACLs.
-- This overlay adjusts only the isolated local replay DB after snapshotting the
-- current request-table ACLs. It is not a captured migration and is not a clean
-- 40-body replay.
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
DECLARE
  v_target text := current_database();
BEGIN
  IF v_target <> 'nplus_migration_replay_20261026' THEN
    RAISE EXCEPTION 'QA request ACL overlay refused outside nplus_migration_replay_20261026.';
  END IF;
  IF current_setting('cron.database_name') <> v_target THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: cron.database_name mismatch.';
  END IF;
  IF to_regclass('nplus_replay_audit.wallet_ledger_acl_snapshot') IS NULL
     OR (SELECT count(*) FROM nplus_replay_audit.wallet_ledger_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: wallet/ledger ACL overlay snapshot is missing.';
  END IF;
  IF to_regclass('public.deposit_requests') IS NULL
     OR to_regclass('public.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: request relations missing.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid IN (
      to_regclass('public.deposit_requests'),
      to_regclass('public.withdrawal_requests')
    )
      AND (NOT relrowsecurity OR pg_get_userbyid(relowner) <> 'postgres')
  ) THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: owner/RLS precondition differs.';
  END IF;
  IF to_regclass('nplus_replay_audit.request_table_acl_snapshot') IS NOT NULL THEN
    RAISE EXCEPTION 'QA request ACL overlay already applied; do not run twice.';
  END IF;
  IF NOT (
    has_table_privilege('anon','public.deposit_requests','INSERT')
    OR has_table_privilege('anon','public.deposit_requests','UPDATE')
    OR has_table_privilege('anon','public.deposit_requests','DELETE')
    OR has_table_privilege('authenticated','public.deposit_requests','UPDATE')
    OR has_table_privilege('authenticated','public.deposit_requests','DELETE')
    OR has_table_privilege('anon','public.withdrawal_requests','INSERT')
    OR has_table_privilege('anon','public.withdrawal_requests','UPDATE')
    OR has_table_privilege('anon','public.withdrawal_requests','DELETE')
    OR has_table_privilege('authenticated','public.withdrawal_requests','INSERT')
    OR has_table_privilege('authenticated','public.withdrawal_requests','UPDATE')
    OR has_table_privilege('authenticated','public.withdrawal_requests','DELETE')
  ) THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: disallowed direct request-table write grants not found; inspect the invariant instead.';
  END IF;
END
$guard$;

CREATE TABLE nplus_replay_audit.request_table_acl_snapshot (
  table_name text PRIMARY KEY,
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

INSERT INTO nplus_replay_audit.request_table_acl_snapshot (
  table_name, relacl_before,
  anon_select_before, anon_insert_before, anon_update_before, anon_delete_before,
  authenticated_select_before, authenticated_insert_before,
  authenticated_update_before, authenticated_delete_before
)
SELECT c.relname, c.relacl::text,
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
  AND c.relname IN ('deposit_requests','withdrawal_requests')
ORDER BY c.relname;

REVOKE ALL ON TABLE public.deposit_requests, public.withdrawal_requests
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.deposit_requests, public.withdrawal_requests
  TO authenticated;

DO $verify$
BEGIN
  IF has_table_privilege('anon','public.deposit_requests','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon','public.withdrawal_requests','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'QA request ACL overlay failed: anon has table privileges on request tables.';
  END IF;
  IF NOT has_table_privilege('authenticated','public.deposit_requests','SELECT')
     OR NOT has_table_privilege('authenticated','public.withdrawal_requests','SELECT')
     OR has_table_privilege('authenticated','public.deposit_requests','INSERT')
     OR has_table_privilege('authenticated','public.deposit_requests','UPDATE')
     OR has_table_privilege('authenticated','public.deposit_requests','DELETE')
     OR has_table_privilege('authenticated','public.withdrawal_requests','INSERT')
     OR has_table_privilege('authenticated','public.withdrawal_requests','UPDATE')
     OR has_table_privilege('authenticated','public.withdrawal_requests','DELETE') THEN
    RAISE EXCEPTION 'QA request ACL overlay failed: request-table ACLs differ from the reviewed read-only contract.';
  END IF;
  IF (SELECT count(*) FROM nplus_replay_audit.request_table_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA request ACL overlay failed: request ACL snapshot incomplete.';
  END IF;
END
$verify$;

COMMIT;

SELECT table_name, relacl_before, anon_select_before, anon_insert_before,
       anon_update_before, anon_delete_before, authenticated_select_before,
       authenticated_insert_before, authenticated_update_before, authenticated_delete_before
FROM nplus_replay_audit.request_table_acl_snapshot
ORDER BY table_name;

SELECT 'QA-ONLY request-table ACL overlay verified; not a clean 40-body replay' AS result;
