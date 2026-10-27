-- Candidate-only least-privilege hardening for legacy wallet/request tables.
-- Review against the canonical migration chain before deployment.
-- This file is not in supabase/migrations and has NOT been run on production.
-- It only revokes privileges from PUBLIC/anon; authenticated grants and RLS policies
-- are intentionally preserved so owner-scoped legacy access is not silently changed.
-- Read-only production catalog review (2026-10-27) found all three legacy tables
-- still grant direct privileges to anon despite RLS. `withdraw_requests` is included
-- because the current product uses `withdrawal_requests` via RPC, not the legacy table.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.manual_deposits
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON TABLE public.user_bank_details
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON TABLE public.withdraw_requests
  FROM PUBLIC, anon;

COMMIT;
