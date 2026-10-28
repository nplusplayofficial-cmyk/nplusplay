-- QA-ONLY REQUEST-TABLE ACL PARITY OVERLAY.
-- NEVER RUN THIS FILE AGAINST PRODUCTION.
-- Read-only production catalog review on 2026-10-27 found both current request
-- tables owned by postgres with RLS enabled, anon with no privileges, and
-- authenticated SELECT only. Local replay baseline may have broader ACLs/owner.
-- This is not a captured migration and is not a clean 40-body replay.
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
DECLARE
  v_target text := current_database();
BEGIN
  IF v_target !~ '^nplus_migration_replay_[0-9]{8}$' THEN
    RAISE EXCEPTION 'QA request ACL overlay refused outside a date-suffixed local replay database.';
  END IF;
  IF current_setting('cron.database_name') <> v_target THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: cron.database_name mismatch.';
  END IF;
  IF to_regclass('nplus_replay_audit.wallet_ledger_acl_snapshot') IS NULL
     OR (SELECT count(*) FROM nplus_replay_audit.wallet_ledger_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: wallet/ledger ACL snapshot is missing.';
  END IF;
  IF to_regclass('nplus_replay_audit.request_table_acl_snapshot') IS NOT NULL THEN
    RAISE EXCEPTION 'QA request ACL overlay already applied; do not run twice.';
  END IF;
  IF to_regclass('public.deposit_requests') IS NULL
     OR to_regclass('public.withdrawal_requests') IS NULL THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: request relations are missing.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid IN (to_regclass('public.deposit_requests'), to_regclass('public.withdrawal_requests'))
      AND NOT relrowsecurity
  ) THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: RLS must be enabled on both tables.';
  END IF;
  IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid=to_regclass('public.deposit_requests')) <> 'postgres' THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: deposit_requests owner does not match the observed local baseline (postgres).';
  END IF;
  IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid=to_regclass('public.withdrawal_requests')) NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: withdrawal_requests owner is not one of the two explicitly reviewed baseline values.';
  END IF;
  IF NOT (
    has_table_privilege('anon','public.deposit_requests','INSERT')
    OR has_table_privilege('anon','public.deposit_requests','UPDATE')
    OR has_table_privilege('authenticated','public.deposit_requests','UPDATE')
    OR has_table_privilege('authenticated','public.deposit_requests','DELETE')
    OR has_table_privilege('anon','public.withdrawal_requests','INSERT')
    OR has_table_privilege('anon','public.withdrawal_requests','UPDATE')
    OR has_table_privilege('authenticated','public.withdrawal_requests','INSERT')
    OR has_table_privilege('authenticated','public.withdrawal_requests','UPDATE')
    OR has_table_privilege('authenticated','public.withdrawal_requests','DELETE')
  ) THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: reviewed broader local request-table grants not found; inspect instead of normalizing blindly.';
  END IF;
END
$guard$;

CREATE TABLE nplus_replay_audit.request_table_acl_snapshot (
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
ALTER TABLE nplus_replay_audit.request_table_acl_snapshot OWNER TO postgres;

INSERT INTO nplus_replay_audit.request_table_acl_snapshot (
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
  AND c.relname IN ('deposit_requests','withdrawal_requests')
ORDER BY c.relname;

DO $precheck$
BEGIN
  IF (SELECT count(*) FROM nplus_replay_audit.request_table_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA request ACL overlay refused: expected two original owner/ACL snapshots.';
  END IF;
END
$precheck$;

-- Normalize only the disposable clone's known owner drift; original owner is recorded.
ALTER TABLE public.withdrawal_requests OWNER TO postgres;
REVOKE ALL ON TABLE public.deposit_requests, public.withdrawal_requests
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.deposit_requests, public.withdrawal_requests
  TO authenticated;

DO $verify$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['deposit_requests','withdrawal_requests'] LOOP
    IF has_table_privilege('anon','public.'||v_table,'SELECT')
       OR has_table_privilege('anon','public.'||v_table,'INSERT')
       OR has_table_privilege('anon','public.'||v_table,'UPDATE')
       OR has_table_privilege('anon','public.'||v_table,'DELETE')
       OR has_table_privilege('anon','public.'||v_table,'TRUNCATE')
       OR has_table_privilege('anon','public.'||v_table,'REFERENCES')
       OR has_table_privilege('anon','public.'||v_table,'TRIGGER')
       OR NOT has_table_privilege('authenticated','public.'||v_table,'SELECT')
       OR has_table_privilege('authenticated','public.'||v_table,'INSERT')
       OR has_table_privilege('authenticated','public.'||v_table,'UPDATE')
       OR has_table_privilege('authenticated','public.'||v_table,'DELETE')
       OR has_table_privilege('authenticated','public.'||v_table,'TRUNCATE')
       OR has_table_privilege('authenticated','public.'||v_table,'REFERENCES')
       OR has_table_privilege('authenticated','public.'||v_table,'TRIGGER') THEN
      RAISE EXCEPTION 'QA request ACL overlay failed: direct browser-role ACL contract differs on public.%.', v_table;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM nplus_replay_audit.request_table_acl_snapshot) <> 2 THEN
    RAISE EXCEPTION 'QA request ACL overlay failed: original owner/ACL snapshot incomplete.';
  END IF;
END
$verify$;

COMMIT;

SELECT table_name, owner_before, relacl_before, anon_select_before, anon_insert_before,
       anon_update_before, anon_delete_before, authenticated_select_before,
       authenticated_insert_before, authenticated_update_before, authenticated_delete_before
FROM nplus_replay_audit.request_table_acl_snapshot
ORDER BY table_name;

SELECT 'QA-ONLY request-table ACL overlay verified; not a clean 40-body replay' AS result;
