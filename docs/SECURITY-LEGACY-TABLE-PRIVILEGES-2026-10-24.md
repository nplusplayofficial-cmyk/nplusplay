# Legacy table privilege follow-up — 2026-10-24

## Read-only production evidence

A live privilege query (no DDL/DML) returned `true` for `anon` on each of SELECT, INSERT, UPDATE and DELETE for both `public.manual_deposits` and `public.user_bank_details`. The same broad table grants are present for `authenticated`. Existing RLS policies are scoped to the `authenticated` role and owner identity; there are no `anon` policies in the audited policy listing, but grants to `anon` are unnecessary defense-in-depth exposure.

Other checks in this audit found direct write privileges restricted on `demo_wallets`, `demo_wallet_transactions`, `deposit_requests` and `withdrawal_requests`. The legacy `manual_deposits` and `user_bank_details` results stand out as cleanup candidates.

## Candidate fix

- `sql/NPLUS_PLAY_LEGACY_TABLE_PRIVILEGE_HARDENING_2026-10-24.sql` revokes all privileges from `PUBLIC` and `anon` on the two legacy tables.
- It intentionally keeps `authenticated` table grants and existing RLS policies unchanged.
- `qa/test-legacy-table-privilege-hardening.sql` uses a fresh disposable schema to check anonymous grants are gone, authenticated owner-scoped access contracts are preserved, and RLS remains enabled.

## Safety / release gate

This candidate is not a canonical migration and was not run on production. The migration history is still being reconciled; do not deploy this SQL until its ordering/preconditions are reviewed against the real history and a disposable replay. If the legacy tables are retired from the app after the demo-only route rollout, prefer a coordinated least-privilege release that confirms no active page requires them.

## Verified elsewhere

- `anon` cannot execute `public.nplus_phone_is_registered(text)` in the current privilege snapshot.
- `anon` cannot execute the privileged Aviator worker-tick function.
- The generic wallet positive-credit guard has a passing disposable PostgreSQL contract test in the current QA branch.

## Final state

Evidence only. No production schema, grants, wallet/ledger rows, user records, game settings, migration history or cron configuration were changed.