# N+ PLAY + N+ ADMIN — release readiness status (2026-10-28)

## Current state

- **Production server migrations applied and verified** for K3/5D/TRX settlement and the chosen 200/20 referral contract.
- **PR #22 merged:** https://github.com/nplusplayofficial-cmyk/nplusplay/pull/22
- **Merge commit:** `09c432a6fc4256898772084aa78f7ec671b3e5d4`.
- **GitHub Pages deployment #456 PASS** for the merge commit: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40744468877.
- **Post-merge Static QA #774 PASS:** https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40744469617. Pre-merge exact-head Static QA #773 and Release Smoke #360 also passed.
- **All six game flags remained disabled** at the latest live read-only check; do not describe the games as playable until they are enabled through the guarded Admin interface and verified.
- Hosted signup/email OTP/password recovery/mobile return has not been run with a controlled inbox. Owner authorized proceeding with this limitation recorded; it is not a test PASS.

## Live migration records (verified read-only)

Supabase project `pcrxlqduygvzchzxsmdv`:
- `20261027172625` — referral qualified state.
- `20261027172637` — legacy table direct-grant hardening.
- `20261027172656` — WINGO Admin overload fix.
- `20261027180120`, `20261027180134`, `20261027180141` — finite numeric guards.
- `20261028134905` — `server_authoritative_k3_5d_trx_demo`.
- `20261028134917` — `demo_referral_200_20_rule`.
- `20261028183128` — `enable_all_demo_game_flags_authorized_release`; all-six activation plus private audit row.

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

- All six production flags are now `true`: 5D, AVIATOR, K3, MOTO, TRX, WINGO. The owner-approved activation migration checked all required server components and the AVIATOR scheduler/worker, and aborted unless all flags were initially OFF and wallet/ledger invariants passed.
- New `nplus_demo_lottery_bets` and `nplus_demo_lottery_rounds` tables have RLS enabled and no direct browser-role SELECT/INSERT/UPDATE/DELETE grants.
- `nplus_demo_lottery_snapshot` and `nplus_demo_lottery_place_bet` have EXECUTE only for authenticated; internal lottery helper functions are not executable by anon/authenticated; Admin game-status RPC remains authenticated-only.
- Referral approval trigger is installed on `deposit_requests`; referral table remained empty at verification, so no legacy referral points were back-credited.
- Wallet integrity: 5 profiles, 5 wallets, 146 wallet-ledger rows, zero negative wallets, zero ledger arithmetic mismatches, and zero current-wallet/latest-ledger mismatches.
- Legacy tables `manual_deposits`, `user_bank_details`, and `withdraw_requests` retain RLS. `anon` has no direct table privileges. `authenticated` has SELECT only on `manual_deposits` and no direct privileges on the other two.
- Private release audit row records the old all-OFF state, new all-ON state, owner authorization basis, deployment commit and no-change guarantee for existing rows. The operation cleared `updated_by` rather than attributing it to an authenticated Admin.
- No existing user, wallet, ledger, deposit or referral rows were changed. Migration definitions and flags are verified; hosted user journeys remain unverified.
- AVIATOR worker health after activation: no last error and zero consecutive failures.
- Post-activation wallet integrity: 5 profiles, 5 wallets, 146 ledger rows; zero negative balances, arithmetic mismatches or latest-wallet mismatches.

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

## Final release/deployment status — 2026-10-28

1. PR #22 merged as `09c432a6fc4256898772084aa78f7ec671b3e5d4`.
2. GitHub Pages deployment #456 succeeded for that merge commit. Latest status-doc refresh is building/deploying from main.
3. Owner-approved activation migration `20261028183128_enable_all_demo_game_flags_authorized_release` passed preflight, recorded an audit row and enabled all six flags in one transaction.
4. Final read-only verification confirms all six flags true, required server functions present, AVIATOR scheduler active/worker healthy, lottery tables RLS-enabled with no browser-role direct grants, and 10/10 payout multiplier cases passing.
5. Wallet/ledger integrity is unchanged: 5 profiles, 5 wallets, 146 ledger entries; zero negative balances or ledger/latest-balance mismatches.
6. Hosted signup/email OTP/password recovery/mobile return remains unverified; this is disclosed, not claimed as passed.

Safety invariants: virtual demo points only; no cash payouts; preserve existing user/wallet/ledger data; no automatic back-credit; never call hosted Auth or deployment tests passed unless actually run.
