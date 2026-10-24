# Supabase migration history source map — 2026-10-23

## Purpose and safety decision

The live Supabase project currently records 40 applied migrations. The `main` branch has six SQL files under `supabase/migrations/`; only the two 2026-10-23 cleanup files match a live version and name exactly.

This source map is an audit aid, **not** a migration repair. It distinguishes files that can be located from SQL whose exact production-applied contents are not proven. A matching subject or function name is not proof that a file is byte-for-byte or behaviorally identical to the SQL previously applied.

**No production SQL was executed or changed during this mapping exercise.** Do not run `supabase db push`, manually replay historical SQL on production, or replace missing history entries with empty/no-op migrations.

## Source mapping

| Live version | Live migration name | Source found in repository | Confidence / action |
|---|---|---|---|
| 20261020135823 | block_generic_wallet_credits_before_game_rpc_deployment | `sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql` | **Unverified.** The source header says not to run before settlement/frontend rollout, while the history name suggests a pre-rollout operation. Confirm the applied SQL and timing before mapping. |
| 20261020162640 | temporarily_pause_games_until_authoritative_backend_rollout | No exact source identified | **Missing.** Recover the original SQL from a historical commit, branch, or trusted deployment record. |
| 20261020162811 | null_safe_admin_rpc_authorization_guard | No exact source identified | **Missing.** Do not substitute a similarly named later guard without comparing the full function definitions. |
| 20261021155813 | admin_game_status_fail_closed_guard | `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql` | **Candidate only.** Name/function match; exact applied SQL has not been independently verified. |
| 20261021160439 | account_preferences_release_support | `supabase/migrations/20261019000100_account_preferences.sql` | **Candidate.** Source exists under an older non-matching version/name. Verify full content against deployment records before canonicalizing. |
| 20261021160443 | demo_wallet_requests_release_support | `supabase/migrations/20261019000150_demo_wallet_requests.sql` and `sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql` | **Candidate.** The repository copies share a Git blob, but live applied content is not available in the history listing. |
| 20261021160446 | admin_deposit_actions_release_support | `supabase/migrations/20261019000175_admin_deposit_actions.sql` and `sql/NPLUS_PLAY_ADMIN_DEPOSIT_ACTIONS.sql` | **Candidate.** The repository copies share a Git blob; verify against the applied SQL. |
| 20261021160503 | demo_referrals_base_release_support | `supabase/migrations/20261019000200_demo_referrals.sql` and `sql/NPLUS_PLAY_DEMO_REFERRALS.sql` | **Candidate.** The repository copies share a Git blob; verify against the applied SQL. |
| 20261021160917 | nplus_vip_referral_demo | `sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql` and draft-branch `supabase/migrations/20261021182729_nplus_vip_referral_demo.sql` | **Ambiguous.** The candidate copies have different Git blob hashes/content. Recover the actual applied version; do not select one by filename alone. |
| 20261021160935 | nplus_server_settlement_foundation | `sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql` and draft-branch `supabase/migrations/20261021182718_nplus_server_settlement_foundation.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161052 | nplus_motorace_schema | `sql/NPLUS_PLAY_MOTORACE_SCHEMA.sql` and draft-branch `supabase/migrations/20261021182719_nplus_motorace_schema.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161109 | nplus_motorace_rpc | `sql/NPLUS_PLAY_MOTORACE_RPC.sql` and draft-branch `supabase/migrations/20261021182720_nplus_motorace_rpc.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161129 | nplus_aviator_schema | `sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql` and draft-branch `supabase/migrations/20261021182721_nplus_aviator_schema.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161143 | nplus_aviator_rpc | `sql/NPLUS_PLAY_AVIATOR_RPC.sql` and draft-branch `supabase/migrations/20261021182722_nplus_aviator_rpc.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161152 | nplus_aviator_worker_recovery | Draft-branch `supabase/migrations/20261021182723_nplus_aviator_worker_recovery.sql` / `sql/NPLUS_PLAY_AVIATOR_SCHEDULER_RECOVERY.sql` | **Candidate.** Source is available on the draft branch, not canonical `main`; verify the production-applied content before restoring it. |
| 20261021161206 | nplus_aviator_persistent_scheduler | Draft-branch `supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql` | **Candidate.** Source is on the draft branch; exact historical SQL not independently verified. |
| 20261021161217 | nplus_admin_user_tools | `sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql` and draft-branch `supabase/migrations/20261021182725_nplus_admin_user_tools.sql` | **Ambiguous.** Candidate copies have different Git blob hashes/content. |
| 20261021161233 | nplus_admin_game_status | `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql` and draft-branch `supabase/migrations/20261021182726_nplus_admin_game_status.sql` | **Source found; applied version still unverified.** Both repository paths point to the same Git blob. |
| 20261021161242 | nplus_admin_null_profile_guard | `sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql` and draft-branch `supabase/migrations/20261021182727_nplus_admin_null_profile_guard.sql` | **Ambiguous.** Candidate copies have different Git blob hashes/content. |
| 20261021161251 | nplus_recent_demo_activity | Draft-branch `supabase/migrations/20261021182728_nplus_recent_demo_activity.sql` / `sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql` | **Candidate.** Source is on the draft branch, not canonical `main`; verify the applied SQL and preserve the public aggregate-only behavior. |
| 20261021162503 | post_rollout_revoke_phone_enumeration | `sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql` | **Candidate only.** Its header has a frontend-deployment precondition; verify rollout timing and exact content. |
| 20261021162645 | enable_server_backed_virtual_demo_games | No exact source identified | **Missing.** Recover the SQL and record the exact game settings affected. |
| 20261022055326 | 20261021182718_nplus_server_settlement_foundation | Draft-branch `supabase/migrations/20261021182718_nplus_server_settlement_foundation.sql` | **Source path found.** Filename stem matches the live history name. Verify this is the exact SQL run for this second application. |
| 20261022055330 | 20261021182719_nplus_motorace_schema | Draft-branch `supabase/migrations/20261021182719_nplus_motorace_schema.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055334 | 20261021182720_nplus_motorace_rpc | Draft-branch `supabase/migrations/20261021182720_nplus_motorace_rpc.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055340 | 20261021182721_nplus_aviator_schema | Draft-branch `supabase/migrations/20261021182721_nplus_aviator_schema.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055345 | 20261021182722_nplus_aviator_rpc | Draft-branch `supabase/migrations/20261021182722_nplus_aviator_rpc.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055350 | 20261021182723_nplus_aviator_worker_recovery | Draft-branch `supabase/migrations/20261021182723_nplus_aviator_worker_recovery.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055354 | 20261021182724_nplus_aviator_persistent_scheduler | Draft-branch `supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055400 | 20261021182725_nplus_admin_user_tools | Draft-branch `supabase/migrations/20261021182725_nplus_admin_user_tools.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055404 | 20261021182726_nplus_admin_game_status | Draft-branch `supabase/migrations/20261021182726_nplus_admin_game_status.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055410 | 20261021182727_nplus_admin_null_profile_guard | Draft-branch `supabase/migrations/20261021182727_nplus_admin_null_profile_guard.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022055424 | 20261021182728_nplus_recent_demo_activity | Draft-branch `supabase/migrations/20261021182728_nplus_recent_demo_activity.sql` | **Source path found.** Filename stem matches the live history name; verify exact applied content. |
| 20261022062741 | enable_supported_virtual_demo_games_preview | No exact source identified | **Missing.** Recover the SQL and confirm which game settings it enabled before documenting a replay sequence. |
| 20261022064315 | pause_unverified_games_and_lockdown_settlement_rpcs_20261022 | No exact source identified | **Missing.** Recover the SQL; preserve the final fail-closed state and blocked arbitrary positive credits. |
| 20261023081657 | fix_profiles_rls_admin_login_recursion_20261023 | `sql/NPLUS_PLAY_PROFILES_RLS_ADMIN_LOGIN_FIX_2026-10-23.sql` | **Source found; applied version still unverified.** SQL file is present in `main`; verify the exact applied definition/policy state. |
| 20261023081758 | secure_admin_demo_wallet_adjustment_rpc_20261023 | `sql/NPLUS_PLAY_ADMIN_DEMO_WALLET_ADJUSTMENT_GUARD_2026-10-23.sql` | **Ambiguous.** The checked-in script appears to represent the later guard but does not prove the earlier migration's exact contents. |
| 20261023081916 | align_admin_wallet_adjust_rpc_signature_20261023 | `sql/NPLUS_PLAY_ADMIN_DEMO_WALLET_ADJUSTMENT_GUARD_2026-10-23.sql` | **Ambiguous.** The checked-in script may represent the final signature, but no distinct historical SQL source was located for this step. |
| 20261023092858 | optimize_rls_policies_and_foreign_key_indexes_20261023 | `supabase/migrations/20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql` | **Exact version/name file is tracked on main.** |
| 20261023093056 | drop_duplicate_referral_unique_indexes_20261023 | `supabase/migrations/20261023093056_drop_duplicate_referral_unique_indexes_20261023.sql` | **Exact version/name file is tracked on main.** |

## Required reconciliation procedure

1. Recover the missing/ambiguous SQL from trusted historic commits, Supabase dashboard SQL editor history, deployment logs, or an original controlled backup. The current Supabase migration list does not include the SQL contents.
2. For each applied record, keep a mapping containing the live version/name, exact source file, file/blob hash, evidence for equivalence, and whether the operation is safe and idempotent on a clean database.
3. Preserve duplicate applied entries as history only when the duplicate execution is understood and replay-safe. Do not silently convert them into no-op migrations.
4. Build a fresh disposable database from the proposed canonical migration chain. Separately restore the private production backup to a different isolated database. Compare schema objects, RLS policies, grants, function definitions, triggers, indexes, and final game settings.
5. Confirm the generic positive wallet-credit guard and non-admin RPC denials with executable tests. Confirm all six game settings are still disabled.
6. Only after clean replay and source mapping pass review, prepare a separate migration-history repair plan. Do not mutate production migration history as a shortcut to make counts match.

## Current status

**Source discovery has progressed; production history is not yet reconciled.** Some migration SQL sources are available, but exact original SQL for several operations is still missing or ambiguous. A clean replay has not been proven. This document records that limitation rather than treating filename similarity as evidence of equivalence.


## Additional source-recovery pass — 2026-10-23

A targeted repository pass checked the expected migration-file paths for the five unresolved operations below on these existing branches: `audit/supabase-migration-history-map-2026-10-23`, `feature/nplus-free-release-audit-2026-10-19`, `fixes/premium-audit-2026-10-15`, and `security/live-security-audit-2026-10-23`.

| Unresolved live operation | Result of expected-path check | Commit-message search |
|---|---|---|
| `temporarily_pause_games_until_authoritative_backend_rollout` | Exact expected migration path not found on checked branches | No matching commit result |
| `null_safe_admin_rpc_authorization_guard` | Exact expected migration path not found on checked branches | No matching commit result |
| `enable_server_backed_virtual_demo_games` | Exact expected migration path not found on checked branches | No matching commit result |
| `enable_supported_virtual_demo_games_preview` | Exact expected migration path not found on checked branches | No matching commit result |
| `pause_unverified_games_and_lockdown_settlement_rpcs_20261022` | Exact expected migration path not found on checked branches | No matching commit result |

These are bounded search results, not proof that the SQL never existed: files may have different paths/names, commits may not mention the migration identifier, or source may exist in deployment/dashboard history rather than Git. No replacement SQL was inferred and no production database or migration history was changed.

The source-recovery pass also confirmed that candidate files such as `sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql` and `sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql` exist on the audit branch, but their existence does not establish equivalence to the corresponding production-applied SQL. Their ambiguity status remains unchanged.

**Next evidence source:** inspect the full migration-related file tree and historical commit diffs across the recovery branches, then request/inspect Supabase SQL Editor history or deployment artifacts for the five unresolved operations. Continue to keep all games disabled and do not replay candidate SQL on production.


## Branch-tree and blob-hash verification — 2026-10-23

### Scope checked

Inspected the recursive Git trees for the current heads of:

- `main` — `680238f2428416faf44df0dced6f907d4cea7f08`
- `audit/supabase-migration-history-map-2026-10-23` — `6469f61af6eb3801c3e8e40e26fab4e7166c34c7`
- `feature/nplus-free-release-audit-2026-10-19` — `c58273fd168bb92a0153c49c9b31e7b6ba622adc`
- `fixes/premium-audit-2026-10-15` — `dd7f2c14666e628a46056dbb6e40077d367682cb`
- `security/live-security-audit-2026-10-23` — `5635e886725db00c0322303f490b5492b2be88ea`

The `main`, audit, feature, and security branches each have a readable repository tree. The fixes branch has no `supabase/migrations/` directory at its current head. The five missing migration identifiers listed above have no matching expected SQL paths in the current `supabase/migrations/` or `sql/` directories checked; GitHub path-specific commit-history queries for those exact expected paths also returned no commits. These are results for current trees and the exact queried paths only, not proof that no differently named script or external dashboard/deployment artifact exists.

### Repository blob evidence for candidate copies

A Git blob SHA proves only that two repository files have identical byte content when their SHAs match. It cannot prove production executed those bytes. The hashes below therefore improve source tracking but do not independently close any applied-history mapping.

| Candidate source | Observed repository blob SHA | What this establishes |
|---|---|---|
| `supabase/migrations/20261021182718_nplus_server_settlement_foundation.sql` (feature branch) and `sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql` (main/feature) | `ee1c9ad63379100b683a799061c6c855360f47d6` | These repository copies match each other. |
| `supabase/migrations/20261021182719_nplus_motorace_schema.sql` and `sql/NPLUS_PLAY_MOTORACE_SCHEMA.sql` | `84bdc7f8af7f23149b350c65abedf851fa29da4b` | Candidate copies match. |
| `supabase/migrations/20261021182720_nplus_motorace_rpc.sql` and `sql/NPLUS_PLAY_MOTORACE_RPC.sql` | `9ee0350dab9cfcb7ebab2a415a245ff462c34646` | Candidate copies match. |
| `supabase/migrations/20261021182721_nplus_aviator_schema.sql` and `sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql` | `d5823d7d2a203a4754d9c72f6380faf02c6fd977` | Candidate copies match. |
| `supabase/migrations/20261021182722_nplus_aviator_rpc.sql` and `sql/NPLUS_PLAY_AVIATOR_RPC.sql` | `411f5f7ed8cb4c6588fc80c366190d64b2126236` | Candidate copies match. |
| `supabase/migrations/20261021182723_nplus_aviator_worker_recovery.sql` and `sql/NPLUS_PLAY_AVIATOR_SCHEDULER_RECOVERY.sql` (feature branch) | `c8bfdbdcec13b217f149c326899bc728d765f886` | Candidate copies match; the source itself is marked draft and is not proof of applied SQL. |
| `supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql` | `83db97a9d70f6347dcec0230f171f43b9937d3fe` | Draft-branch candidate exists; a matching standalone SQL copy was not found in the inspected SQL directories. |
| `supabase/migrations/20261021182725_nplus_admin_user_tools.sql` and feature-branch `sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql` | `94c33fcbff58c6fed492775e2f0383208335f04b` | These feature-branch copies match, but main's `sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql` is `39f27b3c8b9753a7a67c754f135fb74625990538`; branch versions conflict. |
| `supabase/migrations/20261021182726_nplus_admin_game_status.sql` and `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql` | `0eacf5f22445c0481aecb6fed1352d7369c4b9ec` | These candidate copies match main and feature. Applied SQL still unproven. |
| `supabase/migrations/20261021182727_nplus_admin_null_profile_guard.sql` and feature-branch `sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql` | `d8b7173000211f8271508be2e9cc08c0854b2a0c` | These feature-branch copies match, but main's same-named SQL candidate is `43f70a84a6124ac0da5245ee9434438d3e202cdc`; branch versions conflict. |
| `supabase/migrations/20261021182728_nplus_recent_demo_activity.sql` and feature-branch `sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql` | `b25e0fd478bc33297b92563fc3d46aa366f1a4e9` | Feature-branch copies match; no corresponding SQL file exists on main. |
| `supabase/migrations/20261021182729_nplus_vip_referral_demo.sql` | `8e91d0b4077793b9e7d94cb670ae97130d364428` | This candidate differs from feature-branch `sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql` (`c676e956d1cd64216cafb56fd288d018bfb3bdc8`) and from main/audit/security's same-named SQL candidate (`68fb76d6bdb4a6ceb7d571cd7c6af0253984ac82`). The applied version remains ambiguous. |

### Fresh live-state evidence (read-only)

A direct live migration-list call and SQL catalog queries reconfirmed:

- `supabase_migrations.schema_migrations`: **40 rows**.
- `public.game_settings`: all six game keys `WINGO`, `K3`, `5D`, `TRX`, `MOTO`, and `AVIATOR` have `enabled = false`.
- Current catalog snapshot: **33** public tables, **69** public functions, **2** non-internal public triggers, and **22** public RLS policies.
- Both `nplus_admin_set_wingo_demo` signatures still exist (four-argument and five-argument); this remains an unresolved follow-up, not something changed during this migration review.
- Selected wallet/ledger and game table direct grants remain restricted in the inspected privilege snapshot. No production data or schema was changed.

This is a current-state snapshot. It is not evidence that a clean migration replay recreates the same objects or that each historical SQL body has been recovered.

## Clean replay and backup acceptance: execution blocker

The 2026-10-15 backup path is a Windows-local path supplied in the handover. The backup bytes are not mounted in this runtime; only the pasted handover text is available. This runtime also has no `psql`, `pg_restore`, or `docker` executable available. Therefore neither a new restore test nor a disposable local PostgreSQL replay could be executed in this session. The previously recorded restore transcript remains partial evidence because it used `--no-owner --no-acl`.

Do not create a Supabase cloud branch or project for replay without confirming its actual cost and obtaining approval where any nonzero cost applies. Do not upload the private backup to GitHub. To close these gates, run the replay/restore work in the existing local restore lab with the original private dump and a locally provisioned PostgreSQL/Supabase-compatible environment, then attach only redacted test output and schema/object summaries.

**Status after this pass: source evidence improved; the five missing SQL sources, three conflicting copy groups, full 40-row applied-SQL equivalence, production-faithful restore, and clean canonical replay remain open. Work #1 must not be marked complete.**


## Direct applied-SQL body comparison — 2026-10-23 (read-only)

### Important correction to the earlier source-search notes

The live table supabase_migrations.schema_migrations does store the SQL text in its statements array even though the standard migration-list endpoint returns only version/name. A read-only query fetched summary data from all 40 rows. Every row has one stored statement. Across the 40 history entries, the stored bodies produce **29 distinct SQL bodies and 11 repeated exact-body entries**. The 11 repeated pairs below are byte-for-byte the same after joining each row's statement array with a newline; this identifies duplicate applied bodies but does **not** itself prove that replaying them is safe.

The five operations previously described as missing from the checked Git paths can now be recovered from the live applied statement history. Four recovered bodies have been committed as evidence files under docs/recovered-live-migration-sql-2026-10-23/ on this audit branch; the null-safe admin guard is also present as an exact match to the existing main-branch SQL source noted below. These evidence files are not production migration files and must not be copied into supabase/migrations/ blindly.

### Repository comparisons supported by direct applied-SQL evidence

| Live version(s) | Outcome from full stored-body comparison |
|---|---|
| 20261020135823 | Stored body is 2,371 characters and does **not** match the 2,738-character main candidate POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql. |
| 20261020162640 | The exact 490-character applied body was recovered and archived on this audit branch. |
| 20261020162811 | Exact body match to sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql (24,321 characters). This is not the same as the later 25,576-character null-profile-guard body. |
| 20261021155813 | Stored body is 3,554 characters and is not the same as the later 2,004-character admin-game-status body. |
| 20261021160439 | Exact body match to supabase/migrations/20261019000100_account_preferences.sql (2,112 characters). |
| 20261021160443 | Exact body match to supabase/migrations/20261019000150_demo_wallet_requests.sql (8,761 characters). |
| 20261021160446 | Exact body match to supabase/migrations/20261019000175_admin_deposit_actions.sql (3,998 characters). |
| 20261021160503 | Exact body match to supabase/migrations/20261019000200_demo_referrals.sql (11,935 characters). |
| 20261021160917 | Exact body match to feature-branch supabase/migrations/20261021182729_nplus_vip_referral_demo.sql (53,258 characters). The main-branch SQL candidate differs. |
| 20261021160935 and 20261022055326 | Both history rows have the same 24,127-character body, which exactly matches feature-branch supabase/migrations/20261021182718_nplus_server_settlement_foundation.sql. |
| 20261021161052 and 20261022055330 | Both history rows have the same 2,036-character body, exactly matching feature-branch supabase/migrations/20261021182719_nplus_motorace_schema.sql. |
| 20261021161109 and 20261022055334 | Both history rows have the same 14,999-character body, exactly matching feature-branch supabase/migrations/20261021182720_nplus_motorace_rpc.sql. |
| 20261021161129 and 20261022055340 | Both history rows have the same 2,592-character body, exactly matching feature-branch supabase/migrations/20261021182721_nplus_aviator_schema.sql. |
| 20261021161143 and 20261022055345 | Both history rows have the same 21,231-character body, exactly matching feature-branch supabase/migrations/20261021182722_nplus_aviator_rpc.sql. |
| 20261021161152 and 20261022055350 | Both history rows have the same 15,522-character body, exactly matching feature-branch supabase/migrations/20261021182723_nplus_aviator_worker_recovery.sql. |
| 20261021161206 and 20261022055354 | Both history rows have the same 1,172-character body, exactly matching feature-branch supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql. |
| 20261021161217 and 20261022055400 | Both history rows have the same 5,989-character body, exactly matching feature-branch supabase/migrations/20261021182725_nplus_admin_user_tools.sql. The main-branch standalone SQL differs. |
| 20261021161233 and 20261022055404 | Both history rows have the same 2,004-character body, exactly matching supabase/migrations/20261021182726_nplus_admin_game_status.sql. |
| 20261021161242 and 20261022055410 | Both history rows have the same 25,576-character body, exactly matching feature-branch supabase/migrations/20261021182727_nplus_admin_null_profile_guard.sql. The main-branch standalone SQL differs. |
| 20261021161251 and 20261022055424 | Both history rows have the same 1,530-character body, exactly matching feature-branch supabase/migrations/20261021182728_nplus_recent_demo_activity.sql. |
| 20261021162503 | Exact body match to sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql (1,115 characters). This verifies the body, not whether the operational precondition was satisfied at the time. |
| 20261021162645 | The exact 1,050-character applied body was recovered and archived on this audit branch. |
| 20261022062741 | The exact 4,525-character applied body was recovered and archived on this audit branch. |
| 20261022064315 | The exact 872-character applied body was recovered and archived on this audit branch. It records the final pause/settlement-lockdown operation. |
| 20261023081657 | Stored body is 547 characters; main candidate is 357 characters. They differ. |
| 20261023081758 | Stored body is 3,059 characters; main candidate is 2,944 characters. They differ. |
| 20261023081916 | Stored body is 3,040 characters; main candidate is 2,944 characters. They differ. |
| 20261023092858 | Stored body is 5,177 characters; main migration file is 5,106 characters. They differ despite the matching version/name. |
| 20261023093056 | Stored body is 284 characters; main migration file is 357 characters. They differ despite the matching version/name. |

The exact repeated SQL-body groups are:
- 20261021160935 / 20261022055326 — server settlement foundation
- 20261021161052 / 20261022055330 — MotoRace schema
- 20261021161109 / 20261022055334 — MotoRace RPC
- 20261021161129 / 20261022055340 — Aviator schema
- 20261021161143 / 20261022055345 — Aviator RPC
- 20261021161152 / 20261022055350 — Aviator worker recovery
- 20261021161206 / 20261022055354 — persistent scheduler
- 20261021161217 / 20261022055400 — admin user tools
- 20261021161233 / 20261022055404 — admin game status
- 20261021161242 / 20261022055410 — null-profile guard
- 20261021161251 / 20261022055424 — recent demo activity

This closes the earlier **source-retrieval** gap for those five operations, but not clean-replay safety. The final six settings were re-queried on 2026-10-23 and remain disabled: WINGO, K3, 5D, TRX, MOTO, AVIATOR. A heuristic scan found no private-key marker, PostgreSQL credential URI, Supabase secret-key pattern, or JWT-shaped value in stored SQL. A broad service_role-proximity heuristic returned possible code-context matches and should not be treated as a definitive secret scan. No migration history rows, schema objects, wallet data, or game settings were changed by these queries.

### What still blocks completion of Work #1

1. The compared main-branch files with length mismatches must be corrected only through a reviewed source-of-truth decision; do not overwrite a file merely to make it match production.
2. The exact applied SQL has not yet been fully represented as an approved canonical migration chain with replay ordering, prerequisites, role/extension assumptions, and idempotency decisions. Repeated bodies need an explicit replay-safety review.
3. Clean replay in a disposable PostgreSQL/Supabase-compatible database is still not executed in this session.
4. The backup restore test still has not been rerun with original ownership/grants/ACL semantics in a separate local environment. The previous --no-owner --no-acl transcript is not sufficient for restore acceptance.

**Revised status:** all 40 production-applied SQL bodies are available for read-only inspection from the live history table; comparisons have verified a substantial subset and identified several checked-in-file mismatches. This improves source recovery materially, but **Work #1 remains open** until clean replay and backup-acceptance gates pass. Production was read-only throughout.


### Duplicate-body static replay-risk scan — 2026-10-23

A read-only pattern scan was run over the 11 identical-body pairs. It did not flag unguarded CREATE TABLE/INDEX, ADD CONSTRAINT/COLUMN, INSERT, UPDATE, or DELETE patterns in these duplicate bodies. Eight bodies contain CREATE OR REPLACE syntax; three do not. This is only a text-pattern triage aid (not a SQL parser and not a replay test), so it does **not** establish idempotency, transaction safety, role prerequisites, or identical outcomes in a clean database. Duplicate records remain subject to manual review and clean replay before any canonical chain is approved.
