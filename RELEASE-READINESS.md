# N+ PLAY — Release readiness (2026-10-15)

## Branch-only changes included
- Add the missing, correctly named admin-users.html page and remove the misspelled duplicate admin-users.htlm.
- Add assets/nplus-icon.svg, align PWA paths, and bump the service-worker cache version.
- Add a pending virtual-credit deposit request page; route deposit UI only to demo mode.
- Disable REAL_MONEY in legacy configuration.
- Fix forgot-password.html links to auth.html.
- Restore email-OTP signup while retaining password login.
- Add SQL drafts, a QA script, and a GitHub Actions static-QA workflow.

## Not release-ready until these gates pass
1. Take and verify a database backup before running either SQL migration.
2. Reconcile SQL drafts against live tables, policies, triggers, and existing RPC bodies; execute only after review.
3. Set the Supabase Confirm signup email template to use {{ .Token }}; confirm SMTP/email delivery, verify nplus_phone_is_registered exists, and test a new signup/OTP flow end-to-end.
4. Confirm the profile trigger stores email/phone and creates a new virtual wallet with ₹108; test existing-user login with email + mobile + password.
5. Implement server-authoritative bets, round outcomes and idempotent payouts. Do not rely on client-supplied positive GAME_WIN deltas.
6. Test user isolation for wallet/ledger, admin role checks, deposit approve/reject (pending/rejected requests leave the balance unchanged; only admin approval credits), and every game settlement.
7. Run node qa/verify-project.js, then test GitHub Pages runtime on desktop/mobile and inspect the service worker in DevTools.

This branch is not merged into main. Static CI checks do not test live Supabase or browser runtime.
