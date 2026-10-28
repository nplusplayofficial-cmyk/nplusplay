# N+ PLAY + N+ ADMIN — release readiness snapshot (2026-10-28)

## Status

**Exact split-migration local replay now PASS. The complete production launch is still blocked by hosted acceptance and owner decisions.** This report distinguishes local reconstructed-baseline evidence from canonical historical schema proof and hosted Auth verification.

## Current candidate and CI

- PR #22: [open draft PR](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/22)
- Branch: `integration/release-candidate-2026-10-27`
- Candidate code HEAD used for the local replay: `bb3e2c708d630ba629ea3d99ac4a229961b58f57`
- Static QA #725: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40686878703
- Release Smoke #312: PASS — https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40686878533
- Browser-smoke passed as part of Static QA #725.

PR #22 remains OPEN / DRAFT / unmerged. The candidate has not been declared deployed to GitHub Pages.

## Exact split-migration full local replay — PASS (user-run, 2026-10-28)

The user ran `qa/run-final-split-replay.ps1` from the correct current candidate worktree.

- Container: `supabase_db_nplusplay-restore-lab-v2`, image `public.ecr.aws/supabase/postgres:17.11.0.004`.
- Verified restore source: `nplus_restore_acceptance_20261027`.
- Fresh disposable replay database: `nplus_migration_replay_20261031`.
- All 29 distinct captured SQL-body fingerprints matched. All 40 captured production-history bodies replayed in their captured order.
- Candidate migrations `20261027172625` (referral lifecycle constraint), `20261027172637` (legacy-table browser ACL hardening), `20261027172656` (WINGO Admin overload defaults), and the exact current split finite-number migrations `20261027180120`, `20261027180134`, `20261027180141` all applied successfully on the disposable reconstructed clone.
- QA-only wallet/ledger and request-table ACL reconciliation overlays applied and passed their explicit contract checks.
- Backup-acceptance checks: 5 profiles, 5 wallets, 140 wallet-ledger rows, 5 deposits, 6 game settings; zero negative balances, zero ledger arithmetic mismatches, zero wallets without history, and zero wallet/latest-ledger mismatches in that restored baseline.
- Final invariants passed: all six games disabled; RLS/browser write constraints; phone-enumeration RPC not executable by browser roles; generic positive/game-credit guard; server-only Aviator worker and local cron job; both WINGO Admin overloads authorized; recent activity aggregate-only; wallet-ledger arithmetic consistent.
- Synthetic database E2E passed deposit idempotency/approval/rejection and Admin authorization; Admin wallet adjustment/ledger and positive-credit protection; referral uniqueness/self-referral/qualification/one-time tier claim; and withdrawal idempotency/status-only Admin review. Synthetic E2E ended in `ROLLBACK`.
- **PASS:** `RECONSTRUCTED-BASELINE FULL REPLAY CHECK PASSED` for `nplus_migration_replay_20261031`.
- **PASS:** local `cron.database_name` restored to `nplus_migration_replay_20261026`.
- This result is for code HEAD `bb3e2c708d630ba629ea3d99ac4a229961b58f57`. The replay script also confirms it did not modify Supabase production or its migration history.

### Scope limitation

The source clone used a separate schema-only reconstruction of the three legacy relations from the 2026-10-27 live catalog, and QA-only ACL overlays. Therefore the replay verifies the captured 40-body sequence plus candidate split migrations and listed invariants on a reconstructed baseline. It does **not** prove original historical DDL/policy/ACL provenance for `manual_deposits`, `user_bank_details`, and `withdraw_requests`. This replay does not close hosted signup/OTP/login/recovery or hosted browser acceptance.

## Production read-only postconditions

Refreshed against Supabase project `pcrxlqduygvzchzxsmdv` on 2026-10-28:

- Recorded migration versions: `20261027172625`, `20261027172637`, `20261027172656`, `20261027180120`, `20261027180134`, and `20261027180141`.
- All 10 target numeric-sensitive RPCs have NaN/Infinity guards per the verified rollout evidence.
- All six game flags (5D, AVIATOR, K3, MOTO, TRX, WINGO) are `false`.
- The three legacy tables have RLS enabled. `anon` has no direct SELECT/INSERT/UPDATE/DELETE privileges. `authenticated` has SELECT only on `manual_deposits` and no direct privileges on `user_bank_details` or `withdraw_requests`. Legacy-table ACL hardening is already deployed and verified.
- Current production integrity: 5 profiles, 5 wallets, 146 wallet-ledger rows; zero negative wallets, zero ledger arithmetic mismatches, and zero current-wallet/latest-ledger mismatches.
- Read-only checks did not change users, wallet/ledger rows, Auth settings, paid plan, scheduler, or game flags.
- Source/catalog review documents 53 authenticated-callable SECURITY DEFINER functions and one intentionally public aggregate activity RPC; no blanket EXECUTE revoke should be used.

## Gates still open before full game launch

1. **Hosted account acceptance:** test real signup/email OTP delivery, login, password recovery/mobile return, normal-user versus Admin access, and synthetic wallet/deposit/withdrawal/referral journeys with a controlled inbox. Do not modify existing accounts.
2. **Referral contract:** earlier requirement is 200 approved demo credits → inviter receives 20 demo points once. Current code/UI implements 500-point qualification plus separate screenshot-based tier claims. Owner must choose the rule before changing behavior or issuing credits.
3. **K3/5D/TRX rules:** no written, approved server-authoritative result/payout/rounding/cancel/refund/recovery contract exists. Do not invent payout multipliers. Keep all six flags disabled until written rules and server-settlement tests are approved.
4. **Historical schema provenance:** provide authoritative historic DDL/policy/ACL source for the three legacy tables, or accept in writing that original history cannot be proven from available evidence.
5. **Free-plan Auth risk:** leaked-password protection is unavailable on the reviewed Free plan. Record explicit risk acceptance with compensating controls or make an owner-approved plan decision; no upgrade/Auth setting change has been made.
6. **Release/deployment:** after these gates close, review and approve the exact candidate, merge PR #22, verify the Pages deployment commit, and test the hosted N+ PLAY/Admin flows. Current candidate is not declared live.

## Safety invariants

- Demo/virtual points only. No real-money betting or cash payouts.
- Preserve all existing profiles, wallets and ledger rows.
- Do not make unapproved production ACL/RLS, Auth, paid-plan, scheduler, or game-setting changes.
- Keep all six game flags disabled until written game rules and hosted acceptance pass.
- Do not mark the full game launch production-ready while any release gate remains open.
