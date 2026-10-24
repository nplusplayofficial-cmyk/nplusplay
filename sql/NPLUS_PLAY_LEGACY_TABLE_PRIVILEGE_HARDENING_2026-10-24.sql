-- Candidate-only least-privilege hardening for the legacy wallet tables.
-- Review against the canonical migration chain before deployment.
-- This file is not in supabase/migrations and has NOT been run on production.
-- It only revokes privileges from PUBLIC/anon; authenticated grants and RLS policies
-- are intentionally preserved so owner-scoped legacy access is not silently changed.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.manual_deposits
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON TABLE public.user_bank_details
  FROM PUBLIC, anon;

COMMIT;
