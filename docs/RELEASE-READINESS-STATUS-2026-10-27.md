# N+ PLAY + N+ ADMIN — release readiness status (2026-10-28)

## Current state

- **Production server migrations applied and verified** for K3/5D/TRX settlement and the chosen 200/20 referral contract.
- **Exact candidate CI at the application/SQL code head passed:** Static QA #768 — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40700269858; Release Smoke #355 — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40700269916. Browser-smoke passed in Static QA #768. Later commits in this branch currently update release records/filenames only; require CI on the final exact PR head before merge.
- **PR #22** — OPEN / DRAFT / unmerged. Candidate is not yet verified on GitHub Pages.
- **All six game flags were still disabled at the post-migration read-only check.** Do not describe the games as active until their flags are enabled after deploy and verified.
- Hosted signup/email OTP/password recovery/mobile return has not been run with a controlled inbox. Per owner instruction, proceed with this limitation clearly recorded; it is not a test PASS.

## Live migration records (verified read-only)

Supabase project `pcrxlqduygvzchzxsmdv`:
- `20261027172625` — referral qualified state.
- `20261027172637` — legacy table direct-grant hardening.
- `20261027172656` — WINGO Admin overload fix.
- `20261027180120`, `20261027180134`, `20261027180141` — finite numeric guards.
- `20261028134905` — `server_authoritative_k3_5d_trx_demo`.
- `20261028134917` — `demo_referral_200_20_rule`.

### K3 / 5D / TRX demo settlement

The current candidate contains the matching source files:
- `supabase/migrations/20261028134905_server_authoritative_k3_5d_trx_demo.sql`
- `qa/test-demo-lottery-settlement.sql`

The production migration installs private RLS-enabled lottery round/bet tables with no direct `anon`/`authenticated` privileges; server-owned result generation, snapshot, bet-placement and settlement RPCs; finite stake limits; round cutoff; request-token idempotency; and one-time wallet/ledger settlements. The guarded `nplus_set_game_status` RPC refuses to enable K3/5D/TRX unless those server functions exist. The UI pages read server status/results and place bets using authenticated RPCs only.

Owner-approved initial rules are recorded in [OWNER-AUTHORIZED-DEMO-GAME-RULES-2026-10-28.md](OWNER-AUTHORIZED-DEMO-GAME-RULES-2026-10-28.md). Unsupported selections are disabled: K3 only Big/Small and Even/Odd; 5D per-position exact digit/size/parity (sum disabled); TRX color/last digit/size. All payouts are gross virtual demo points and not cash.

### Referral 200/20 contract

The current candidate contains `supabase/migrations/20261028134917_demo_referral_200_20_rule.sql` and `qa/test-demo-referral-200-20.sql`.

On a new transition to approved, a `DEMO_CREDIT` deposit request of at least 200 points for a referred user marks the referral rewarded and atomically writes exactly one 20-point inviter wallet credit and matching ledger row. Pending/rejected requests, other payment methods, self-referrals and repeats don't qualify. The migration does not back-credit existing referrals. Old tier-claim/manual qualification paths no longer issue points; member and Admin referral pages now use the 200/20 model.

### Post-apply security/data verification

- All six production flags were `false` at the recorded post-apply read: 5D, AVIATOR, K3, MOTO, TRX, WINGO.
- New `nplus_demo_lottery_bets` and `nplus_demo_lottery_rounds` tables have RLS enabled and no direct browser-role SELECT/INSERT/UPDATE/DELETE grants.
- `nplus_demo_lottery_snapshot` and `nplus_demo_lottery_place_bet` have EXECUTE only for authenticated; internal lottery helper functions are not executable by anon/authenticated; Admin game-status RPC remains authenticated-only.
- Referral approval trigger is installed on `deposit_requests`; referral table remained empty at verification, so no legacy referral points were back-credited.
- Wallet integrity: 5 profiles, 5 wallets, 146 wallet-ledger rows, zero negative wallets, zero ledger arithmetic mismatches, and zero current-wallet/latest-ledger mismatches.
- Legacy tables `manual_deposits`, `user_bank_details`, and `withdraw_requests` retain RLS. `anon` has no direct table privileges. `authenticated` has SELECT only on `manual_deposits` and no direct privileges on the other two.
- These postchecks did not update existing user, wallet, or ledger rows. Migration definitions and flags are verified; hosted user journeys remain unverified.

## Exact split-migration reconstructed-baseline replay — PASS

User ran `qa/run-final-split-replay.ps1` on 2026-10-28:
- Existing local restore-lab `supabase_db_nplusplay-restore-lab-v2`.
- Verified restore source `nplus_restore_acceptance_20261027`.
- Fresh disposable target `nplus_migration_replay_20261031`.
- All 40 captured production-history bodies replayed in order; all 29 unique SQL fingerprints matched.
- Candidate protection migrations plus the current split finite-number guards passed on the reconstructed clone; QA-only wallet/ledger and request ACL overlays and final invariants passed.
- Synthetic deposit/Admin/wallet/referral/withdrawal E2E passed and ended in `ROLLBACK`.
- Local cron database target restored and verified as `nplus_migration_replay_20261026`.

**Scope limitation:** the three legacy tables were created by schema-only reconstruction plus QA-only ACL overlays. This does not prove original historic DDL/policy/ACL provenance. See [replay result](RECONSTRUCTED-BASELINE-REPLAY-RESULT-2026-10-27.md).

## Owner-approved limitations

- **Historic schema provenance:** owner accepts that original legacy-table DDL/policy/ACL history cannot be proven from available evidence for this demo-only release. This is not canonical history proof.
- **Free-plan leaked-password protection:** owner accepts the reviewed plan limitation with compensating controls; no paid upgrade or Auth-setting change was made.
- **Hosted Auth/browser acceptance:** owner authorizes proceeding while this remains unverified. No one should claim OTP/signup/recovery/browser acceptance passed. Run it with a controlled inbox when available.

## Final release/deployment steps

1. Verify the latest CI on the **exact current PR #22 head** after documentation/filename updates.
2. Mark PR #22 ready and merge it once exact-head CI is green.
3. Verify GitHub Pages build/deployment for the merge commit and fetch the live pages.
4. Read-only check the expected live migration records, game flags, trigger/execute grants, and wallet/ledger invariants after deployment.
5. **Enable all six game flags** only after the deployed site/server RPCs pass smoke. Enable through the authenticated Admin game-status path or an explicitly audited privileged operations step; do not impersonate an Admin JWT. Verify all six flags are true and the Admin UI reflects that state.
6. Share the site as live only after the actual Pages deployment and game flags are verified. Keep the hosted Auth acceptance limitation disclosed.

Safety invariants: virtual demo points only; no cash payouts; preserve existing user/wallet/ledger data; no automatic back-credit; never call hosted Auth or deployment tests passed unless actually run.
