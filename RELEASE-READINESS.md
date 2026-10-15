# N+ PLAY — Release readiness (2026-10-15)

## Done
- Created local custom-format Supabase database backup and verified its archive list (not restore-tested).
- Live DB: added a role-change guard trigger; rollback-only test confirmed non-admin role escalation is blocked.
- Live DB: removed anonymous EXECUTE from the wallet/admin RPC set, removed direct wallet/ledger browser writes, preserved authenticated own-row reads and RPC access.
- Live DB: consolidated duplicate deposit policies, optimized RLS policy expressions and added FK/ledger indexes.
- Live DB: created `profiles_phone_digits_unique_idx`; current profile values were checked and no duplicate digit-normalized phone groups existed.
- Branch: fixed missing admin-users page, PWA icon path, missing demo deposit route, legacy REAL_MONEY flag and forgot-password links.
- Branch: restored email OTP signup UI and added static QA checks/CI. The latest recorded static QA run passed, but subsequent branch edits need a fresh check.

## Not release-ready until these gates pass
1. Run a restore test in an isolated/staging database using a separate test project. Do not restore over production.
2. Confirm Supabase Confirm signup email template uses `{{ .Token }}`; test code delivery and verifyOtp end-to-end.
3. Enable leaked-password protection in Supabase Auth settings, then test sign-up and login.
4. Verify profile trigger and new-wallet balance ₹108 on a test account; do not change existing wallet balances.
5. **Critical:** replace client-authoritative wins with server-authoritative bet/round/result/idempotent payout RPCs for WINGO, K3, 5D, TRX WINGO, MotoRace and Aviator. Generic `nplus_wallet_change` still allows authenticated clients to submit positive deltas.
6. Verify pending / approved / rejected demo-credit requests: pending and rejected preserve balance; only admin approval credits.
7. Test all user/admin pages and games on desktop and mobile, then review the PR and deployment.

Production DB hardening was applied through Supabase and is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. No code PR is merged to main.
