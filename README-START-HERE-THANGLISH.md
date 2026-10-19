# N+ PLAY — Premium Audit Fixes (virtual-credit demo only)

This branch is a review candidate, not a claim that N+ PLAY is production-secure. It keeps the current plain HTML/CSS/JavaScript + Supabase architecture and does not migrate to Next.js.

## Repository/code changes in this branch
- Adds the missing, correctly named admin-users.html user-management page and removes the typo duplicate.
- Adds assets/nplus-icon.svg, matching the icon path used by manifest.webmanifest and sw.js.
- Adds deposit-demo.html and deposit-history.html for idempotent server-side virtual-credit requests and per-user history.
- Adds withdraw.html, withdrawal-history.html and admin-withdrawals.html for status-only demo withdrawal requests; review never moves wallet credits or pays cash.
- Adds sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql plus a disposable PostgreSQL request/idempotency/authorization test. Review and stage this SQL and the matching frontend together before any production rollout.
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
- Consolidated redundant deposit policies and optimized RLS expressions; tightened table grants to least privilege, retained owner/admin read access where the UI needs it, aligned the wallet default to ₹108 (existing balances unchanged), and added missing FK/ledger indexes.
- The exact migration is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. Do not rerun manually on this production project; the change is already applied.

## Remaining database/auth checks
- Supabase leaked-password protection is still disabled and must be enabled in Auth settings.
- Live `main` still calls `nplus_phone_is_registered(text)` until this branch is merged/deployed, so anon EXECUTE remains temporarily to avoid breaking current signup. This branch removes that lookup and relies on the database unique mobile index. After deployment and signup testing, revoke anon EXECUTE on the old RPC.
- For signup OTP, the Confirm signup email template must use `{{ .Token }}`; test actual email delivery and verification in the live project. Current code expects a six-digit code.
- Verify a test signup creates a profile and ₹108 wallet, and that normal login works. Do not modify existing balances.
- Do not use the old `supabase-schema.sql` basic template over the production database; it has an obsolete ₹1,000 default.

## Current game-security and release status
- The candidate migrates WINGO, MotoRace and Aviator to server-owned virtual-credit bet/round/settlement RPCs with replay protection and wallet-ledger writes.
- K3, 5D and TRX WINGO betting are intentionally paused in the candidate until their payout rules are reviewed and matching server settlement is implemented.
- The live production `main` still uses the legacy wallet path and does not yet have the new settlement tables. Do not deploy the candidate HTML before its matching reviewed SQL, and do not apply the post-rollout wallet guard before every active frontend path has migrated.
- No cash deposits, cash payouts or cash withdrawals are supported; demo credits have no cash value. The candidate withdrawal screen is a status-only simulation.

## Verification
- Candidate commit `cc10da4e4e2d78436e3dd49f147ce36408413935` passed static HTML/JavaScript/local-link QA and all eight disposable PostgreSQL suites.
- Push CI: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39017662316
- Pull-request CI: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39017665739
- The baseline eight-suite set covers WINGO, Admin game status, MotoRace, Aviator, generic wallet guard, phone-enumeration revocation, Admin user tools and Admin deposit actions. This candidate adds a ninth disposable PostgreSQL suite for demo request idempotency, Admin authorization and unchanged wallet/ledger checks. CI for the current head must pass before treating the updated candidate as verified. These tests do not cover live Supabase Auth or a real browser.
- Latest read-only production inspection found no new settlement tables; all six live game toggles remain enabled; anon can still execute `nplus_phone_is_registered(text)`; authenticated users can still execute the legacy wallet RPC. This is why production rollout remains blocked.
- The PR is draft and unmerged. No production writes were made during this verification, and existing wallet balances were not changed.


## Demo referral (virtual credits only)
- Each existing/new profile receives its own unique referral code from the database.
- Share the link shown in Promotion Center. It opens `auth.html?ref=CODE`, pre-fills the optional signup field and applies attribution only after successful email OTP verification.
- The referrer earns 20 virtual demo credits once only after N+ ADMIN approves the referred account's `DEMO_CREDIT` request for 200 or more virtual credits. This is not a real deposit or cash reward; demo credits have no cash value.
- Local SQL order: make sure the demo request schema exists, then apply `supabase/migrations/20261019000200_demo_referrals.sql` with `npx supabase migration up --local`. Do not run `supabase db reset`; that would reset local staging data.
- CI includes a disposable PostgreSQL test for unique codes, self-referral rejection, immutable attribution, the 200-credit qualification threshold, one-time reward and wallet/ledger consistency. The UI and migration remain candidate-only until the local signup flow and Admin approval are browser-tested.
