-- POST-ROLLOUT ONLY. Do not run this while production main still calls this RPC.
-- Precondition: deploy the updated signup code that no longer calls
-- nplus_phone_is_registered(text), then verify duplicate-mobile signup against
-- a new isolated/test account. This removes the authenticated/anonymous phone
-- enumeration endpoint; it does not alter profiles or wallet balances.
--
-- This file is intentionally a separate manual release gate, not part of the
-- new game migrations. Review current production callers before applying.

begin;
revoke execute on function public.nplus_phone_is_registered(text) from public;
revoke execute on function public.nplus_phone_is_registered(text) from anon;
revoke execute on function public.nplus_phone_is_registered(text) from authenticated;
commit;

-- Read-only post-check:
-- select has_function_privilege('anon',
--   'public.nplus_phone_is_registered(text)', 'EXECUTE') as anon_execute,
--   has_function_privilege('authenticated',
--   'public.nplus_phone_is_registered(text)', 'EXECUTE') as authenticated_execute;
-- Expected after approved rollout: both false.
