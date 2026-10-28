# N+ PLAY + N+ ADMIN — Release owner decisions and verified gates (2026-10-28)

## Owner decisions recorded

The user explicitly instructed: approve the remaining decisions and complete the N+ PLAY + N+ ADMIN demo-only release. The decisions below document the chosen contract and the remaining facts that are not falsely represented as tested.

### 1. Referral qualification and reward — APPROVED: 200/20

- One referred account must have an **approved** server-recorded `DEMO_CREDIT` request of at least 200 virtual points.
- Inviter receives exactly one 20 virtual demo-point reward.
- Pending/rejected requests, other payment methods, self-referrals and duplicate approval updates do not qualify.
- No existing referral is back-credited. Legacy tier claims and manual qualification no longer issue rewards.
- Candidate regression covers the trigger, wallet and ledger entries, no back-credit, dashboard summaries, and rollback.
- Production migration `20261028134917_demo_referral_200_20_rule` is applied and recorded. The trigger is installed on `public.deposit_requests`.

### 2. K3 / 5D / TRX rules — APPROVED, SERVER-IMPLEMENTED

Written rules are recorded in [owner-authorized demo game rules](OWNER-AUTHORIZED-DEMO-GAME-RULES-2026-10-28.md).

- K3: three server-generated dice; Big/Small and Even/Odd only; 2.0× gross on wins.
- 5D: five server-generated digits A–E; per-position exact digit 10.0×, size/parity 2.0×; sum betting disabled until its own payout table exists.
- TRX WINGO: five server-generated digits; last digit determines color/size; Green/Red 2.5×, Violet 5.0×, exact last digit 10.0×, size 2.0× gross. It is explicitly a demo result, not live blockchain data.
- All three use server-owned outcomes, five-second cutoff, finite stake bounds, round-scoped request idempotency, atomic wallet/ledger changes and one-time settlement.
- Production migration `20261028134905_server_authoritative_k3_5d_trx_demo` is applied and recorded. Both lottery tables have RLS enabled and no direct `anon`/`authenticated` privileges. The browser uses authenticated RPCs only.
- These payout rules use virtual demo points only; they do not imply cash or redeemable value.

### 3. Historical legacy-table schema provenance — OWNER ACCEPTS LIMITATION

The original historical DDL/policy/ACL lineage for `manual_deposits`, `user_bank_details`, and `withdraw_requests` cannot be proven from the supplied 2026-10-15 backup and recorded migration history. Owner accepts proceeding with a documented reconstructed-baseline limitation for a virtual-demo-only release. Do not describe this as canonical historical replay.

### 4. Leaked-password protection on Supabase Free — OWNER ACCEPTS LIMITATION

The current Free plan does not provide leaked-password protection. Owner accepts proceeding with the documented compensating controls for a virtual-demo-only release. The setting is not enabled; no paid upgrade or Auth setting change has been made.

### 5. Hosted Auth/browser acceptance — OWNER ACCEPTS UNVERIFIED STATUS FOR THIS RELEASE PASS

Owner authorizes proceeding after local/CI/server-side checks despite the lack of a controlled test inbox. The following have **not** been verified in a real hosted browser in this work: signup/email OTP delivery, password recovery/mobile return, and the full hosted normal-user/Admin journey. This decision records acceptance to proceed; it is not a claim that those tests passed. Never fabricate a test result or modify an existing account. Run controlled hosted acceptance when an inbox/account is available.

### 6. Full reconstructed-baseline replay — PASS

User ran `qa/run-final-split-replay.ps1` on 2026-10-28 using candidate code HEAD `bb3e2c708d630ba629ea3d99ac4a229961b58f57` (exact code HEAD shown in the successful replay run).

- Existing local container: `supabase_db_nplusplay-restore-lab-v2`.
- Restore source: `nplus_restore_acceptance_20261027`.
- Disposable replay DB: `nplus_migration_replay_20261031`.
- All 40 captured production-history bodies replayed in order; all 29 unique SQL fingerprints matched.
- Current split finite-number guards, candidate protection migrations, QA-only ACL overlays, final invariants and synthetic wallet/Admin/referral/deposit/withdrawal E2E passed; synthetic transaction rolled back.
- Local `cron.database_name` restored and verified as `nplus_migration_replay_20261026`.
- Scope limitation: three legacy relations were created by a schema-only reconstruction plus QA-only ACL overlays. This does not prove original historical DDL/policy/ACL provenance.
- See [replay report](RECONSTRUCTED-BASELINE-REPLAY-RESULT-2026-10-27.md) and [release readiness report](RELEASE-READINESS-STATUS-2026-10-27.md).

## Current production and candidate evidence (2026-10-28)

- Production migration records now include `20261028134905_server_authoritative_k3_5d_trx_demo` and `20261028134917_demo_referral_200_20_rule`, after earlier recorded protections/finite-number guards `20261027172625`, `20261027172637`, `20261027172656`, `20261027180120`, `20261027180134`, `20261027180141`.
- Static QA #768 PASS: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40700269858
- Release Smoke #355 PASS: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40700269916
- Latest live read-only wallet invariant check: 5 profiles, 5 wallets, 146 ledger rows, zero negative balances, zero ledger arithmetic mismatch, zero wallet/latest-ledger mismatch.
- Referral migration did not credit any historical referrals: live referral table had zero rows at post-apply check.
- All six game flags are now enabled by audited activation migration `20261028183128_enable_all_demo_game_flags_authorized_release`, and post-activation read-only verification confirms all six are true.
- PR #22 is merged; Pages deployment #456 succeeded for merge commit `09c432a6fc4256898772084aa78f7ec671b3e5d4`. The final status-document refresh is redeploying from main.
- Audit row #1 records all-OFF -> all-ON, user authorization, deployment commit and that no existing user/wallet/ledger/deposit/referral rows were modified.

## Release path — updated 2026-10-28

- PR #22 is merged as `09c432a6fc4256898772084aa78f7ec671b3e5d4`.
- Exact candidate CI passed (Static QA #773; Release Smoke #360).
- GitHub Pages deployment #456 passed for the merge commit: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40744468877
- Post-merge Static QA #774 passed: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40744469617
- Production migrations `20261028134905` (server-authoritative K3/5D/TRX settlement) and `20261028134917` (200/20 referral) were applied and verified.
- Latest live read-only state after activation migration `20261028183128`: all six game flags are ON; wallet/ledger integrity is clean; 10/10 payout-multiplier cases pass; AVIATOR worker has no last error and zero consecutive failures.
- The private `nplus_release_operations_audit` records the explicit user approval, deployment commit, previous all-OFF state, new all-ON state, and that no existing user/wallet/ledger/deposit/referral rows were changed.
- **Game activation complete:** all six flags were enabled by the owner-approved one-time guarded migration with preflight checks and a private audit record; no Admin JWT was impersonated.
- Hosted signup/email OTP/login/password recovery/mobile return has not been tested with a controlled inbox and remains unverified. Owner accepted proceeding with that limitation recorded; do not claim this test passed.

## Non-negotiable constraints

- Virtual demo points only. No real-money deposit, wagering, cash payouts or withdrawals.
- Preserve existing users, wallet balances and ledger rows; no automatic back-credit.
- No blanket SECURITY DEFINER EXECUTE revokes or blanket RLS policies.
- Do not bypass the authenticated game-status interface or impersonate an Admin JWT.
- Keep launch/deployment reporting truthful about any hosted Auth/browser tests not performed.
