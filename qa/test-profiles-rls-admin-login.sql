\set ON_ERROR_STOP on
-- Disposable PostgreSQL regression for the Admin login profile-role query and profile privacy.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email text);
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $function$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $function$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  uid text NOT NULL UNIQUE,
  display_name text,
  email text,
  phone text,
  role text NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.nplus_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND lower(coalesce(role, '')) = 'admin'
  )
$function$;
REVOKE ALL ON FUNCTION public.nplus_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nplus_is_admin() TO authenticated;

INSERT INTO auth.users(id,email) VALUES
 ('a1111111-1111-4111-8111-111111111111','qa-admin-rls@example.invalid'),
 ('a2222222-2222-4222-8222-222222222222','qa-user-rls@example.invalid')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles(id,uid,display_name,email,phone,role) VALUES
 ('a1111111-1111-4111-8111-111111111111','QA-RLS-ADMIN','RLS QA Admin','qa-admin-rls@example.invalid','9090909001','admin'),
 ('a2222222-2222-4222-8222-222222222222','QA-RLS-USER','RLS QA User','qa-user-rls@example.invalid','9090909002','user')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.profiles TO anon, authenticated;
DO $drop_existing_profile_policies$
DECLARE v_policy record;
BEGIN
  FOR v_policy IN
    SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='profiles'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.profiles',v_policy.policyname);
  END LOOP;
END
$drop_existing_profile_policies$;

CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO public
  USING (EXISTS (SELECT 1 FROM public.profiles p2 WHERE p2.id=auth.uid() AND p2.role='admin'));
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles
  FOR SELECT TO public USING (true);
CREATE POLICY "profiles_owner_or_admin_read" ON public.profiles
  FOR SELECT TO authenticated
  USING ((id=(SELECT auth.uid())) OR (SELECT public.nplus_is_admin()));

\ir ../sql/NPLUS_PLAY_PROFILES_RLS_ADMIN_LOGIN_FIX_2026-10-23.sql

DO $policy_check$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles'
             AND policyname IN ('Admins can view all profiles','Public profiles are viewable by everyone')) THEN
    RAISE EXCEPTION 'Admin login RLS hotfix left a recursive/public profile SELECT policy.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles'
                 AND policyname='profiles_owner_or_admin_read') THEN
    RAISE EXCEPTION 'Owner/admin profile read policy was removed.';
  END IF;
END
$policy_check$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
DO $admin_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.profiles WHERE id='a2222222-2222-4222-8222-222222222222';
  IF v_count <> 1 THEN RAISE EXCEPTION 'Admin could not read the target user profile after RLS fix.'; END IF;
END
$admin_read$;
SELECT set_config('request.jwt.claim.sub','a2222222-2222-4222-8222-222222222222',true);
DO $user_read$
DECLARE v_own integer; v_other integer;
BEGIN
  SELECT count(*) INTO v_own FROM public.profiles WHERE id='a2222222-2222-4222-8222-222222222222';
  SELECT count(*) INTO v_other FROM public.profiles WHERE id='a1111111-1111-4111-8111-111111111111';
  IF v_own <> 1 OR v_other <> 0 THEN RAISE EXCEPTION 'Normal user profile visibility is not own-row-only.'; END IF;
END
$user_read$;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true);
DO $anon_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.profiles;
  IF v_count <> 0 THEN RAISE EXCEPTION 'Anonymous user can read profile rows.'; END IF;
END
$anon_read$;
ROLLBACK;
