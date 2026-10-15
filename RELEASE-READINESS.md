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

- Added `sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql`: private server-owned WINGO round/bet tables, server-side round result, atomic bet debit, idempotency, locked one-time settlement and payout ledger writes.
- Updated only the WINGO branch page to call server placement/settlement RPCs; removed its direct client-issued `GAME_WIN` wallet credit calls.
- Added a static QA guard and an isolated PostgreSQL test harness/workflow. Check the current GitHub Actions result before calling the SQL tested.
- No settlement SQL has been run against the live Supabase project. The migration is draft-only and needs code review plus disposable PostgreSQL and isolated Supabase runtime tests.

## Still blocks release

1. **Only WINGO is migrated in the security branch.** K3, 5D, TRX WINGO, MotoRace and Aviator still contain client-derived results, legacy wallet calls or incomplete settlement behavior.
2. The live generic `nplus_wallet_change` RPC still accepts caller-supplied positive deltas. Keep PR #2 unmerged and do not label the product secure until all legitimate game pages move to server-owned settlement and the legacy credit path is closed.
3. WINGO uses a new schema. Apply it only through a reviewed migration after tests; do not deploy the updated WINGO HTML without its matching schema/RPCs.
4. Legacy WINGO bets in browser `localStorage` do not have server-issued bet IDs. The new frontend intentionally does not award credits from such local-only records. Decide and test a migration/reconciliation plan before deployment; do not reset wallet balances.
5. The live anonymous `nplus_phone_is_registered(text)` RPC and disabled leaked-password protection remain outstanding. Confirm signup/email OTP settings have not been switched on in production.
6. Backup archive is readable but not restore-tested. Test restore only in a separate isolated database/project.
7. Test deposits, admin pages and every game on desktop/mobile, then review the whole PR before merging.

## Not release-ready until these gates pass
1. Run a restore test in an isolated/staging database using a separate test project. Do not restore over production.
2. Confirm Supabase Confirm signup email template uses `{{ .Token }}`; test code delivery and verifyOtp end-to-end. Once this branch is deployed and duplicate-mobile signup is tested, revoke anon EXECUTE on the now-unused `nplus_phone_is_registered` RPC.
3. Enable leaked-password protection in Supabase Auth settings, then test sign-up and login.
4. Verify profile trigger and new-wallet balance ₹108 on a test account; do not change existing wallet balances.
5. **Critical:** replace client-authoritative wins with server-authoritative bet/round/result/idempotent payout RPCs for WINGO, K3, 5D, TRX WINGO, MotoRace and Aviator. Generic `nplus_wallet_change` still allows authenticated clients to submit positive deltas.
6. Verify pending / approved / rejected demo-credit requests: pending and rejected preserve balance; only admin approval credits.
7. Test all user/admin pages and games on desktop and mobile, then review the PR and deployment.

Production DB hardening was applied through Supabase and is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. No code PR is merged to main.
