# N+ PLAY audit notes — 2026-10-15

## Repository defects fixed on the branch
- admin.html linked to admin-users.html, but only a misspelled admin-users.htlm existed; that file duplicated the reports page. This branch adds the correct User Management page and removes the typo duplicate.
- manifest.webmanifest and sw.js expected assets/nplus-icon.svg, while the icon existed only under assest/. This branch adds the correctly located asset and bumps the service-worker cache version.
- deposit.html navigated to deposit-demo.html or deposit-gateway.html, neither of which existed. This branch adds a pending virtual-credit request page and disables the unimplemented payment-gateway route.
- forgot-password.html linked to missing login.html; those static links now point to auth.html.
- Legacy core/config.js said MODE: "DEMO" but set REAL_MONEY: true; the branch sets it to false.
- The checked-in auth files had password-only signup despite the intended email-OTP signup flow. The branch restores signup OTP code handling while retaining email + mobile + password login.

## Authentication / database release checks
- Signup uses Supabase signUp and verifyOtp({ email, token, type: "email" }); therefore the Confirm signup email template must render {{ .Token }} rather than only {{ .ConfirmationURL }}.
- The sign-up code calls nplus_phone_is_registered. Verify that RPC exists and is executable for unauthenticated signup requests.
- Verify the auth.users profile trigger stores profile email and phone and creates the intended ₹108 new-user virtual wallet. The checked-in supabase-schema.sql is an older/basic template with a ₹1,000 default; do not run it over the existing database.
- The premium foundation SQL changes RLS on wallet/ledger tables and adds admin RPCs. It also relies on the existing nplus_is_admin() helper for admin-only table reads. Reconcile all of this against live definitions before running.
- A separate SQL guard draft removes a duplicate, weaker deposit INSERT policy and prevents ordinary users from editing profiles.role.

## Critical security blocker
- Available nplus_wallet_change definition accepts a client-supplied delta, updates the user's own wallet, and writes a ledger row. It prevents negative balances but does not verify that a positive GAME_WIN delta reflects a valid server-side game result.
- WINGO, MotoRace, and Aviator currently ask the generic wallet RPC to credit positive wins. Some other game pages show stake deductions, but their server-authoritative win settlement was not verified.
- Do not claim tamper-resistant production status until bet state, round result, payout amount and idempotency are enforced server-side and all games are tested.

## Limits of this audit
- This review reads GitHub files and static metadata. It does not execute SQL on the live Supabase project or run real browser flows.
- The branch is separate from main; no production database changes were made.
