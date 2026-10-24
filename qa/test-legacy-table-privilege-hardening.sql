\set ON_ERROR_STOP on
-- Isolated PostgreSQL-only contract test for legacy table grants.
-- Runs against a fresh disposable database; never against Supabase production.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$roles$;

CREATE TABLE public.manual_deposits (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  amount numeric NOT NULL,
  status text NOT NULL DEFAULT 'pending'
);
CREATE TABLE public.user_bank_details (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  account_number text
);

ALTER TABLE public.manual_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_bank_details ENABLE ROW LEVEL SECURITY;

GRANT ALL PRIVILEGES ON TABLE public.manual_deposits,
  public.user_bank_details TO PUBLIC, anon, authenticated;

CREATE POLICY manual_deposits_owner_read ON public.manual_deposits
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY manual_deposits_owner_insert ON public.manual_deposits
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY user_bank_details_owner_read ON public.user_bank_details
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY user_bank_details_owner_insert ON public.user_bank_details
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY user_bank_details_owner_update ON public.user_bank_details
  FOR UPDATE TO authenticated USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- In a fresh test database only: auth.uid() stub so owner policies parse/validate.
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

\ir ../sql/NPLUS_PLAY_LEGACY_TABLE_PRIVILEGE_HARDENING_2026-10-24.sql

DO $tests$
BEGIN
  IF has_table_privilege('anon','public.manual_deposits','SELECT')
     OR has_table_privilege('anon','public.manual_deposits','INSERT')
     OR has_table_privilege('anon','public.manual_deposits','UPDATE')
     OR has_table_privilege('anon','public.manual_deposits','DELETE') THEN
    RAISE EXCEPTION 'FAIL: anon retains a privilege on manual_deposits';
  END IF;
  IF has_table_privilege('anon','public.user_bank_details','SELECT')
     OR has_table_privilege('anon','public.user_bank_details','INSERT')
     OR has_table_privilege('anon','public.user_bank_details','UPDATE')
     OR has_table_privilege('anon','public.user_bank_details','DELETE') THEN
    RAISE EXCEPTION 'FAIL: anon retains a privilege on user_bank_details';
  END IF;

  IF NOT has_table_privilege('authenticated','public.manual_deposits','INSERT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','SELECT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','INSERT')
     OR NOT has_table_privilege('authenticated','public.user_bank_details','UPDATE') THEN
    RAISE EXCEPTION 'FAIL: authenticated legacy privileges changed unexpectedly';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.manual_deposits'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_bank_details'::regclass) THEN
    RAISE EXCEPTION 'FAIL: RLS must remain enabled on both legacy tables';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='manual_deposits' AND policyname='manual_deposits_owner_read')
     OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                    AND tablename='user_bank_details' AND policyname='user_bank_details_owner_update') THEN
    RAISE EXCEPTION 'FAIL: expected authenticated owner policies were not preserved';
  END IF;

  RAISE NOTICE 'PASS: PUBLIC/anon privileges removed from manual_deposits and user_bank_details';
  RAISE NOTICE 'PASS: authenticated owner-scoped privileges/policies and RLS preserved';
END
$tests$;
