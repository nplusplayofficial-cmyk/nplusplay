# N+ PLAY audit notes — 2026-10-15

## Confirmed live changes (Supabase Production)
A verified custom-format backup was created locally at `C:\\Users\\Natarajan K\\NPLUS-PLAY-DB-BACKUP\\nplus-play-full-2026-10-15.dump`. Archive metadata is readable with `pg_restore --list`; a restore into an isolated database has not yet been tested.

The following database hardening was then applied and read-only verified:
- Added `profiles.role` trigger protection; a rollback-only test confirmed a non-admin promotion attempt is blocked.
- Removed anonymous EXECUTE on the generic wallet RPC and the admin SECURITY DEFINER RPC set; authenticated calls remain granted and the RPCs retain their own authorization checks.
- Removed direct anon/authenticated write privileges from wallet and transaction tables; authenticated users retain own-row SELECT.
- Consolidated duplicate deposit SELECT/INSERT policies and optimized RLS expressions using `(SELECT auth.uid())`.
- Added profile owner/admin SELECT policy, kept own-row profile update policy, and added reviewed_by/updated_by/transaction indexes.
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
- The signup code calls `nplus_phone_is_registered`; it remains anon-executable for compatibility and leaks whether a phone is already registered. Replace this with a rate-limited/less-enumerable design before a wider public launch.
- Verify that Auth email OTP delivers successfully and that the auth.users trigger stores email/mobile and creates exactly ₹108 for new users. Do not modify existing balances.
- The checked-in `supabase-schema.sql` is an old/basic template with a ₹1,000 default; do not run it over production.
- Leaked password protection still needs to be enabled in Supabase Auth settings.

## Critical game-security blocker
- The live `nplus_wallet_change` function accepts a client-supplied delta and prevents negative balances but does not prove positive `GAME_WIN` deltas were earned.
- WINGO, MotoRace, and Aviator browser code currently asks the generic wallet RPC for positive wins; some other games' settlement flow is unverified.
- Do not claim tamper-resistant game settlement until bets, outcomes, payout amounts and replay/idempotency are validated on the server and every game is tested.

## Limits
The database hardening has been applied in Production and verified by catalog/privilege queries. It has not undergone a full browser signup/login/deposit/game end-to-end test, and there is no verified restore test yet. PR changes remain on the separate branch, not merged into main.
