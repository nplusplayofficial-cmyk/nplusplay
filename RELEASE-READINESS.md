# N+ PLAY — Release readiness (2026-10-15)

## Done
- Created local custom-format Supabase database backup and verified its archive list (not restore-tested).
- Live DB: added a role-change guard trigger; rollback-only test confirmed non-admin role escalation is blocked.
- Live DB: removed anonymous EXECUTE from the wallet/admin RPC set, removed direct wallet/ledger browser writes, preserved own-row reads plus admin-role reads required by admin pages, and verified authenticated RPC access.
- Live DB: consolidated duplicate deposit policies, optimized RLS policy expressions, applied least-privilege table grants, retained admin-only reads needed by admin screens, and added FK/ledger indexes.
- Live DB: created `profiles_phone_digits_unique_idx`; current profile values were checked and no duplicate digit-normalized phone groups existed. Aligned the future wallet default to ₹108 (no existing wallet balance changed).
- Branch: fixed missing admin-users page, PWA icon path, missing demo deposit route, legacy REAL_MONEY flag and forgot-password links.
- Branch: restored email OTP signup UI and added static QA checks/CI. The latest recorded static QA run passed, but subsequent branch edits need a fresh check.


## Security-branch progress (not deployed)

- Added a server-owned WINGO backend: private rounds/bets tables, server-side outcomes, atomic wallet debit, idempotent requests, one-time settlement, history and reload recovery.
- Migrated `wingo.html` to server-side placement/settlement; its browser no longer issues generic `GAME_WIN` credits.
- Added a MotoRace backend: server-owned round outcomes, validated selections, server-computed 1.5% demo fee, server-side 2x winner return, one-time settlement and own-bet/history recovery.
- Migrated `motorace.html` away from browser-generated results and generic wallet credit/debit calls.
- Added `sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql` plus a disposable PostgreSQL test. After the matching frontend/server RPC rollout only, this migration rejects caller-supplied positive deltas while preserving negative virtual-stake debits. It has not been run against production.
- Added an Aviator backend: server-owned crash points/timing, atomic server-side stake debit, server-time-based manual cash-out, server-handled auto cash-out and post-crash loss settlement. The client no longer decides crash points or credits its own cash-out amount.
- Migrated `aviator.html` to those RPCs and removed its local-balance fallback.
- Added an isolated PostgreSQL 17 QA workflow. Latest recorded successful run: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/38768941850. It passed the 36-page static check and disposable database tests for WINGO, MotoRace and Aviator.
- These are branch/CI tests only. No new settlement SQL has been run against the live Supabase project, and no code PR has been merged to `main`.

## Remaining release blockers

1. **K3, 5D and TRX WINGO payout rules are not specified in the current source pages.** They currently calculate outcomes client-side and charge demo stakes, but the inspected source contains no matching wallet-win settlement/payout table. Do not guess return rates; define and approve those rules, then migrate them to server-side rounds/settlement.
2. The live generic `nplus_wallet_change` RPC still accepts authenticated positive deltas. Do not close that legacy path until the remaining active game flows are migrated and regression-tested; then block arbitrary positive client credits without breaking legitimate demo bets.
3. WINGO, MotoRace and Aviator now require matching new schema/RPC migrations. Never deploy these updated HTML pages without their reviewed server schema/functions.
4. Legacy bets kept only in browser `localStorage` have no server-issued settlement record. The migrated pages deliberately will not award credits for those records. Plan and test a user-safe reconciliation/transition notice; never reset or silently alter existing wallet balances.
5. The live anonymous `nplus_phone_is_registered(text)` RPC can reveal phone registration. After the updated signup code is deployed and duplicate-mobile signup is verified, revoke its client EXECUTE permission.
6. Leaked-password protection is unavailable on the current Free plan according to the project dashboard. Do not upgrade just to clear the advisor; retain strong password rules and document the remaining warning.
7. The database backup archive was readable but has not been restore-tested. Test restore in a separate isolated database/project, never production.
8. End-to-end Supabase Auth/email OTP, profile + ₹108 wallet creation for a new test account, deposits/admin workflows, and real browser desktop/mobile regression are still pending. Email template `Confirm signup` already contains `{{ .Token }}`; keep production email confirmation OFF until the new signup flow is actually deployed/tested.

## Merge gates

- Approve K3/5D/TRX demo payout rules.
- Pass automated tests for all six games, including duplicate/replayed settlement, insufficient balance, bad selection/amount, reload and parallel requests.
- Validate RPC permissions/RLS and Auth/deposit/admin behavior against an isolated Supabase test project.
- Review the final diff and workflow logs, then deploy the matching SQL + frontend in a controlled order. Keep PR #2 and this security branch unmerged until these gates pass.

Production DB hardening was applied through Supabase and is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. No code PR is merged to main.
