# N+ PLAY audit notes — current status as of 2026-10-23

The authoritative release status and remaining blockers are maintained at [RELEASE-READINESS.md](./RELEASE-READINESS.md). Earlier sections in this file are historical notes from 2026-10-15; statements such as “PR changes remain on a separate branch” or that the recent-activity RPC/settlement tables do not exist describe the state at that earlier inspection and must not be treated as the current state.

Latest live database changes now recorded in Supabase migration history:
- `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023`: 8 FK indexes, optimized owner-scoped RLS policies, one combined manual-deposit SELECT policy, removed redundant profile UPDATE policy.
- `20261023093056_drop_duplicate_referral_unique_indexes_20261023`: removed two standalone duplicate indexes while preserving primary/constraint-backed uniqueness.

Verification after those migrations:
- 8/8 new FK indexes present.
- 0 of the two known duplicate index names remain.
- All six game settings remain disabled.
- Read-only authorization regression checks denied a non-admin referral Admin RPC call and a non-admin wallet-adjustment RPC call; the generic wallet RPC denied arbitrary positive credits.
- No balances were changed during these checks.

The site deployment and navigation change are merged, but this is not a claim of complete production launch readiness. See RELEASE-READINESS.md for the residual Security Advisor notices, pending live-browser tests, untested backup restore, disabled game release gates, and draft PRs.

---

# N+ PLAY audit notes — 2026-10-15

## Confirmed live changes (Supabase Production)
A verified custom-format backup was created locally at `C:\\Users\\Natarajan K\\NPLUS-PLAY-DB-BACKUP\\nplus-play-full-2026-10-15.dump`. Archive metadata is readable with `pg_restore --list`; a restore into an isolated database has not yet been tested.

The following database hardening was then applied and read-only verified:
- Added `profiles.role` trigger protection; a rollback-only test confirmed a non-admin promotion attempt is blocked.
- Removed anonymous EXECUTE on the generic wallet RPC and the admin SECURITY DEFINER RPC set; authenticated calls remain granted and the RPCs retain their own authorization checks.
- Removed direct anon/authenticated write privileges from wallet and transaction tables; normal users retain own-row SELECT, and admin-role SELECT access remains for admin deposit/report screens.
- Added a unique expression index on digit-normalized profile phone values after confirming 5 existing profiles had no duplicate phone groups.
- Consolidated duplicate deposit SELECT/INSERT policies, optimized RLS expressions using `(SELECT auth.uid())`, and restricted direct table grants: deposit updates/deletes, profile inserts/deletes, and direct game-control writes are revoked; controlled SECURITY DEFINER RPCs perform trusted writes.
- Added profile owner/admin SELECT policy, kept own-row profile update policy, aligned future wallet inserts to ₹108 without changing existing balances, and added reviewed_by/updated_by/transaction indexes.
- Removed public EXECUTE on the auth profile trigger function.

These changes did not change existing wallet balances or execute any game result/settlement. The backup remains sensitive and must not be committed/uploaded to GitHub.

## Repository defects fixed on the branch
- Correct admin User Management page and removed the misspelled duplicate.
- Add PWA icon at the manifest/service-worker expected path and bump shell cache version.
- Add a pending virtual-credit request page and route deposits only to demo mode; payment gateway placeholder is disabled.
- Set legacy REAL_MONEY configuration to false.
- Fix forgot-password links to the existing auth page.
- Restore signup email-OTP UI while retaining email + mobile + password login.
- Add a static QA GitHub Actions workflow and release-readiness docs.

## Authentication / release checks
- Signup uses Supabase signUp and verifyOtp({ email, token, type: "email" }); Confirm signup email template must use `{{ .Token }}` for a six-digit code, rather than only `{{ .ConfirmationURL }}`.
- The live `main` signup code still calls `nplus_phone_is_registered`, so that function remains anon-executable until the PR is merged and deployed. The branch removes the lookup and relies on `profiles_phone_digits_unique_idx`, which is a database-enforced unique index. After deployment and signup testing, revoke anon EXECUTE on the old RPC.
- Verify that Auth email OTP delivers successfully and that the auth.users trigger stores email/mobile and creates exactly ₹108 for new users. Do not modify existing balances.
- The checked-in `supabase-schema.sql` is an old/basic template with a ₹1,000 default; do not run it over production.
- Leaked password protection still needs to be enabled in Supabase Auth settings.

## Critical game-security blocker
- The live `nplus_wallet_change` function accepts a client-supplied delta and prevents negative balances but does not prove positive `GAME_WIN` deltas were earned.
- WINGO, MotoRace, and Aviator browser code currently asks the generic wallet RPC for positive wins; some other games' settlement flow is unverified.
- Do not claim tamper-resistant game settlement until bets, outcomes, payout amounts and replay/idempotency are validated on the server and every game is tested.

## Limits
The database hardening has been applied in Production and verified by catalog/privilege queries. It has not undergone a full browser signup/login/deposit/game end-to-end test, and there is no verified restore test yet. PR changes remain on the separate branch, not merged into main.
