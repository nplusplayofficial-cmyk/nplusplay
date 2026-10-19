# N+ PLAY — Remaining Release Work Plan

Updated: 2026-10-19
Status: planning/audit only; no production mutation.

## Decision summary

**Do not merge or deploy yet.** The existing audit branch is still a draft. Latest source-guard workflow runs have been observed in the queued state, with no confirmed conclusion. A queued job is not a pass.

## Screenshot parity requirement — full Daman reference scope

The Daman screenshots the user supplied are the UI/feature reference. The requirement is **not referral-only**: every visible page, section, instruction, label, status, filter, and user action represented in those screenshots must be inventoried and implemented in N+ PLAY/N+ ADMIN where applicable. Keep the same user-facing flow and comparable layout, while using N+ branding and honest demo-only wording. Do not silently omit sections just because the referral flow is the first priority.

### Account and history
- Account/profile hub and navigation to the shown account sections.
- Game/play history and transaction history.
- Deposit/withdraw history screens as reference scope only; **do not modify deposit/withdraw pages or enable real-money transactions in this release**.
- Notifications/information messages and their seen/read states where shown.
- Language selection, including English and Hindi.
- Service centre/customer service, feedback, and support entry points.
- Beginner guide, install guide, agreements/terms, and other help/information pages shown.
- Gift centre and gift redemption/code entry flow.

### Promotion, referral, and agency/team
- Promotion/referral landing page and every referral instruction/rule visible in the screenshots.
- Per-account unique referral code, shareable referral link, and QR code where shown.
- Invitation rules and eligibility/qualification explanation.
- Subordinate/team list and team statistics, including the screenshot's filters and date/range controls.
- Commission/rebate sections and rebate levels/rates shown.
- Agency/team information and related navigation.
- Referral activity/statuses that distinguish invited, qualifying, approved, and rewarded users.
- Reward history and clear explanation of when a reward is and is not issued.

### VIP, virtual safe, rewards, and statistics
- Virtual safe page and its rules/instructions, but only for virtual/demo credits.
- VIP levels VIP1–VIP10, EXP/progress display, current level, next-level progress, and the shown level benefits.
- VIP level rewards, monthly rewards, VIP benefit/rate tables, and reward history shown in the references.
- Coupons/vouchers and their available/used/expired states where shown.
- Statistics pages with the screenshot's filters, totals, and date ranges.
- Attendance, gifts, and other reward pages represented in the screenshots.

### Referral demo business rules
- Each account has its own referral code/link; a user cannot refer themselves.
- The supplied Daman screenshot shows invite-count tiers 1/3/10/30/50/70/100/200/500/1,000/5,000/10,000/20,000/50,000/100,000, a 500-per-invite qualification amount, and the corresponding tier bonuses 55/155/555/1,555/2,555/3,355/5,555/10,955/25,555/48,555/355,555/755,555/1,555,555/3,555,555/7,555,555. In N+ these values are virtual demo points only, not cash. The former 200/20 rule was invented and is rejected.
- A referred user can be attributed to only one inviter; duplicate qualifying requests/replays must not issue another reward.
- The UI must explain the qualification, approval, reward status, and any reason a reward remains pending.
- Never present virtual/demo credits as cash or promise a real-money payout.

### Acceptance approach
- Create a screenshot-to-page checklist before marking parity complete; verify every screenshot and every visible interaction against the checklist.
- Match the reference's information architecture and instructions; use N+ styling, responsive desktop/mobile layout, accessible controls, and clear loading/empty/error/success states.
- Do not invent live activity, users, wins, balances, commissions, or rewards. Empty states must say when verified data is not available.
- Each action must have a working destination/behavior or a clearly disabled/unavailable state; no decorative dead buttons.
- Test account ownership, Admin separation, privacy, replay prevention, and virtual-ledger consistency for each relevant flow.
- Deposit/withdraw screens remain untouched and real-money functionality remains out of scope, even if shown in reference screenshots.

## Work completed in the audit branch

- Homepage recent demo activity now shows a truthful empty state instead of fabricated live activity.
- Homepage sample leaderboard is labelled illustrative, not real player activity.
- Admin page warns that browser localStorage is only display cache, not authority.
- Credential-free source guards check Admin server RPC use, fail-closed game status, demo-only homepage disclosure, Aviator RPC use, no client crash-point override, and selected SQL privilege contracts.
- Aviator scheduler/recovery architecture and tests are documented.
- No production SQL applied, no wallet balances changed, no deposit/withdraw pages changed, no merge/deploy.

## Free scheduler feasibility — decision

- Cloudflare Workers Free documents Cron Triggers, up to five per account, but only 10 ms CPU time per Cron invocation. That may support lightweight periodic maintenance, not a continuous 500 ms game loop. Do not treat it as a real-time Aviator engine.
- GitHub Actions scheduled workflows are not a persistent worker and can be delayed; scheduled workflows run from the default branch and the minimum documented schedule interval is five minutes. Do not use it to progress live rounds.
- Supabase Cron supports recurring database jobs from every second to yearly according to its docs, but actual feature availability and permissions must be checked in the existing project without upgrading or creating a paid branch. A direct call to the current user-authenticated `nplus_aviator_demo_current_round()` is not acceptable because it requires `auth.uid()` and has user-facing side effects.
- Therefore, the no-cost option is **not yet approved**. First inspect whether the existing Supabase project already exposes Cron and what role can run it. Do not enable extensions, create jobs, or change production SQL as part of this read-only check.
- If a safe scheduler is unavailable, keep Aviator explicitly as client-driven demo mode, with no claim of autonomous 24/7 rounds.

## Next actions in priority order

### P0 — build/test status
1. Obtain final result for both N+ Free Release GitHub Actions workflows on the latest audit commit. If still queued, inspect repository Actions status/permissions; do not claim pass.
2. Run `node qa/verify-project.js` and `node qa/free-release-guards.cjs` locally or in CI and verify the reported check count matches the actual executed checks.
3. Inspect all changes in PR #6 and ensure it remains draft.
4. Build a screenshot-by-screenshot checklist from all user-provided references and record each item as implemented, pending, blocked, or intentionally out of scope. Do not claim full parity until every screenshot is accounted for.

### P0 — backup and database security
5. Verify backup archive integrity and restore into a separate disposable PostgreSQL database. Never restore over production.
6. Test role boundaries for anonymous, normal authenticated user, and Admin in disposable PostgreSQL.
7. Verify the generic wallet mutation RPC cannot mint credits before applying the candidate revoke, and trace all legitimate callers first.
8. Verify phone enumeration behavior with the matching signup flow before applying its candidate revoke.
9. Confirm all bet/settlement RPCs check game status server-side, enforce idempotency, and write exactly one ledger entry under retries/concurrency.

### P1 — Aviator
10. Do not schedule the current authenticated polling RPC directly.
11. If an available scheduler is confirmed, design a separate trusted maintenance entry point with no caller-supplied crash point, multiplier, wallet delta, payout, or user ID; strict grants; idempotent settlement; heartbeat; fail-closed outage handling.
12. Test concurrent workers, duplicate invocation, worker restart, closed-browser recovery, late cash-out, auto-cashout, and one ledger write per settlement in disposable PostgreSQL.

### P1 — homepage activity
13. Keep the truthful empty state until a verified server-backed activity source exists.
14. Only show settled virtual-demo events, with privacy-safe display names and no phone/email/user IDs. Never fabricate wins or amounts.
15. Add tests for access control, limits, ordering, and privacy before connecting a public feed.

### P1 — user flows and screenshot parity
16. The screenshot-based tier table, Admin qualification RPC, user tier-progress RPC, exactly-once claim RPC, and corresponding draft UI are implemented on the feature branch. Keep merge/deploy blocked until disposable PostgreSQL tests pass for the 500-point threshold, tier 1/3 payouts, duplicate and concurrent claims, event expiry, Admin-only qualification, privacy/RLS, and proof that generic deposit requests never trigger bonuses.
17. Test gifts/transfers/support/VIP/attendance for ownership, role permissions, replay prevention and ledger consistency.
18. Implement and verify every applicable Account, history, notifications, service centre, help, language, gift, promotion/agency/team, rebate, virtual-safe, VIP, coupon, and statistics screen listed above.
19. Test desktop/mobile flows and auth recovery with a dedicated test account. Do not change production Auth settings until the candidate frontend flow passes.
20. Keep deposit/withdraw pages unchanged.

## Release gate

Merge/deploy remains blocked until all P0 items are evidenced, all relevant P1 tests pass, backup restore is proven, screenshot parity is checked item-by-item, and the release diff has been reviewed. Static checks alone are not sufficient. Keep the virtual-credit demo-only scope and preserve existing balances/ledger.
