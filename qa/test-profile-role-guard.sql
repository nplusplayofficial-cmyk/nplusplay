\set ON_ERROR_STOP on

-- Disposable PostgreSQL regression for the live profile-role guard.
-- This duplicates the expected production trigger contract and never touches Supabase production.

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

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text
);

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $function$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text LANGUAGE sql STABLE
AS $function$
  SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')
$function$;

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

INSERT INTO auth.users(id,email)
VALUES
  ('c1111111-1111-4111-8111-111111111111','role-admin-qa@example.invalid'),
  ('c2222222-2222-4222-8222-222222222222','role-user-qa@example.invalid'),
  ('c3333333-3333-4333-8333-333333333333','role-other-qa@example.invalid')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,uid,display_name,email,phone,role)
VALUES
  ('c1111111-1111-4111-8111-111111111111','QA-ROLE-ADMIN','Role Guard Admin QA','role-admin-qa@example.invalid','9000000101','admin'),
  ('c2222222-2222-4222-8222-222222222222','QA-ROLE-USER','Role Guard User QA','role-user-qa@example.invalid','9000000102','user'),
  ('c3333333-3333-4333-8333-333333333333','QA-ROLE-OTHER','Role Guard Other QA','role-other-qa@example.invalid','9000000103','user')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nplus_guard_profile_role_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor_id uuid;
  v_actor_role text;
  v_jwt_role text;
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    v_actor_id := auth.uid();

    IF v_actor_id IS NULL THEN
      v_jwt_role := auth.role();
      IF v_jwt_role IN ('anon', 'authenticated') THEN
        RAISE EXCEPTION 'Only an administrator can change profile roles.'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      SELECT lower(coalesce(p.role, ''))
        INTO v_actor_role
        FROM public.profiles AS p
       WHERE p.id = v_actor_id;

      IF coalesce(v_actor_role, '') <> 'admin' THEN
        RAISE EXCEPTION 'Only an administrator can change profile roles.'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_guard_profile_role_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS nplus_guard_profile_role_update ON public.profiles;
CREATE TRIGGER nplus_guard_profile_role_update
BEFORE UPDATE OF role ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.nplus_guard_profile_role_update();

DO $tests$
DECLARE
  v_admin uuid := 'c1111111-1111-4111-8111-111111111111';
  v_user uuid := 'c2222222-2222-4222-8222-222222222222';
  v_other uuid := 'c3333333-3333-4333-8333-333333333333';
  v_error text;
  v_state text;
  v_role text;
BEGIN
  -- Authenticated user cannot promote themselves.
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  BEGIN
    UPDATE public.profiles SET role='admin' WHERE id=v_user;
    RAISE EXCEPTION 'QA_ASSERT: self-promotion unexpectedly allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
    IF v_error <> 'Only an administrator can change profile roles.' OR v_state <> '42501' THEN
      RAISE;
    END IF;
  END;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_user;
  IF v_role <> 'user' THEN RAISE EXCEPTION 'Self-promotion changed the saved role.'; END IF;

  -- A normal user cannot promote another account.
  BEGIN
    UPDATE public.profiles SET role='admin' WHERE id=v_other;
    RAISE EXCEPTION 'QA_ASSERT: cross-account promotion unexpectedly allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
    IF v_error <> 'Only an administrator can change profile roles.' OR v_state <> '42501' THEN
      RAISE;
    END IF;
  END;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_other;
  IF v_role <> 'user' THEN RAISE EXCEPTION 'Cross-account promotion changed the saved role.'; END IF;

  -- A request with no authenticated subject must not change a role either.
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    UPDATE public.profiles SET role='admin' WHERE id=v_other;
    RAISE EXCEPTION 'QA_ASSERT: subject-less authenticated request unexpectedly allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
    IF v_error <> 'Only an administrator can change profile roles.' OR v_state <> '42501' THEN
      RAISE;
    END IF;
  END;

  PERFORM set_config('request.jwt.claim.role','anon',true);
  BEGIN
    UPDATE public.profiles SET role='admin' WHERE id=v_other;
    RAISE EXCEPTION 'QA_ASSERT: anonymous role change unexpectedly allowed.';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
    IF v_error <> 'Only an administrator can change profile roles.' OR v_state <> '42501' THEN
      RAISE;
    END IF;
  END;

  -- Admin can make an intentional role change.
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  UPDATE public.profiles SET role='admin' WHERE id=v_other;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_other;
  IF v_role <> 'admin' THEN RAISE EXCEPTION 'Administrator role change was incorrectly blocked.'; END IF;

  IF has_function_privilege('anon','public.nplus_guard_profile_role_update()','EXECUTE')
     OR has_function_privilege('authenticated','public.nplus_guard_profile_role_update()','EXECUTE') THEN
    RAISE EXCEPTION 'Trigger function must not be directly exposed as an RPC.';
  END IF;

  RAISE NOTICE 'PASS: non-admin self-promotion rejected';
  RAISE NOTICE 'PASS: non-admin cross-account role change rejected';
  RAISE NOTICE 'PASS: anonymous and subject-less role changes rejected';
  RAISE NOTICE 'PASS: authenticated admin role changes remain possible';
  RAISE NOTICE 'PASS: trigger function is not executable by browser roles';
END
$tests$;

SELECT 'PASS: profile role escalation guard regression' AS result;
