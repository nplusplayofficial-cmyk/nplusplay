# N+ PLAY — Premium Audit Fixes (virtual-credit demo only)

This branch is a review candidate, not a claim that N+ PLAY is production-secure. It keeps the current plain HTML/CSS/JavaScript + Supabase architecture and does not migrate to Next.js.

## Repository/code changes in this branch
- Adds the missing, correctly named admin-users.html user-management page and removes the typo duplicate.
- Adds assets/nplus-icon.svg, matching the icon path used by manifest.webmanifest and sw.js.
- Adds deposit-demo.html so the demo request route exists; it submits a pending virtual-credit request and does not immediately change the balance.
- Updates deposit.html to use virtual-credit requests only and block the unimplemented gateway route.
- Sets legacy core/config.js to REAL_MONEY: false.
- Bumps the service-worker cache version and fixes forgot-password links to use auth.html.
- Restores email-OTP signup while retaining email + mobile + password login.
- Adds static QA checks, GitHub Actions CI, a live-hardening migration record and release checklist.

## Verified local database backup
A custom-format backup archive was created on the operator's computer:
`C:\Users\Natarajan K\NPLUS-PLAY-DB-BACKUP\nplus-play-full-2026-10-15.dump`
The archive listing was read successfully with `pg_restore --list` (661 TOC entries). It has not been restored into a separate test database; keep the dump file private and never upload it to GitHub.

## Confirmed live database hardening (applied 2026-10-15)
- Added a trigger to prevent non-admin role changes on profiles. A rollback-only test confirmed a non-admin promotion attempt is blocked.
- Removed anonymous EXECUTE from the generic wallet RPC and administrative SECURITY DEFINER RPCs, while preserving authenticated access and each function's internal authorization checks.
- Revoked direct anon/authenticated writes to wallet and transaction tables; normal users read their own rows, while admin-role reads remain available for admin deposit/report screens.
- Added a unique index on normalized profile phone numbers after confirming no current duplicate phone groups.
- Consolidated redundant deposit policies and optimized RLS expressions; added profile owner/admin reads, aligned the wallet default to ₹108 (existing balances unchanged), and added missing FK/ledger indexes.
- The exact migration is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. Do not rerun manually on this production project; the change is already applied.

## Remaining database/auth checks
- Supabase leaked-password protection is still disabled and must be enabled in Auth settings.
- Live `main` still calls `nplus_phone_is_registered(text)` until this branch is merged/deployed, so anon EXECUTE remains temporarily to avoid breaking current signup. This branch removes that lookup and relies on the database unique mobile index. After deployment and signup testing, revoke anon EXECUTE on the old RPC.
- For signup OTP, the Confirm signup email template must use `{{ .Token }}`; test actual email delivery and verification in the live project. Current code expects a six-digit code.
- Verify a test signup creates a profile and ₹108 wallet, and that normal login works. Do not modify existing balances.
- Do not use the old `supabase-schema.sql` basic template over the production database; it has an obsolete ₹1,000 default.

## Critical game-security blocker
The browser game pages can call `nplus_wallet_change` with positive `GAME_WIN` deltas. That RPC prevents negative balances but does not itself verify that a positive win was earned. Client-generated outcomes can be forged.

Do not merge this branch as a fully secured release until every game uses server-authoritative bets/rounds/results/payouts with replay/idempotency protection. Removing positive credits immediately would break current winning settlements; the server settlement replacement has to land before tightening those credits.

## Verification
- Static QA workflow completed successfully on the latest branch commit: 36 HTML pages checked, 0 warnings and 0 static errors. This is static validation only.
- It does not test live Supabase auth, RLS, RPC or browser/game settlement behaviour.
- Production SQL hardening was applied via Supabase, but app code remains isolated on this branch. The Pull Request is draft and not merged into main.
