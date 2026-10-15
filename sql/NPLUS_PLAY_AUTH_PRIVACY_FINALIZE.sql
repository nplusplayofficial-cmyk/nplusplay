-- Run ONLY after the auth branch that removes the public phone lookup has been merged/deployed
-- AND new sign-up has passed an end-to-end test.
-- The normalized-phone unique index is recorded in NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql
-- and has already been created in production.
-- Do not run this before frontend deployment: older main auth code still calls this RPC.

BEGIN;
REVOKE ALL ON FUNCTION public.nplus_phone_is_registered(text) FROM PUBLIC, anon, authenticated;
COMMIT;

-- Verify after deployment:
-- SELECT has_function_privilege('anon','public.nplus_phone_is_registered(text)','EXECUTE') AS anon_can_execute;
-- Expected: false.
