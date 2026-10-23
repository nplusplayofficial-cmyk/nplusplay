-- N+ PLAY production hotfix: prevent recursive profile RLS checks and private-profile disclosure.
-- Safe to re-run; changes policies only and does not update profile or wallet rows.
BEGIN;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
COMMIT;
