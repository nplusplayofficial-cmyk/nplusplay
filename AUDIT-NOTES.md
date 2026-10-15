# N+ PLAY audit notes — 2026-10-15

## Observed repository issues
- admin.html linked to admin-users.html, but the repository only had a typo file named admin-users.htlm; that file duplicated the reports page. This branch adds the correct User Management file and removes the misspelled duplicate.
- manifest.webmanifest and sw.js expected assets/nplus-icon.svg, while the icon existed only under assest/. This branch adds the correctly located asset and bumps the service-worker cache version.
- deposit.html navigated to deposit-demo.html or deposit-gateway.html, neither of which existed. This branch adds a pending virtual-credit request page and disables navigation to the unimplemented payment gateway.
- forgot-password.html linked to a missing login.html; this branch redirects those static links to auth.html.
- Legacy core/config.js said MODE: "DEMO" but set REAL_MONEY: true; this branch sets it to false.

## Authentication / database findings
- Current core/nplus-auth.js signs up with a password and calls nplus_phone_is_registered; login uses signInWithPassword. This does not match some older project notes referring to an OTP flow. Verify the live RPC exists and decide which auth flow the product should use.
- The checked-in supabase-schema.sql is an older/basic template (including a ₹1,000 wallet default); do not run it over the existing production database. Project notes state that live new-user wallet initialization was later changed to ₹108, but that must be confirmed on the live trigger before release.
- The premium foundation SQL changes RLS on wallet/ledger tables and adds admin RPCs. It must be reviewed against the actual live schema before running.
- A separate SQL guard draft removes a duplicate, weaker deposit INSERT policy and prevents ordinary users from editing their profiles.role.

## Critical security blocker
- Available nplus_wallet_change definition accepts a client-supplied delta, updates the user's own wallet, and writes a ledger row. It prevents negative balances but does not verify that a positive GAME_WIN delta reflects a valid server-side game result.
- WINGO, MotoRace, and Aviator currently ask the generic wallet RPC to credit positive wins. Some other game pages show stake deductions, but their server-authoritative win settlement was not verified.
- Do not claim tamper-resistant production status until bet state, round result, payout amount and idempotency are enforced server-side and all games are tested.

## Limits of this audit
- This review reads GitHub files and static metadata. It does not run a live browser, connect to the user's Supabase project, execute SQL, or test actual login/wallet/game flows.
- Branch fixes are isolated from main; no production database changes were made.
