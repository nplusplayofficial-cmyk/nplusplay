# Reconstructed-Baseline Local Replay Result — 2026-10-27

## Result

**PASS — user-run local restore-lab acceptance, not production deployment approval.**

- Candidate branch: `integration/release-candidate-2026-10-27`
- Candidate source HEAD tested: `27d13556c393881e67a27389a42279fa36d12690`
- Local Docker container: `supabase_db_nplusplay-restore-lab-v2`
- Restore acceptance DB: `nplus_restore_acceptance_20261027`
- Disposable replay DB: `nplus_migration_replay_20261028`
- PostgreSQL image reported by the local runner: `public.ecr.aws/supabase/postgres:17.11.0.004`

## Evidence recorded from the local run

1. Backup restore acceptance passed. The 661-entry archive restored with owner/ACL restoration enabled. Checks reported 5 profiles, 5 wallets, 140 ledger rows, 5 deposits, and 6 game settings; zero wallet arithmetic mismatches, negative wallets, wallets without history, or wallet/latest-ledger mismatches.
2. All 29 recovered distinct SQL bodies matched their captured fingerprints. The recorded order contained 40 migration history rows (including exact repeated bodies).
3. All 40 recorded migration bodies replayed successfully on the disposable replay DB after applying a separate empty schema-only bootstrap for the three legacy relations missing from the 2026-10-15 backup baseline.
4. The local-only candidate referral-state and legacy-table ACL migrations, the finite-numeric guard source bundle as it existed at the tested HEAD, and QA-only wallet/ledger/request ACL reconciliation overlays applied successfully on that clone.
5. Final invariants passed: six game settings remained disabled; public tables had RLS enabled; browser roles could not directly write wallet/ledger/request tables; phone-enumeration RPC was not executable by browser roles; server-only Aviator worker and local cron job were present; both WINGO Admin overloads retained explicit authorization; Recent Activity remained aggregate-only; wallet-ledger arithmetic remained consistent.
6. Synthetic database E2E passed for deposit idempotency/approval/rejection and Admin authorization, Admin wallet adjustment/ledger and positive-credit protection, referral uniqueness/self-referral/qualification/one-time tier claim, and withdrawal idempotency/status-only Admin review. The synthetic test transaction ended with `ROLLBACK`.

## Important limitations

- This is a **reconstructed-baseline** replay, not proof of canonical historical schema replay. The three legacy relation definitions were reconstructed from a snapshot of the current live catalog; this does not prove their original historical DDL, policy history, or ACL provenance.
- Candidate migrations and QA-only ACL overlays were tested on a local disposable database only. No production Supabase schema, grants, wallet balances, Auth settings, scheduler, or game settings were changed by this run.
- This local replay is not a hosted signup/OTP/login or full-browser acceptance test, and does not close the remaining manual SECURITY DEFINER review, leaked-password protection plan limitation, or unapproved K3/5D/TRX settlement rules.
- All six games remain disabled. Do not merge/deploy on the strength of this run alone.

## Local lab configuration cleanup

The local container's `cron.database_name` was changed to `nplus_migration_replay_20261028` to allow the captured scheduler migration to replay. After preserving this result, restore the lab's prior setting (`nplus_migration_replay_20261026`) if that database is still the intended local cron target. This is a local Docker configuration only.


## Subsequent candidate hardening after this recorded local run — 2026-10-27

The above local replay was run against candidate HEAD `27d13556c393881e67a27389a42279fa36d12690`. After that run, two timestamped candidate migrations were added and passed isolated CI regression tests:

- `supabase/migrations/20261027140000_fix_wingo_admin_overload_defaults.sql` removes the overlapping defaults from the five-argument WINGO Admin overload while preserving the four-argument compatibility overload, original owner, fixed search path and intended execute grants. The disposable regression test reproduces the prior ambiguity and confirms deterministic overload resolution plus non-admin denial.
- The former monolithic numeric guard source was split into 20261027180000_guard_finite_numeric_request_and_gift_inputs.sql, 20261027180100_guard_finite_numeric_safe_transfer_and_referral.sql, and 20261027180200_guard_finite_numeric_game_stakes.sql. The prior full local replay exercised the same function bodies from the pre-split monolithic file; the split sequence needs a fresh CI/runtime pass before it is called verified.

Latest tested candidate at the time of this note: `72969cf8ce1393e7a95b8b1221423c8f70120b36`; Static QA #660 and Release Smoke #247 passed. This does **not** mean those two newer migrations have been replayed against the full restored local database. A final fresh local reconstructed-baseline replay is still required to exercise the exact latest candidate head. Use a new target DB name such as `nplus_migration_replay_20261029`; do not overwrite the earlier `20261028` evidence DB.

For the final local run, temporarily set the local restore-lab `cron.database_name` to the new replay database before starting the sequence, then restore its prior value (`nplus_migration_replay_20261026`) and restart the local container afterwards. This is local Docker configuration only. Keep all six games disabled and do not use the reconstructed schema bootstrap as proof of original historical DDL.


## Latest full local replay — 2026-10-27

**User-executed result: PASS** on exact candidate HEAD `eb4377e09139cf826c6d102d7d8b6b39a41a99c4`.

- Local restore lab: `supabase_db_nplusplay-restore-lab-v2`, PostgreSQL image `public.ecr.aws/supabase/postgres:17.11.0.004`.
- Backup acceptance source: `nplus_restore_acceptance_20261027`.
- Fresh disposable replay target: `nplus_migration_replay_20261030`.
- Captured history: all 40 recorded rows replayed successfully; all 29 distinct recovered SQL bodies matched the stored fingerprints.
- Read-only restore checks again passed: 5 profiles, 5 wallets, 140 ledger rows, 5 deposits, 6 game settings; zero wallet arithmetic mismatches, negative balances, wallets without history, or latest-ledger mismatches.
- Candidate migrations 20261027120000 (referral qualified state), 20261027130000 (legacy table browser ACL hardening), 20261027140000 (WINGO Admin overload defaults), and the pre-split monolithic finite numeric guard all applied successfully to the disposable clone. The current split form is now verified in isolated CI: Static QA #697 and Release Smoke #284 pass, runtime finite-number migration regression passes, and browser smoke passed 38/38 pages plus 17/17 mobile checks. The split form has not been applied to production.
- QA-only wallet/ledger/request ACL reconciliation overlays applied and passed their contract checks.
- Final invariants passed: all six game settings disabled; public tables RLS enabled; no direct browser writes to wallet/ledger/request tables; phone enumeration RPC denied to browser roles; generic positive/game credit guard present; Aviator worker server-only with local cron job; both WINGO Admin overloads include Admin authorization; Recent Activity remains aggregate-only; wallet ledger arithmetic consistent.
- Synthetic DB E2E passed deposit idempotency/approval/rejection and Admin authorization; Admin wallet adjustment/ledger and positive-credit protection; referral uniqueness/self-referral/qualification/one-time tier claim; and withdrawal idempotency/status-only Admin review. Test ended with `ROLLBACK`.
- The local cron setting was restored to `nplus_migration_replay_20261026`; PostgreSQL was accepting connections after restart.

**Scope limitation:** this is still a reconstructed-baseline replay: the three legacy relation shapes were bootstrapped from the current live catalog because the supplied 2026-10-15 backup plus captured SQL bodies do not establish their original historical DDL/policy/ACL lineage. This is not canonical historical replay and does not certify production release. No production Supabase database, migration history, wallet/user rows, Auth settings, scheduler settings or game flags were changed.


## Production migration rollout update — 2026-10-27

Three migrations have now been applied to the live Supabase project via the migration API: referral lifecycle state, legacy-table ACL hardening, and WINGO overload resolution. They were recorded by Supabase as versions 20261027172625, 20261027172637, and 20261027172656 respectively. The repository migration filenames were aligned to those recorded versions so future migration tooling will not replay them.

The finite-number guard code remains pending production rollout. The monolithic apply did not return success; current live catalog checks indicated the guard was absent. That code is now split into three smaller migrations for isolated testing and controlled rollout. No wallet/user rows were rewritten, and the six game flags stayed disabled.


## Current split-migration verification — 2026-10-27

The three split finite-number migrations pass the current Static QA runtime test in a disposable PostgreSQL database. Current code head is 16a66cf8c941da7893716b1faad9729b8d6f98aa. Release Smoke #284 passes. The finite-number guards are still not live on production; don't mark that production security gate complete until the three migration records are verified in live migration history and the function catalog shows the guards.


## Superseding production rollout update — 2026-10-27

The three finite-number guard migrations were subsequently applied to the live Supabase project and verified. Their recorded versions are `20261027180120`, `20261027180134`, and `20261027180141`; see [production guard rollout evidence](PRODUCTION-FINITE-NUMERIC-GUARDS-ROLLOUT-2026-10-27.md). This later production rollout does not change the provenance limitations of this local replay.

The current repo migration filenames align to the server-recorded versions. Live postconditions confirmed all ten target RPCs have NaN/Infinity checks, all six game flags remain disabled, legacy table RLS/grants remain correct, and wallet/ledger aggregate invariants report no mismatches. The exact split-file sequence has not yet been fully replayed against the local restored-baseline clone; the earlier recorded replay used the pre-split monolithic guard source. Treat the prior replay result as historical evidence only, not as a pass for the current split files.

Hosted Auth/OTP/login/recovery and synthetic browser journeys, owner decisions on the referral reward contract and payout rules, historical legacy schema provenance/risk disposition, the Free-plan leaked-password-protection decision, and final hosted Pages verification remain open. PR #22 remains OPEN/DRAFT.
