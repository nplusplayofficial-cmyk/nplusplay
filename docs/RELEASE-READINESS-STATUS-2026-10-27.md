# N+ PLAY + N+ ADMIN — release readiness snapshot (2026-10-28)

## Status

**The current candidate is CI-green, but the full game launch is not certified.** This snapshot combines the latest available exact-head CI and production read-only checks. It does not treat a reconstructed replay as canonical schema history, and it does not claim hosted acceptance without a real test inbox.

## Current candidate and CI

- PR #22: [open draft PR](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/22)
- Branch: `integration/release-candidate-2026-10-27`
- Candidate code HEAD checked: `93c1e07940076dc44e740b083f69d8fc16e53c7b`
- Static QA #724: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40560060351
- Release Smoke #311: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40560060384
- Browser smoke job on that head passed desktop/mobile rendering.

PR #22 remains OPEN / DRAFT / unmerged. The latest candidate is not declared deployed to GitHub Pages.

## Production read-only postconditions

Refreshed against Supabase project `pcrxlqduygvzchzxsmdv` on 2026-10-28:

- Recorded migration versions: `20261027172625` (referral qualified-state constraint), `20261027172637` (legacy table ACL hardening), `20261027172656` (WINGO Admin overload defaults), `20261027180120`, `20261027180134`, and `20261027180141` (split finite-number guards).
- All 10 target numeric-sensitive RPCs have NaN/Infinity guards per the verified rollout evidence.
- All six game flags (5D, AVIATOR, K3, MOTO, TRX, WINGO) are `false`.
- `manual_deposits`, `user_bank_details`, and `withdraw_requests` have RLS enabled. `anon` has no direct SELECT/INSERT/UPDATE/DELETE privileges on those tables. `authenticated` has SELECT only on `manual_deposits` and no direct privileges on the other two. Legacy-table ACL hardening is already live and verified.
- Wallet integrity: 5 profiles, 5 wallets, 146 wallet-ledger rows; zero negative wallets, zero arithmetic mismatches (`balance_before + delta = balance_after`), and zero current-wallet/latest-ledger mismatches.
- This read-only verification did not change user/wallet/ledger rows, Auth settings, paid plan, scheduler/cron settings, or game flags.
- Source/catalog review documents the 53 authenticated-callable SECURITY DEFINER functions and the one intentionally public aggregate activity RPC; generic Advisor warnings must not be addressed with a blanket revoke.

## Local replay evidence and limitation

The recorded user-run full reconstructed-baseline replay passed 40 captured migration-history rows, 29 distinct SQL-body fingerprints, final invariants and synthetic wallet/Admin/referral/withdrawal E2E with transaction rollback on HEAD `eb4377e09139cf826c6d102d7d8b6b39a41a99c4`. The local cron target was restored to `nplus_migration_replay_20261026`.

That historical replay used the pre-split monolithic finite-numeric guard body and QA-only schema/ACL overlays. It **does not certify** that the current three split migration files replay successfully as part of the full captured sequence. Their isolated PostgreSQL runtime tests pass in the latest CI, but the exact split-file full replay on the user's existing Windows restore-lab still needs evidence.

Use the guarded wrapper from the repo root after pulling the latest branch:
```powershell
git fetch origin
git switch integration/release-candidate-2026-10-27
git pull --ff-only origin integration/release-candidate-2026-10-27
git rev-parse HEAD
.\qa\run-final-split-replay.ps1
```
The wrapper is local-only, refuses remote Docker endpoints and existing replay targets, and restores the documented local cron target in `finally`. Preserve any failed target for diagnosis; do not delete or overwrite it.

## Gates still open before full game launch

1. **Exact split replay:** run the wrapper on the existing Windows restore-lab and record its report. This tool cannot access that user's Docker environment directly.
2. **Hosted account acceptance:** test real signup/email OTP, login, password recovery and mobile return with a controlled inbox and synthetic accounts; then verify Admin-vs-normal-user permissions and wallet/deposit/withdrawal/referral journeys. Do not alter existing accounts.
3. **Referral contract:** earlier explicit brief said a referred account reaching 200 approved demo credits earns its inviter 20 demo points once. Current code/UI implements 500-point qualification and separately claimed screenshot-based tiers. This needs an owner decision before reward behavior is changed or credits are issued.
4. **K3/5D/TRX rules:** no written, approved server-authoritative result/payout/rounding/cancel/refund/recovery contract exists. Do not invent payout multipliers; all six game flags must remain disabled until the rules and server-settlement tests are approved.
5. **Legacy schema provenance:** authoritative historic DDL/policy/ACL lineage for the three legacy tables is absent from the supplied backup/migration history. Provide a canonical source or explicitly accept in writing that the original history cannot be proven. Reconstructed schema is not historical proof.
6. **Free-plan Auth risk:** leaked-password protection remains unavailable on the reviewed Free plan. Record owner risk acceptance with compensating controls or make an owner-approved plan decision; no upgrade or Auth-setting change has been made.
7. **Deployment:** after the evidence and decisions above close, re-check the exact PR head and CI, approve and merge PR #22, verify the Pages deployment commit, and test the hosted N+ PLAY/Admin journeys. Do not claim the latest candidate is live before verifying it.

## Safety invariants

- Demo/virtual points only. No real-money betting or cash payouts.
- Preserve all existing profiles, wallets and ledger rows.
- Do not make unapproved production ACL/RLS, Auth, paid-plan, scheduler, or game-setting changes.
- Keep all six game flags disabled until written rules and hosted acceptance pass.
- Do not mark the full game launch production-ready while any release gate remains open.
