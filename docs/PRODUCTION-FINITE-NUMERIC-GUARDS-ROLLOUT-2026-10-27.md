# Production Finite-Number RPC Guard Rollout — 2026-10-27

## Status

**Applied successfully; live postconditions verified read-only.** Production project: `pcrxlqduygvzchzxsmdv`.

The split candidate migrations were inspected against the live function bodies, applied sequentially with the Supabase migration tool, recorded under the actual server-assigned versions below, and then rechecked in the live catalog. No migration-history rows were rewritten and no migration was blindly re-run.

## Recorded production migration versions

| Recorded version | Recorded migration name | Repository source file | Source blob SHA |
|---|---|---|---|
| `20261027180120` | `guard_finite_numeric_request_and_gift_inputs` | `supabase/migrations/20261027180120_guard_finite_numeric_request_and_gift_inputs.sql` | `8dcfb9a8cea0313f37a0f0c0a9a19af32c360cfd` |
| `20261027180134` | `guard_finite_numeric_safe_transfer_and_referral` | `supabase/migrations/20261027180134_guard_finite_numeric_safe_transfer_and_referral.sql` | `14753e4cb216b0b06bc026f2e079e190c7a283c8` |
| `20261027180141` | `guard_finite_numeric_game_stakes` | `supabase/migrations/20261027180141_guard_finite_numeric_game_stakes.sql` | `6cf939ff4e31e5e360d769709b6b1ad4aad878c6` |

The repository filenames have been aligned to the recorded production version IDs to prevent future migration tooling from treating these migrations as unapplied. The three SQL bodies are unchanged from the candidate files that passed isolated PostgreSQL runtime QA.

## Live postconditions

A post-deployment, read-only query returned the following:

- **10/10 target RPC definitions contain non-finite numeric checks** for NaN/Infinity inputs.
- All 10 functions remain owned by `postgres`, remain `SECURITY DEFINER`, and retain `search_path=pg_catalog, public`.
- All six game flags remain disabled: 5D, AVIATOR, K3, MOTO, TRX and WINGO.
- `manual_deposits`, `user_bank_details`, and `withdraw_requests` all remain RLS-enabled. `anon` has no direct SELECT/INSERT/UPDATE/DELETE on those three tables; `authenticated` has SELECT only on `manual_deposits` and no direct SELECT/INSERT/UPDATE/DELETE on the other two.
- Aggregate integrity checks: 5 profiles, 5 demo wallets, 146 wallet-ledger rows, 0 negative wallets, 0 ledger arithmetic mismatches and 0 current-wallet/latest-ledger mismatches.
- The migration SQL replaces function definitions; it does not issue DML to rewrite wallet balances, user rows or ledger entries. Auth settings and scheduler configuration were not changed by this rollout.

The migration history contains 46 rows after rollout, including the three versions above. The existing three protective migrations remain recorded as `20261027172625`, `20261027172637` and `20261027172656`.

## Validation limits and remaining release gates

The split migrations passed isolated disposable-PostgreSQL tests in Static QA #701, and Release Smoke #288 passed on the same pre-filename-alignment candidate HEAD. A new CI run on the filename-aligned current branch HEAD is required before merge.

This deployment does **not** certify the full product release. Still open:

1. Run a fresh full local reconstructed-baseline replay using the exact split migration files on the user's existing local restore lab. The previously recorded full replay exercised the pre-split monolithic source and cannot substitute for this evidence. Keep the replay strictly local and preserve the cron target after the run.
2. Complete hosted signup/email OTP/login/recovery and synthetic normal-user/Admin wallet/request/referral/browser journeys with a controlled inbox.
3. Resolve the referral contract conflict (prior 200 demo-credit qualification / 20-point reward vs current 500-point tier qualification) with owner decision; do not credit users or change the rule silently.
4. Obtain explicit K3/5D/TRX payout-rule approval; keep all six game flags disabled.
5. Obtain authoritative historical DDL/ACL/policy provenance for the three legacy tables, or record explicit owner acceptance that original history cannot be proven.
6. Record owner risk acceptance for the Free-plan leaked-password-protection limitation or an owner-approved plan decision; no plan or Auth setting was changed here.
7. Independently verify GitHub Pages deployment and hosted N+ PLAY/N+ ADMIN journeys after the remaining gates close.

PR #22 must remain OPEN/DRAFT until these gates are genuinely closed. No production game flag, wallet balance, ledger entry, Auth setting, paid plan or scheduler configuration was changed as part of this rollout.
