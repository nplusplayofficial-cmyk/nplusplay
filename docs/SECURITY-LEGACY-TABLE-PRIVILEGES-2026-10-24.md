# Legacy table privilege follow-up — 2026-10-24

## Read-only production evidence

A live privilege query (no DDL/DML) returned `true` for `anon` on each of SELECT, INSERT, UPDATE and DELETE for both `public.manual_deposits` and `public.user_bank_details`. The same broad table grants are present for `authenticated`. Existing RLS policies are scoped to the `authenticated` role and owner identity; there are no `anon` policies in the audited policy listing, but grants to `anon` are unnecessary defense-in-depth exposure. A follow-up read-only catalog snapshot on 2026-10-27 also found the same anonymous grants on `public.withdraw_requests` (owner `postgres`, RLS enabled).

Other checks in this audit found direct write privileges restricted on `demo_wallets`, `demo_wallet_transactions`, `deposit_requests` and `withdrawal_requests`. The legacy `manual_deposits` and `user_bank_details` results stand out as cleanup candidates.

## Candidate fix

- Candidate migration `supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql` revokes all privileges from `PUBLIC` and `anon` on all three legacy tables: `manual_deposits`, `user_bank_details`, and `withdraw_requests`. The legacy SQL entry point is now a wrapper around this single migration source.
- It intentionally keeps `authenticated` table grants and existing RLS policies unchanged.
- `qa/test-legacy-table-privilege-hardening.sql` exercises the current migration in a fresh disposable schema and checks that direct privileges are removed from PUBLIC/anon/authenticated on all three tables, then authenticated SELECT-only is restored on `manual_deposits` for the read-only Admin screen. It also verifies RLS and policy definitions remain intact. `qa/test-legacy-browser-route-readonly.cjs` guards the Admin `manual_deposits` route as SELECT-only and forbids browser queries to `user_bank_details` / `withdraw_requests`. The older authenticated-grant-preserving behavior below is superseded by the 2026-10-27 refinement.

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

The initial candidate removed `PUBLIC`/`anon` privileges only. This statement was superseded by the 2026-10-27 refinement below: the current candidate revokes direct browser-role grants across all three legacy tables and then grants authenticated SELECT only on `manual_deposits`, because that is the only current browser route using these tables. It preserves rows, owner, RLS flags and policy definitions; it remains candidate-only and has not been applied to production.
## Browser-route regression guard

- `qa/test-legacy-browser-route-readonly.cjs` scans browser source and fails if any front-end code directly queries `user_bank_details` or `withdraw_requests`, or if `manual_deposits` is queried outside `admin-deposits.html`.
- It asserts the legacy Admin block selects rows only and sends no legacy record to an RPC, preventing accidental approval/credit behavior.
- The Static QA workflow now runs this guard after the disposable table-privilege test. It does not substitute for live hosted-user testing.

## Latest candidate test status (2026-10-27)

- Static QA + desktop/mobile browser smoke: [PASS](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40482213478).
- Release Smoke: [PASS](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40482213497).
- Both ran against candidate commit `a24b6ace7d6194b8bd7575f774a5b6e04a4d3980`. The new migration remains an unmerged candidate and has not been applied to production. The canonical clean-replay/schema-lineage gate remains open.


## 2026-10-27 candidate least-privilege refinement

The current production catalog reports broad table grants for both `anon` and `authenticated` on all three legacy relations, including DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN. Read-only inspection found only `admin-deposits.html` directly SELECTs `manual_deposits`; current browser routes do not query `user_bank_details` or `withdraw_requests`, and a read-only `pg_proc.prosrc` scan found no current public function bodies referencing these legacy table names.

The integration candidate now proposes a narrower direct table-access contract:
- revoke direct grants from PUBLIC/anon/authenticated on all three tables;
- grant authenticated `SELECT` on `manual_deposits` only, for the existing read-only Admin reconciliation page;
- keep `user_bank_details` and `withdraw_requests` without browser-role direct table grants;
- preserve rows, table owner, RLS flags and all existing policy definitions.

The disposable SQL regression now asserts every browser-role privilege, including TRUNCATE/REFERENCES/TRIGGER/MAINTAIN, and the exact authenticated contract. This remains a candidate proposal and **has not been applied to production**. A fresh Static QA run must pass; canonical migration ordering and hosted route checks remain release gates.
