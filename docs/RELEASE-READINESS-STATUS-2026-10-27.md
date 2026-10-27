# N+ PLAY + N+ ADMIN — release readiness snapshot (2026-10-27)

## Verified current production state

This snapshot was refreshed read-only against Supabase project `pcrxlqduygvzchzxsmdv` and GitHub PR #22 on 2026-10-27.

- PR #22 branch: `integration/release-candidate-2026-10-27`. At the start of this refresh its head was `218df8eaff199dfc647e1e863ce9024f8d8887a6`; Static QA #723 and Release Smoke #310 both succeeded on that exact head.
- Supabase migration history records the three protective migrations as versions `20261027172625`, `20261027172637`, and `20261027172656`, plus finite-number guards `20261027180120`, `20261027180134`, and `20261027180141`.
- Legacy-table privilege checks are already clean in production: all three tables have RLS enabled; `anon` has no direct SELECT/INSERT/UPDATE/DELETE; `authenticated` has SELECT-only on `manual_deposits` and no direct privileges on `user_bank_details` or `withdraw_requests`. Treat this ACL-hardening step as **deployed and verified**, not as an unapplied migration.
- The six game settings (5D, AVIATOR, K3, MOTO, TRX, WINGO) are all `false`.
- Read-only wallet integrity checks: 5 profiles, 5 wallets, 146 wallet-ledger rows; zero negative wallets, zero `balance_before + delta != balance_after` mismatches, and zero latest-ledger/current-wallet mismatches.
- The source/catalog security report classifies all 53 authenticated-callable SECURITY DEFINER functions and the one anon-callable aggregate function. The remaining security gate is not a generic source inventory gap: hosted role/authorization acceptance and owner risk decisions are still required.

## CI and local replay evidence

- Static QA #723: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40558234313
- Release Smoke #310: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40558234310
- The recorded full user-run reconstructed-baseline replay passed 40 captured migration-history rows, 29 distinct SQL-body fingerprints, final wallet/game/security invariants, and synthetic deposit/Admin/wallet/referral/withdrawal E2E with rollback. It ran at candidate HEAD `eb4377e09139cf826c6d102d7d8b6b39a41a99c4`, using the pre-split monolithic finite-numeric guard body and QA-only schema/ACL overlays. The local cron target was restored to `nplus_migration_replay_20261026`.
- Consequently that historical replay **does not prove** that the current three split finite-number migration files replay successfully as part of the full captured sequence. Current split-file runtime regressions pass in CI, but the latest full restore-lab replay of the exact split sequence is not yet evidenced in this repository.

## Release gates still open

1. **Exact current split replay:** run `qa/run-final-split-replay.ps1` on the user's existing Windows restore-lab, on the current PR head. Preserve any failed DB as evidence; never delete/overwrite an existing replay target. The wrapper restores the documented prior local cron target in `finally`.
2. **Hosted Auth/browser acceptance:** verify real signup/email OTP delivery, login/recovery/mobile return, Admin-versus-normal-user authorization, and synthetic wallet/deposit/withdrawal/referral journeys using a controlled inbox and synthetic accounts. Do not alter existing users.
3. **Referral product contract:** the earlier brief described a qualifying 200-demo-credit request and a one-time 20-demo-point reward; current code follows a 500-point/tier qualification and separate tier-claim model. Do not silently choose or award credits until the product owner records the intended contract.
4. **K3/5D/TRX payout contract:** valid selections, round/cutoff, result derivation, win conditions, exact virtual payout, rounding, tie/cancel/refund behavior, idempotency, and recovery need written approval and server-side tests. Keep all six game flags disabled.
5. **Legacy schema provenance:** authoritative historical DDL/policy/ACL lineage for `manual_deposits`, `user_bank_details`, and `withdraw_requests` is missing from the supplied backup/migration history. Provide a canonical source or explicitly accept that the original history cannot be proven; the reconstructed bootstrap is not historical proof.
6. **Free-plan Auth risk:** leaked-password protection remains disabled because it is not available on the current Free plan per the current project review. Record explicit owner risk acceptance with compensating controls, or make an owner-approved plan decision; no paid plan or Auth setting was changed.
7. **Final release/deployment:** after all gates above close, re-check the exact PR HEAD and CI, review/approve and merge PR #22, then verify the deployed Pages commit and live N+ PLAY/N+ ADMIN journeys. Candidate HEAD is not declared deployed while PR #22 remains draft/unmerged.

## Non-negotiable safety invariants

- Demo/virtual credits only; no real-money claims or cash payouts.
- Preserve existing profiles, wallets, and ledger rows.
- Do not change Auth settings, paid plan, scheduler/cron, or production grants unless the specific reviewed action is authorized.
- Keep all six game flags disabled until the rules and hosted settlement gates pass.
- Do not mark the release production-ready while any gate above remains open.
