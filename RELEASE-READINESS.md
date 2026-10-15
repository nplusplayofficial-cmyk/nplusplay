# N+ PLAY — Release readiness (2026-10-15)

## Branch-only changes included
- Add the missing, correctly named admin-users.html page and remove the misspelled duplicate admin-users.htlm.
- Add the icon at assets/nplus-icon.svg, match manifest/service-worker paths, and bump the service-worker cache version.
- Add a pending virtual-credit deposit request page; route the deposit UI only to demo mode.
- Disable REAL_MONEY in legacy configuration.
- Fix forgot-password.html static login links to auth.html.
- Add reviewed SQL drafts for admin user tools and role/deposit safeguards.
- Expand qa/verify-project.js to check inline JS syntax, required files, manifest/service-worker assets, and static local references.

## Not release-ready until these gates pass
1. Take and verify a database backup before running either SQL migration.
2. Reconcile SQL drafts against live tables, policies, triggers, and existing RPC bodies; execute only after review.
3. Verify sign-up works end-to-end. Current repo code uses password auth and calls nplus_phone_is_registered; confirm the RPC exists and that the profile trigger saves email, phone, role, and the intended ₹108 initial wallet.
4. Implement server-authoritative bets, round outcomes and idempotent payouts. Do not rely on client-supplied positive GAME_WIN deltas.
5. Test user isolation for wallet/ledger, admin role checks, deposit approve/reject (₹108 unchanged when pending/rejected; only approved request credits), and every game settlement.
6. Run node qa/verify-project.js, then test GitHub Pages runtime on desktop/mobile and inspect the service worker in DevTools.

This branch is not merged into main. Static GitHub file reads were used; live Supabase execution and browser runtime tests have not been performed.
