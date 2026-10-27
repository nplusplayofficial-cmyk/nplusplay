# Legacy table privilege follow-up — 2026-10-24

## Read-only production evidence

A live privilege query (no DDL/DML) returned `true` for `anon` on each of SELECT, INSERT, UPDATE and DELETE for both `public.manual_deposits` and `public.user_bank_details`. The same broad table grants are present for `authenticated`. Existing RLS policies are scoped to the `authenticated` role and owner identity; there are no `anon` policies in the audited policy listing, but grants to `anon` are unnecessary defense-in-depth exposure. A follow-up read-only catalog snapshot on 2026-10-27 also found the same anonymous grants on `public.withdraw_requests` (owner `postgres`, RLS enabled).

Other checks in this audit found direct write privileges restricted on `demo_wallets`, `demo_wallet_transactions`, `deposit_requests` and `withdrawal_requests`. The legacy `manual_deposits` and `user_bank_details` results stand out as cleanup candidates.

## Candidate fix

- Candidate migration `supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql` revokes all privileges from `PUBLIC` and `anon` on all three legacy tables: `manual_deposits`, `user_bank_details`, and `withdraw_requests`. The legacy SQL entry point is now a wrapper around this single migration source.
- It intentionally keeps `authenticated` table grants and existing RLS policies unchanged.
- `qa/test-legacy-table-privilege-hardening.sql` exercises the migration in a fresh disposable schema and checks anonymous grants are gone from all three tables, authenticated owner-scoped access contracts are preserved, and RLS remains enabled. `qa/test-legacy-browser-route-readonly.cjs` additionally guards the current Admin `manual_deposits` reconciliation screen as SELECT-only and forbids browser queries to `user_bank_details` / `withdraw_requests`. Authenticated grants are preserved until the legacy route contract is deliberately changed.

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
## Browser-route regression guard

- `qa/test-legacy-browser-route-readonly.cjs` scans browser source and fails if any front-end code directly queries `user_bank_details` or `withdraw_requests`, or if `manual_deposits` is queried outside `admin-deposits.html`.
- It asserts the legacy Admin block selects rows only and sends no legacy record to an RPC, preventing accidental approval/credit behavior.
- The Static QA workflow now runs this guard after the disposable table-privilege test. It does not substitute for live hosted-user testing.

## Latest candidate test status (2026-10-27)

- Static QA + desktop/mobile browser smoke: [PASS](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40482213478).
- Release Smoke: [PASS](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40482213497).
- Both ran against candidate commit `a24b6ace7d6194b8bd7575f774a5b6e04a4d3980`. The new migration remains an unmerged candidate and has not been applied to production. The canonical clean-replay/schema-lineage gate remains open.
