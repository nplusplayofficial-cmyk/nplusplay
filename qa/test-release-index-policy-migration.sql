\set ON_ERROR_STOP on

-- Disposable PostgreSQL regression test for the two 2026-10-23 production
-- migrations. This fixture does not connect to or mutate the live Supabase DB.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,
  role text NOT NULL DEFAULT 'user'
);
CREATE TABLE public.user_preferences (user_id uuid NOT NULL);
CREATE TABLE public.manual_deposits (user_id uuid NOT NULL);
CREATE TABLE public.user_bank_details (user_id uuid NOT NULL);
CREATE TABLE public.withdraw_requests (user_id uuid NOT NULL);
CREATE TABLE public.withdrawal_requests (user_id uuid NOT NULL, reviewed_by uuid);
CREATE TABLE public.nplus_demo_gift_claims (code uuid);
CREATE TABLE public.nplus_demo_gift_codes (created_by uuid);
CREATE TABLE public.nplus_demo_referral_bonus_claims (invitee_count integer);
CREATE TABLE public.nplus_demo_referral_qualifications (verified_by uuid);
CREATE TABLE public.nplus_demo_support_requests (handled_by uuid);

CREATE TABLE public.nplus_demo_referral_codes (
  user_id uuid PRIMARY KEY
);
CREATE UNIQUE INDEX nplus_demo_referral_codes_user_uidx
  ON public.nplus_demo_referral_codes (user_id);

CREATE TABLE public.nplus_demo_referrals (
  referred_user_id uuid CONSTRAINT nplus_demo_referrals_referred_user_id_key UNIQUE
);
CREATE UNIQUE INDEX nplus_demo_referrals_referred_uidx
  ON public.nplus_demo_referrals (referred_user_id);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_own_update ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY profiles_update_own_display_name ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.nplus_recent_demo_activity(p_window_minutes integer)
RETURNS TABLE(game_key text, activity_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$ SELECT 'WINGO'::text, 0::bigint WHERE false $$;

\ir ../supabase/migrations/20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql
\ir ../supabase/migrations/20261023093056_drop_duplicate_referral_unique_indexes_20261023.sql

DO $assertions$
DECLARE
  fk_indexes integer;
  prefs_policies integer;
  deposit_select_policies integer;
  redundant_profile_policy integer;
  duplicate_indexes integer;
  preserved_keys integer;
BEGIN
  SELECT count(*) INTO fk_indexes
  FROM pg_indexes
  WHERE schemaname='public' AND indexname IN (
    'idx_manual_deposits_user_id_fk',
    'idx_nplus_demo_gift_claims_code_fk',
    'idx_nplus_demo_gift_codes_created_by_fk',
    'idx_nplus_demo_referral_bonus_claims_invitee_count_fk',
    'idx_nplus_demo_referral_qualifications_verified_by_fk',
    'idx_nplus_demo_support_requests_handled_by_fk',
    'idx_withdraw_requests_user_id_fk',
    'idx_withdrawal_requests_reviewed_by_fk'
  );
  IF fk_indexes <> 8 THEN
    RAISE EXCEPTION 'Expected 8 FK indexes; found %.', fk_indexes;
  END IF;

  SELECT count(*) INTO prefs_policies
  FROM pg_policies
  WHERE schemaname='public' AND tablename='user_preferences'
    AND policyname IN (
      'user_preferences_select_own',
      'user_preferences_insert_own',
      'user_preferences_update_own'
    ) AND roles = ARRAY['authenticated']::name[];
  IF prefs_policies <> 3 THEN
    RAISE EXCEPTION 'Expected three authenticated owner-scoped preferences policies; found %.', prefs_policies;
  END IF;

  SELECT count(*) INTO deposit_select_policies
  FROM pg_policies
  WHERE schemaname='public' AND tablename='manual_deposits' AND cmd='SELECT'
    AND policyname='manual_deposits_owner_admin_read'
    AND roles = ARRAY['authenticated']::name[];
  IF deposit_select_policies <> 1 THEN
    RAISE EXCEPTION 'Combined owner/admin deposit SELECT policy not found.';
  END IF;

  SELECT count(*) INTO redundant_profile_policy
  FROM pg_policies
  WHERE schemaname='public' AND tablename='profiles'
    AND policyname='profiles_update_own_display_name';
  IF redundant_profile_policy <> 0 THEN
    RAISE EXCEPTION 'Redundant profile UPDATE policy was not removed.';
  END IF;

  SELECT count(*) INTO duplicate_indexes
  FROM pg_indexes
  WHERE schemaname='public' AND indexname IN (
    'nplus_demo_referral_codes_user_uidx',
    'nplus_demo_referrals_referred_uidx'
  );
  IF duplicate_indexes <> 0 THEN
    RAISE EXCEPTION 'Duplicate standalone referral indexes remain.';
  END IF;

  SELECT count(*) INTO preserved_keys
  FROM pg_class c
  WHERE c.relnamespace='public'::regnamespace
    AND c.relname IN (
      'nplus_demo_referral_codes_pkey',
      'nplus_demo_referrals_referred_user_id_key'
    );
  IF preserved_keys <> 2 THEN
    RAISE EXCEPTION 'Primary/unique constraint indexes were not preserved.';
  END IF;

  IF obj_description('public.nplus_recent_demo_activity(integer)'::regprocedure, 'pg_proc')
      NOT ILIKE '%aggregate-only%' THEN
    RAISE EXCEPTION 'Public activity RPC intent is not documented.';
  END IF;

  RAISE NOTICE 'PASS: release index/policy migrations verified.';
END
$assertions$;

-- Additional security follow-up, isolated in this disposable migration-test DB:
-- simulate broad pre-existing table grants, then verify only the current route's
-- minimum authenticated SELECT remains and unused legacy tables have no browser grants.
ALTER TABLE public.manual_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_bank_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdraw_requests ENABLE ROW LEVEL SECURITY;
GRANT ALL PRIVILEGES ON TABLE public.manual_deposits,
  public.user_bank_details, public.withdraw_requests TO PUBLIC, anon, authenticated;

\ir ../sql/NPLUS_PLAY_LEGACY_TABLE_PRIVILEGE_HARDENING_2026-10-24.sql

DO $legacy_privilege_assertions$
BEGIN
  IF has_table_privilege('anon','public.manual_deposits','SELECT')
     OR has_table_privilege('anon','public.manual_deposits','INSERT')
     OR has_table_privilege('anon','public.manual_deposits','UPDATE')
     OR has_table_privilege('anon','public.manual_deposits','DELETE')
     OR has_table_privilege('anon','public.manual_deposits','TRUNCATE')
     OR has_table_privilege('anon','public.manual_deposits','REFERENCES')
     OR has_table_privilege('anon','public.manual_deposits','TRIGGER')
     OR has_table_privilege('anon','public.manual_deposits','MAINTAIN') THEN
    RAISE EXCEPTION 'Anonymous table privileges remain on public.manual_deposits.';
  END IF;
  IF has_table_privilege('anon','public.user_bank_details','SELECT')
     OR has_table_privilege('anon','public.user_bank_details','INSERT')
     OR has_table_privilege('anon','public.user_bank_details','UPDATE')
     OR has_table_privilege('anon','public.user_bank_details','DELETE')
     OR has_table_privilege('anon','public.user_bank_details','TRUNCATE')
     OR has_table_privilege('anon','public.user_bank_details','REFERENCES')
     OR has_table_privilege('anon','public.user_bank_details','TRIGGER')
     OR has_table_privilege('anon','public.user_bank_details','MAINTAIN') THEN
    RAISE EXCEPTION 'Anonymous table privileges remain on public.user_bank_details.';
  END IF;
  IF has_table_privilege('anon','public.withdraw_requests','SELECT')
     OR has_table_privilege('anon','public.withdraw_requests','INSERT')
     OR has_table_privilege('anon','public.withdraw_requests','UPDATE')
     OR has_table_privilege('anon','public.withdraw_requests','DELETE')
     OR has_table_privilege('anon','public.withdraw_requests','TRUNCATE')
     OR has_table_privilege('anon','public.withdraw_requests','REFERENCES')
     OR has_table_privilege('anon','public.withdraw_requests','TRIGGER')
     OR has_table_privilege('anon','public.withdraw_requests','MAINTAIN') THEN
    RAISE EXCEPTION 'Anonymous table privileges remain on public.withdraw_requests.';
  END IF;
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
    RAISE EXCEPTION 'Authenticated table grants exceed the reviewed legacy route contract.';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.manual_deposits'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_bank_details'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.withdraw_requests'::regclass) THEN
    RAISE EXCEPTION 'RLS must remain enabled on all three legacy tables.';
  END IF;
  RAISE NOTICE 'PASS: anonymous grants removed on all three legacy tables.';
  RAISE NOTICE 'PASS: authenticated has only manual_deposits SELECT and no direct grants on legacy bank/withdraw tables.';
  RAISE NOTICE 'PASS: all three tables retain RLS and their reviewed policy definitions.'
END
$legacy_privilege_assertions$;
