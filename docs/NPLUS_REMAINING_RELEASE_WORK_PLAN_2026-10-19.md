# N+ PLAY — Remaining Release Work Plan

Updated: 2026-10-19
Status: planning/audit only; no production mutation.

## Decision summary

**Do not merge or deploy yet.** The existing audit branch is still a draft. Latest source-guard workflow runs have been observed in the queued state, with no confirmed conclusion. A queued job is not a pass.

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

### P0 — backup and database security
4. Verify backup archive integrity and restore into a separate disposable PostgreSQL database. Never restore over production.
5. Test role boundaries for anonymous, normal authenticated user, and Admin in disposable PostgreSQL.
6. Verify the generic wallet mutation RPC cannot mint credits before applying the candidate revoke, and trace all legitimate callers first.
7. Verify phone enumeration behavior with the matching signup flow before applying its candidate revoke.
8. Confirm all bet/settlement RPCs check game status server-side, enforce idempotency, and write exactly one ledger entry under retries/concurrency.

### P1 — Aviator
9. Do not schedule the current authenticated polling RPC directly.
10. If an available scheduler is confirmed, design a separate trusted maintenance entry point with no caller-supplied crash point, multiplier, wallet delta, payout, or user ID; strict grants; idempotent settlement; heartbeat; fail-closed outage handling.
11. Test concurrent workers, duplicate invocation, worker restart, closed-browser recovery, late cash-out, auto-cashout, and one ledger write per settlement in disposable PostgreSQL.

### P1 — homepage activity
12. Keep the truthful empty state until a verified server-backed activity source exists.
13. Only show settled virtual-demo events, with privacy-safe display names and no phone/email/user IDs. Never fabricate wins or amounts.
14. Add tests for access control, limits, ordering, and privacy before connecting a public feed.

### P2 — user flows
15. Test referrals: unique referral codes, eligible 200 virtual-credit event, one-time 20 virtual-point reward, replay protection, no self-referral, and server-side approval.
16. Test gifts/transfers/support/VIP/attendance for ownership, role permissions, replay prevention and ledger consistency.
17. Test desktop/mobile flows and auth recovery with a dedicated test account. Do not change production Auth settings until the candidate frontend flow passes.

## Release gate

Merge/deploy remains blocked until all P0 items are evidenced, all relevant P1 tests pass, backup restore is proven, and the release diff has been reviewed. Static checks alone are not sufficient. Keep the virtual-credit demo-only scope and preserve existing balances/ledger.
