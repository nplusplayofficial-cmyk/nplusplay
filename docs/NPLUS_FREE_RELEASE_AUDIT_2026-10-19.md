# N+ PLAY + N+ ADMIN — Free Release Audit

Updated: 2026-10-19

## Scope and non-negotiable safety rules
- Demo/virtual credits only. Do not implement cash deposits, cash payouts, or real-money wagering.
- Do not modify deposit or withdrawal pages as part of this audit.
- Do not reset, overwrite, or silently adjust existing wallet balances or ledger rows.
- Do not run candidate migrations against the connected production database.
- Do not merge or deploy until the release gates below are evidenced.
- Use GitHub Actions and disposable/local PostgreSQL for no-cost checks. A paid Supabase branch is out of scope unless the owner later approves its exact cost.

## Verified candidate status
- PR #3 is a draft security/game-settlement candidate. Its recorded CI covers static QA, disposable PostgreSQL suites, and credential-free browser rendering.
- PR #5 is a draft Member Centre/referral candidate on top of the security branch. Its recorded CI covers static QA, disposable PostgreSQL tests, and credential-free browser rendering.
- These CI checks do not prove authenticated browser flows against Supabase, OTP delivery, or production readiness.
- The live database was previously audited read-only. Existing wallets and ledger must be preserved.

## Priority 0 — do not release until resolved
- [ ] Validate the backup archive and restore it into a separate disposable/local PostgreSQL database; capture evidence. Never restore over production.
- [ ] Verify all active game pages call only server-authoritative settlement RPCs; no browser-controlled win credit, crash point, payout, or client-side wallet fallback.
- [ ] Verify legacy nplus_wallet_change cannot be used by authenticated clients to mint positive credits. Do this only after every legitimate caller has been migrated and tested; never run the post-rollout guard early.
- [ ] Revoke anonymous phone-registration enumeration only after the matching signup flow is deployed and duplicate-phone behavior is tested.
- [ ] Review NULL-safe Admin role checks and every SECURITY DEFINER RPC; prove non-admin/anonymous denial in disposable PostgreSQL tests.
- [ ] Verify server game status is enforced inside every bet RPC, not just hidden/disabled in the UI.
- [ ] Do not re-enable K3, 5D, or TRX until payout rules are documented and server settlement tests exist.
- [ ] Confirm email confirmation/OTP and password recovery using a test account before changing production Auth settings.

## Priority 1 — game and wallet integrity
- [ ] Aviator: test round creation, one authoritative crash result per round, server-time cashout, auto-cashout, late requests, reconnect/reload, simultaneous requests, and recovery when the browser is closed.
- [ ] WINGO and MotoRace: test atomic stake debit + bet insert, server-side result, one-time settlement, insufficient balance, duplicate requests, concurrent bets, and reload recovery.
- [ ] All games: verify wallet balance equals the ledger-derived balance under concurrent actions; retries cannot debit or credit twice.
- [ ] Keep game status fail-closed if settings cannot be read.
- [ ] Add a persistent scheduler/recovery mechanism only where the hosting platform supports it. Static GitHub Pages cannot itself run a permanent background game worker.
- [ ] Keep outcomes fair and auditable. Admin test controls must never secretly manipulate outcomes for active users.

## Priority 2 — N+ ADMIN and Member Centre
- [ ] Verify Admin routes and RPCs independently enforce the server-side Admin role; hiding links is not authorization.
- [ ] Verify high-bet reports are based on stored settled demo bets and are scoped correctly.
- [ ] Replace any client-only Admin game/outcome state with server-persisted, role-guarded state.
- [ ] Verify referral code uniqueness, one-time 20 virtual-point reward only after an eligible 200-point virtual-credit request is approved, and replay protection.
- [ ] Verify gift, safe transfer, attendance, support, and VIP actions enforce ownership and permissions in SQL/RPCs.
- [ ] Keep rebate non-claimable until authoritative settlement supports verified statistics.
- [ ] Keep jackpot inactive/zero unless a real, server-backed demo pool and its rules exist.

## Priority 3 — homepage activity and cross-page sync
- [ ] Recent bets/wins must be sourced from real server records; never fabricate names, wins, or activity.
- [ ] Clearly label all balances, bets, wins, and jackpot values as virtual/demo points.
- [ ] Do not expose phone numbers, emails, or private user identifiers in public activity feeds.
- [ ] Ensure wallet display refreshes after server-confirmed transactions and after tab focus/reconnect; UI events and localStorage are hints, not financial truth.
- [ ] Show a truthful empty state when there is no verified recent activity or jackpot pool.

## No-cost verification sequence
1. Run both existing GitHub Actions QA workflows on the final candidate head.
2. Run SQL migrations and permission tests only against disposable PostgreSQL.
3. Run static checks for direct positive GAME_WIN calls, local wallet fallbacks, and privileged localStorage controls.
4. Run credential-free desktop/mobile browser smoke.
5. Perform authenticated Supabase integration tests only if a genuinely free isolated environment is available; otherwise record them as blocked, not passed.
6. Review the final diff and verify no deposit/withdraw page changes and no production data mutations.
7. Keep PRs draft until all release gates are evidenced. Do not merge/deploy as a shortcut.

## Current release decision
**NOT READY TO MERGE/DEPLOY.** Remaining live RPC risks, unapplied candidate migrations, restore test, authenticated integration, and runtime game tests are blockers. Passing static/disposable tests alone is insufficient.