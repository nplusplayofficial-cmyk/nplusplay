# Legacy table privilege follow-up — 2026-10-24

## Read-only production evidence

A live privilege query (no DDL/DML) returned `true` for `anon` on each of SELECT, INSERT, UPDATE and DELETE for both `public.manual_deposits` and `public.user_bank_details`. The same broad table grants are present for `authenticated`. Existing RLS policies are scoped to the `authenticated` role and owner identity; there are no `anon` policies in the audited policy listing, but grants to `anon` are unnecessary defense-in-depth exposure. A follow-up read-only catalog snapshot on 2026-10-27 also found the same anonymous grants on `public.withdraw_requests` (owner `postgres`, RLS enabled).

Other checks in this audit found direct write privileges restricted on `demo_wallets`, `demo_wallet_transactions`, `deposit_requests` and `withdrawal_requests`. The legacy `manual_deposits` and `user_bank_details` results stand out as cleanup candidates.

## Candidate fix

- `sql/NPLUS_PLAY_LEGACY_TABLE_PRIVILEGE_HARDENING_2026-10-24.sql` now revokes all privileges from `PUBLIC` and `anon` on all three legacy tables: `manual_deposits`, `user_bank_details`, and `withdraw_requests`.
- It intentionally keeps `authenticated` table grants and existing RLS policies unchanged.
- `qa/test-legacy-table-privilege-hardening.sql` uses a fresh disposable schema to check anonymous grants are gone from all three tables, authenticated owner-scoped access contracts are preserved, and RLS remains enabled. The current Admin page reads `manual_deposits` as authenticated but never changes those legacy rows; authenticated grants are therefore preserved until the legacy route is retired.

## Safety / release gate

This candidate is not a canonical migration and was not run on production. The migration history is still being reconciled; do not deploy this SQL until its ordering/preconditions are reviewed against the real history and a disposable replay. If the legacy tables are retired from the app after the demo-only route rollout, prefer a coordinated least-privilege release that confirms no active page requires them.

## Verified elsewhere

- `anon` cannot execute `public.nplus_phone_is_registered(text)` in the current privilege snapshot.
- `anon` cannot execute the privileged Aviator worker-tick function.
- The generic wallet positive-credit guard has a passing disposable PostgreSQL contract test in the current QA branch.

## Final state

Evidence only. No production schema, grants, wallet/ledger rows, user records, game settings, migration history or cron configuration were changed.

## 2026-10-27 catalog follow-up

Read-only production catalog evidence now confirms:
- `manual_deposits`: anonymous direct SELECT/INSERT/UPDATE/DELETE grants exist; Admin UI still SELECTs the legacy table for read-only reconciliation.
- `user_bank_details`: anonymous direct grants exist on a table containing bank/UPI fields; RLS has authenticated owner policies and no anonymous policies.
- `withdraw_requests`: anonymous direct grants also exist; current product withdrawal flow uses the newer `withdrawal_requests` table and server RPCs.

The candidate hardening script and isolated PostgreSQL test now include all three tables. It removes `PUBLIC`/`anon` privileges only and deliberately preserves authenticated grants and owner policies to avoid an unreviewed client break. The candidate remains separate from the canonical migration chain and has not been applied to production.
