# N+ PLAY Member Centre — Release & QA Guide

## Current release state

- Member Centre implementation is in draft PR [#5](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/5), targeting `release-candidate/security-rollout-2026-10-17`.
- **Current branch CI passed** on 2026-10-19: 333 static checks across 17 required member/Admin pages; the updated migration applied and referral-tier/gift/safe/attendance/support smoke tests passed on a disposable PostgreSQL 17 service.
- Playwright Chromium rendered 36/36 available HTML pages and passed 12/12 mobile-critical viewport checks. [Passing workflow run](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39287117614).
- The connected production Supabase database has **not** received the member-centre migration. These tests do not prove production OTP, live Supabase RLS/authenticated RPC integration, concurrent claim behavior in a deployed database, or full real-device/PWA acceptance. Keep the PR in draft until the separate release blockers and authenticated integration review are cleared.

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
- A referred account can attach one code only. Self-referrals are rejected. The old 200-point qualification / 20-point automatic reward is removed.
- Invitation tiers match the supplied Daman screenshot: 1/3/10/30/50/70/100/200/500/1,000/5,000/10,000/20,000/50,000/100,000 invited accounts; each counted account must meet a 500-point qualification and the listed tier bonuses are 55/155/555/1,555/2,555/3,355/5,555/10,955/25,555/48,555/355,555/755,555/1,555,555/3,555,555/7,555,555 virtual demo points. These figures are reference-matched demo units, not rupees or cash.
- Gift codes are checked server-side and each account can redeem the same code only once.
- Virtual-safe transfers move points between two demo balances. They do not calculate interest.
- Attendance is limited to one claim per user per day and requires a previously admin-approved virtual-credit request.
- Admin RPCs check the server-side admin role. New feature tables have RLS enabled and direct browser-role table access revoked.
- The rebate page does not generate or claim credits until validated server-side game settlement exists.
- The invitation tiers now have a server-side progress RPC and exactly-once claim RPC. N+ ADMIN must verify trusted virtual-demo qualification of at least 500 points for each counted invite; a member can then claim each eligible tier once. Generic `deposit_requests` approval never triggers referral rewards. The RPC workflow is in draft and remains unapproved for release until disposable PostgreSQL and authenticated browser/RPC tests pass.
- No real-money investment, deposit, cash withdrawal, interest or guaranteed-return promise is implemented in these member pages.

## Required isolated Supabase staging test

1. Confirm the Supabase organization and view the cost for creating a development branch. Obtain approval for any hourly charge before creating it.
2. Create a development branch from the existing NPLUS-PLAY project. The branch starts without copied production data; do not run tests against production.
3. Apply `sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql` to that branch only.
4. Confirm every new table has RLS enabled, anonymous execution is revoked on feature RPCs, and only authenticated or server-admin RPC execution is available as intended.
5. Register two test accounts. Confirm they receive different codes. Open the second account's invite URL and verify the signup code is prefilled.
6. Confirm the tier table matches the screenshot values. Attach three invitees to one test inviter, verify each invite in N+ ADMIN with 500 virtual demo points, then claim tier 1 (55 points) and tier 3 (155 points). Confirm repeat claims fail without another ledger entry and tier 10 remains unavailable with only three qualified invitees. Also verify that generic `deposit_requests` approval does not award anything.
7. Test invalid, self and already-attached referral codes; gift-code redeem and duplicate rejection; virtual-safe IN/OUT and insufficient-balance cases; first and duplicate attendance claims; support ticket submission and admin status update.
8. Confirm a normal member cannot execute admin reports/support updates, directly read other users' private records, or modify feature tables.
9. Test sign-up/OTP, refresh, logout, PWA install/update, narrow-mobile navigation and desktop layout in a real browser. Confirm the referral dashboard/claim UI reads server status and never hardcodes a claimed result.
10. Only after the above checks and review should the draft PR be marked ready. Keep the main/live site unchanged until the larger security rollout has separately cleared its release blockers.

## CI commands

The draft PR's GitHub Actions workflow automatically runs:

- `node tests/nplus-member-centre-qa.mjs`
- `psql -v ON_ERROR_STOP=1 -f tests/nplus-member-centre-prelude.sql`
- `psql -v ON_ERROR_STOP=1 -f sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql`
- `psql -v ON_ERROR_STOP=1 -f tests/nplus-member-centre-smoke.sql`
- The `member-centre-browser-smoke` CI job installs Playwright/Chromium, serves this checkout locally, and runs `python qa/browser-smoke.py` at desktop and mobile sizes.

The database tests use a disposable CI-only PostgreSQL database with minimal Supabase-like auth functions; they do not use production credentials or production data. Browser smoke validates rendering/layout only and does not log in or mutate wallets.


## Browser smoke update — 2026-10-19

- The same credential-free Playwright Chromium smoke test now runs for this Member Centre branch.
- **PASS:** [push run 39275107359](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39275107359) and [PR run 39275122292](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39275122292): all 36/36 HTML pages in this branch rendered and all 12/12 mobile-critical viewports passed.
- This validates page rendering/layout only. It does not prove live OTP delivery, signed-in session behavior, Supabase RLS/RPC authorization, admin ticket actions, or the real referral approval flow. Those still require isolated Supabase staging with two test accounts.
