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
