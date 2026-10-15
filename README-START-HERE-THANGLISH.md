# N+ PLAY — Premium Audit Fixes (virtual-credit demo only)

This branch is a review candidate, not a claim that N+ PLAY is production-secure. It keeps the current plain HTML/CSS/JavaScript + Supabase architecture and does not migrate to Next.js.

## Changes in this branch
- Adds the missing, correctly named admin-users.html user-management page.
- Adds assets/nplus-icon.svg, matching the icon path used by manifest.webmanifest and sw.js.
- Adds deposit-demo.html so the demo deposit request route exists. It creates a pending row in public.deposit_requests; it must not change a wallet balance until an admin-approved server RPC runs.
- Updates deposit.html to route only to the virtual-credit request flow and reject the disabled payment-gateway placeholder.
- Sets legacy core/config.js to REAL_MONEY: false.
- Bumps the service-worker cache version and fixes forgot-password links to use the existing auth.html.
- Restores email OTP verification for account creation while retaining email + mobile + password login.
- Adds static QA checks and SQL migration drafts for admin user tools and profile/deposit safeguards.

## Before any database change
1. Take and verify a database backup first. Do not use an unreviewed schema reset on the live project.
2. Review the live schema, RLS policies, triggers, and definitions for nplus_wallet_change, nplus_approve_deposit, nplus_reject_deposit, and nplus_phone_is_registered.
3. Review sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql and sql/NPLUS_PLAY_PROFILE_DEPOSIT_GUARDS.sql against that live schema. Do not run either script just because it exists in this branch.
4. Test on a staging project or backed-up database where possible. Apply approved SQL separately and verify its result before testing the website.

The foundation migration resets policies on demo_wallets and demo_wallet_transactions, grants users own-row access, preserves admin read access for admin screens via the existing nplus_is_admin() helper, and revokes direct browser table writes. That affects existing behavior, so it requires a verified backup and a review of how admin pages read those tables.

## Email OTP requirement
Signup now calls Supabase signUp, then verifies the six-digit code with verifyOtp(type=email). Login remains password-based and checks the entered mobile number against the profile.

For six-digit signup codes, the Supabase Confirm signup email template must use {{ .Token }} rather than {{ .ConfirmationURL }}. If the current template still sends a clickable confirmation link, the user will not receive a code that matches the UI. Email-delivery restrictions/custom SMTP also need verification before opening signup to the public. See the current Supabase template guide: https://supabase.com/docs/guides/auth/auth-email-templates

## Security release blocker
The browser game pages can call nplus_wallet_change with positive GAME_WIN deltas. The currently available function definition checks authentication and prevents negative balances, but does not itself prove a win was earned. Because each game currently calculates rounds/payouts in the browser, a player may be able to forge a positive credit unless the live RPC has additional checks not captured in the available definition.

Do not merge this branch as a fully secured game release until game bets, round outcomes and payouts are validated atomically on the server (RPC/Edge Functions), arbitrary client-supplied positive credits are blocked, and duplicate/replayed settlement attempts are tested. Removing positive credits prematurely would break winning settlements, so do not patch the legacy RPC without replacing the game settlement flow.

## Verification
- Static QA now checks inline JavaScript syntax, required files, the manifest/service-worker assets, and static local links.
- Run node qa/verify-project.js from the repository root.
- Current CI passed for the earlier staged code; check the latest PR check after any further push. Live Supabase RPC behavior, OTP email delivery, game settlement, and browser runtime still need hands-on testing.
- Current live main was not changed by this branch. Review the Pull Request before merging.
