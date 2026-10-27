# Supabase Security Advisor triage — 2026-10-24

## Scope and safety

Read-only snapshot of Supabase Security and Performance Advisor output on 2026-10-24 for project `pcrxlqduygvzchzxsmdv`. No production grants, RLS policies, functions, auth settings, wallets, users, or game settings were changed.

This document triages findings; it does not claim that every warning is exploitable or that a warning has been remediated.

## Security findings observed

- **RLS enabled with no policies: 20 tables (INFO).** The finding list includes server-side bet/round/worker-health tables and demo gift/referral/support tables. RLS with no policies is default-deny for normal table access, but the design must still be checked against intended RPC access and grants. Do not add broad policies merely to silence the Advisor.
- **Anonymous SECURITY DEFINER function: 1 warning.** `public.nplus_recent_demo_activity(integer)` is executable by `anon` and `authenticated`. Read-only inspection confirms it returns only `game_key` and `activity_count`, caps the time window between 5 and 1440 minutes, uses a fixed `search_path`, and does not return user IDs, bet rows, or timestamps. This appears consistent with the public aggregate homepage use case. Keep public execute only if that public feed is intentional; otherwise revoke anonymous execute and update the UI in the same reviewed rollout.
- **Authenticated SECURITY DEFINER functions: 53 warnings.** This is a broad linter category, not proof that every function is vulnerable. Each callable function must be reviewed for `auth.uid()`, role checks where required, input bounds, fixed `search_path`, and whether it returns private data. Do not blanket-revoke authenticated EXECUTE: legitimate signed-in features would break. The inspected functions `nplus_admin_adjust_demo_wallet` and `nplus_set_game_status` require a signed-in admin inside the function and deny anonymous execution; `nplus_wallet_change` requires authentication and blocks positive credits and generic game win/bet types.
- **Leaked-password protection disabled (WARN).** This is an Auth project setting and cannot be safely changed by a SQL migration. Enable it through Supabase Auth settings after checking the supported plan/configuration and then test signup/password reset.

## Release actions

1. Keep the candidate least-privilege fix for `manual_deposits` and `user_bank_details` in draft until the legacy route inventory and RLS/authenticated access tests pass.
2. Review all 53 authenticated SECURITY DEFINER functions by category (admin, user-owned data, public aggregate, internal worker); document authorization tests before changing privileges.
3. Decide explicitly whether the homepage aggregate activity RPC is public. If yes, retain only its minimal aggregate output and test it anonymously; if no, revoke anon EXECUTE and remove anonymous UI calls together.
4. Organization/project plan is Free. [Supabase documentation](https://supabase.com/docs/guides/auth/password-security) says leaked-password protection is Pro+; do not upgrade or incur costs without approval. Record this as a known Free-plan limitation and verify supported password length/complexity and rate-limit settings, then test signup, OTP, login, and reset flows.
5. Re-run Advisor after the approved changes and compare finding counts. Avoid dropping indexes based only on an unused-index warning; low traffic and recent creation can make indexes appear unused.

## Not done

- No production mutation.
- No blanket function privilege changes.
- No blanket RLS policy creation.
- No Auth setting changes.
- No assertion that the hosted login/browser journey has passed.

## Refreshed current snapshot — 2026-10-27 09:02 UTC

The latest Advisor read confirms the same categories are still present; this is an updated observation, not a claim that the warnings were remediated:

- **20 RLS-enabled/no-policy tables (INFO).** A read-only table-privilege review found no direct browser-role table privileges for `anon` or `authenticated` on the tables in this Advisor set. Maintain default-deny and avoid adding blanket policies.
- **1 anonymous SECURITY DEFINER function (WARN).** `public.nplus_recent_demo_activity(integer)` remains intentionally public for the aggregate-only homepage feed. Retain this public exception only with its narrow result contract and regression tests.
- **53 authenticated SECURITY DEFINER functions (WARN).** Review authorization one function/category at a time. The linter warning alone does not mean an exploit exists; however, generic role grants cannot substitute for in-function Admin, user-ownership and input-bound checks. Current release candidate CI and local E2E cover important paths but do not prove every callable function.
- **Leaked-password protection disabled (WARN).** Confirmed Free-tier limitation: current Supabase docs say this feature is available on Pro and above. No plan upgrade or Auth-setting change was made. Keep it documented unless the owner explicitly approves a paid upgrade; check supported password length/complexity and rate-limit controls as no-cost compensating measures.
- **20 unused indexes (INFO).** No changes. Check query workload and age before considering any removal.

Read-only current database footprint: 40 migration-history rows, 69 public functions (all 69 reported SECURITY DEFINER), 33 public relations, 33 RLS-enabled tables, 22 public policies. All six game settings remain disabled. No production mutation occurred during this refresh.
