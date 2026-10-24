BEGIN;

-- These permissive policies make profile reads recurse through public.profiles.
-- The second policy also exposes all profile rows to authenticated users.
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;

-- Keep the existing authenticated-only policy which grants a user their own
-- profile and grants admins the directory view via SECURITY DEFINER nplus_is_admin().
-- No profile rows or wallet balances are modified.

COMMIT;