# N+ PLAY Member Centre — Release & QA Guide

## Current release state

- Member Centre implementation is in draft PR [#5](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/5), targeting `release-candidate/security-rollout-2026-10-17`.
- Static CI passes: 308 checks covering 17 member/admin pages.
- Database CI passes in a disposable PostgreSQL 17 service: the migration applies and the server-side smoke tests pass.
- The connected production Supabase database has **not** received the member-centre migration. Keep the PR in draft until an isolated Supabase branch and desktop/mobile browser tests also pass.

## Included pages

| Area | Page |
|---|---|
| VIP tiers and summary | `vip.html` |
| Personal referral code, invite link and referral records | `referral.html` |
| Virtual gift redemption | `gift.html` |
| Virtual safe transfers (no interest) | `safe.html` |
| Once-daily attendance demo reward | `attendance.html` |
| Own-account wallet ledger statistics | `game-statistics.html` |
| Rebate information (intentionally non-claimable) | `rebate.html` |
| Member notices / information | `notification.html` |
| Beginner guide | `beginner-guide.html` |
| Demo risk and confidentiality disclosure | `about.html` |
| Gift-coupon status | `coupons.html` |
| Inactive jackpot screen | `jackpot.html` |
| Member support request and history | `support.html` |
| Admin VIP/referral reports and gift-code creation | `admin-vip.html` |
| Admin support queue | `admin-support.html` |

## Demo rules implemented

- Every account receives its own unique referral code.
- A referred account can attach one code only. Self-referrals are rejected.
- A referral reward is 20 **virtual demo points** and is applied once only when the invited account's virtual-credit request for 200 points or more is approved by N+ ADMIN.
- Gift codes are checked server-side and each account can redeem the same code only once.
- Virtual-safe transfers move points between two demo balances. They do not calculate interest.
- Attendance is limited to one claim per user per day and requires a previously admin-approved virtual-credit request.
- Admin RPCs check the server-side admin role. New feature tables have RLS enabled and direct browser-role table access revoked.
- The rebate page does not generate or claim credits until validated server-side game settlement exists.
- No real-money investment, deposit, cash withdrawal, interest or guaranteed-return promise is implemented in these member pages.

## Required isolated Supabase staging test

1. Confirm the Supabase organization and view the cost for creating a development branch. Obtain approval for any hourly charge before creating it.
2. Create a development branch from the existing NPLUS-PLAY project. The branch starts without copied production data; do not run tests against production.
3. Apply `sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql` to that branch only.
4. Confirm every new table has RLS enabled, anonymous execution is revoked on feature RPCs, and only authenticated or server-admin RPC execution is available as intended.
5. Register two test accounts. Confirm they receive different codes. Open the second account's invite URL and verify the signup code is prefilled.
6. Submit a virtual-credit request for 200 points from the invited account and approve it from N+ ADMIN. Confirm the referring member receives exactly 20 virtual points once; repeat the approval/update and confirm no second credit.
7. Test invalid, self and already-attached referral codes; gift-code redeem and duplicate rejection; virtual-safe IN/OUT and insufficient-balance cases; first and duplicate attendance claims; support ticket submission and admin status update.
8. Confirm a normal member cannot execute admin reports/support updates, directly read other users' private records, or modify feature tables.
9. Test sign-up/OTP, refresh, logout, PWA install/update, narrow-mobile navigation and desktop layout in a real browser.
10. Only after the above checks and review should the draft PR be marked ready. Keep the main/live site unchanged until the larger security rollout has separately cleared its release blockers.

## CI commands

The draft PR's GitHub Actions workflow automatically runs:

- `node tests/nplus-member-centre-qa.mjs`
- `psql -v ON_ERROR_STOP=1 -f tests/nplus-member-centre-prelude.sql`
- `psql -v ON_ERROR_STOP=1 -f sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql`
- `psql -v ON_ERROR_STOP=1 -f tests/nplus-member-centre-smoke.sql`

The database tests use a disposable CI-only PostgreSQL database with minimal Supabase-like auth functions; they do not use production credentials or production data.
