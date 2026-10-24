# N+ PLAY production security review — read-only snapshot (2026-10-24)

## Executive decision

**Read-only review completed; security release gate remains OPEN.** No database schema, privileges, RLS policies, wallet entries, users, game settings, functions or scheduled jobs were changed while gathering this evidence.

This review separates confirmed protections from remaining release decisions. Supabase Advisor warnings about `SECURITY DEFINER` functions are not automatically proof of an exploit: those functions are often intended authenticated RPC endpoints and must enforce authorization inside their bodies. Conversely, an `EXECUTE` grant is not by itself proof that all function paths are safe.

## Current database footprint observed

- Live migration-history records: 40.
- Public-schema functions with `SECURITY DEFINER`: 69.
- Public RLS policies: 22.
- Public tables/partitioned tables with RLS enabled: 33.
- All six game-settings rows exist and are disabled: WINGO, K3, 5D, TRX, MOTO, AVIATOR.

## Supabase Security Advisor findings

Advisor snapshot observed on 2026-10-24:

| Advisor finding | Observed count/status | Interpretation |
|---|---:|---|
| RLS enabled without policies | 20 tables | Read-only follow-up below found **zero anon/authenticated SELECT/INSERT/UPDATE/DELETE table privileges on every table in this finding set**. With RLS enabled and no policies this is a backend-only, default-deny posture for browser roles; retain only if intentional. |
| Anonymous-callable SECURITY DEFINER | 1 function | `public.nplus_recent_demo_activity(integer)`, intentionally public for aggregate activity counts. Its result contract is only game key and count, with a server-clamped 1–60 minute window and fixed search path. No player identifier, stake, payout, selection or outcome is returned. |
| Authenticated-callable SECURITY DEFINER | 53 functions | These include user-facing RPCs and Admin RPCs. This warning is a review queue, **not proof of an authorization bypass**. Internal auth/ownership/admin checks must be proven for each endpoint by source review and tests. |
| Leaked-password protection disabled | 1 Auth finding | Dashboard/Auth configuration follow-up required. Confirm availability for the current project plan and enable only if supported without an unapproved plan change or added cost. Do not publish user credentials or test passwords. |

Performance Advisor also returned 20 “unused index” informational findings. Do not drop these indices just to clear the Advisor; a recent/low-traffic table may not have accumulated usage statistics, and some indexes exist for FK integrity or workload spikes. Review with actual query plans/usage before any change.

## RLS tables with no policies — direct grant cross-check

A read-only privilege query checked every public table reported as RLS-enabled with no policies. Each of the 20 tables returned:

- RLS enabled.
- `anon`: no direct SELECT/INSERT/UPDATE/DELETE table privilege.
- `authenticated`: no direct SELECT/INSERT/UPDATE/DELETE table privilege.

This corroborates that the Advisor finding is not exposing those underlying tables directly to browser roles in the current privilege snapshot. Keep server-side RPCs least-privileged and internally authorized; do not add broad policies simply to silence the Advisor.

## Wallet, profile and request-table contracts

A read-only catalog/function review confirmed:

- `public.nplus_wallet_change(numeric,text,text,text)`: `SECURITY DEFINER`, fixed search path, requires non-null `auth.uid()`, rejects null/non-finite/zero amounts, rejects **all positive generic credits**, rejects `GAME_BET`/`GAME_WIN` through the generic function, locks the caller’s own wallet row and prevents negative balance. `anon` cannot execute; `authenticated` can execute, subject to the internal guard.
- `public.nplus_admin_set_wingo_demo` has both four-argument and five-argument overloads. Both require a signed-in user with `profiles.role='admin'` and have fixed search paths; `anon` cannot execute either. The older four-argument overload is a **cleanup/replay-review item** because overlapping overloads complicate API maintenance. Do not drop it until every deployed client reference and function dependency has been checked in an isolated test.
- `public.nplus_admin_adjust_demo_wallet`, `public.nplus_admin_resolve_demo_withdrawal`, and `public.nplus_set_game_status` are not executable by `anon`; their checked definitions require `auth.uid()`, and the function calls remain subject to their internal admin guards. Authenticated EXECUTE is expected for the RPC API but should be regression-tested against non-admin callers.
- `public.nplus_phone_is_registered(text)`: `anon` and `authenticated` EXECUTE are both false in the current snapshot.
- `profiles`, `demo_wallets`, `demo_wallet_transactions`, `deposit_requests`, `withdrawal_requests`, and `game_settings` have RLS enabled; the reviewed privilege snapshot shows browser roles cannot write directly to the listed wallet/request/settings tables. `profiles` retains authenticated UPDATE grant with an own-row RLS policy and role-protection trigger.

### SECURITY DEFINER body-marker cross-check

A further read-only catalog query scanned the definitions of the 53 SECURITY DEFINER functions executable by authenticated users plus the one anon-executable function:

- 54 total functions callable by one or both browser roles were included in the query.
- All 54 have a configured fixed search path.
- All 53 authenticated-callable functions reference either auth.uid() or the shared nplus_is_admin() helper in their function text; the sole no-marker exception is nplus_recent_demo_activity(integer), the intentional public aggregate-only feed.
- The one anon-executable function is that same aggregate-only feed.

This is a **source-pattern cross-check, not a proof of every authorization branch**. Calls through helpers, owner predicates, data returned, state transitions and non-admin outcomes still need targeted authenticated regression tests. The result reduces the untriaged set but does not justify clearing the Advisor warnings automatically.

## Legacy table grant follow-up

The current database still reports table-level browser-role grants for legacy `manual_deposits` and `user_bank_details`:

- Both have RLS enabled. Their observed policies target `authenticated` and constrain reads/writes by user ownership; there is no anonymous policy in the inspected policy list.
- This does **not** prove anonymous data exposure in the current RLS configuration, but direct grants remain broader than the demo-only target design.
- Do not blindly revoke these grants in production while old `main` routes/deployments may still reference the legacy flow. First merge/deploy the reviewed demo-request UI in the right sequence, test authenticated and anonymous denial on an isolated backend, check legacy references and preserve any records needed for reconciliation, then propose a separate reviewed least-privilege migration.

## Release gates still open

1. Complete source-to-applied-body reconciliation, review the repeated migration bodies for replay safety, execute the proposed canonical chain in a fresh isolated database, and pass the backup restore acceptance gate with original ownership/ACL semantics. See the separate migration audit and fingerprint report.
2. Test Admin RPCs under real authenticated non-admin sessions in an isolated environment, particularly wallet adjustments, WINGO result controls, referral qualification/claim, deposit approval and withdrawal status review. Verify all server checks deny unauthorized users.
3. Resolve whether the four-argument `nplus_admin_set_wingo_demo` overload has any active clients; remove only via a separate tested migration after dependency analysis.
4. Review legacy `manual_deposits`/`user_bank_details` grants after demo-only UI deployment and end-to-end validation. Do not alter them during this audit.
5. Resolve the Auth leaked-password protection notice based on current plan capabilities/cost.
6. Keep K3/5D/TRX and all other games disabled until supported game rules and server-owned settlement have been approved and tested.

## Evidence/source boundaries

- Live checks performed via SELECT-only catalog, privilege, policy and Advisor reads on 2026-10-24.
- No individual user rows, emails, phone numbers, balances, request IDs or bank details are included in this report.
- The review did not attempt to change production settings, grants, functions, scheduled jobs, game flags or user/wallet data.
- This document is an audit snapshot, not approval to merge or deploy a draft PR.
