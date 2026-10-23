# N+ PLAY — Live Supabase migration drift (2026-10-23)

## Finding

The connected live Supabase project `pcrxlqduygvzchzxsmdv` reports **40 applied migration-history rows**. The `main` branch's `supabase/migrations/` folder currently contains six SQL files. Only the two new 2026-10-23 migration files match the live history by exact version and name.

Four older files currently tracked on `main` use versions `20261019000100`, `20261019000150`, `20261019000175`, and `20261019000200`; those exact version numbers do not appear in the live migration history. The live database instead records similarly scoped release-support migrations under versions `20261021160439`–`20261021160503`. That does **not** prove the schemas were not applied; it means the checked-in filenames/version history is not a canonical exact match to production.

## Exact live migration history

| Live version | Name | Exact file tracked on `main` |
|---|---|---|
| 20261020135823 | block_generic_wallet_credits_before_game_rpc_deployment | No |
| 20261020162640 | temporarily_pause_games_until_authoritative_backend_rollout | No |
| 20261020162811 | null_safe_admin_rpc_authorization_guard | No |
| 20261021155813 | admin_game_status_fail_closed_guard | No |
| 20261021160439 | account_preferences_release_support | No |
| 20261021160443 | demo_wallet_requests_release_support | No |
| 20261021160446 | admin_deposit_actions_release_support | No |
| 20261021160503 | demo_referrals_base_release_support | No |
| 20261021160917 | nplus_vip_referral_demo | No |
| 20261021160935 | nplus_server_settlement_foundation | No |
| 20261021161052 | nplus_motorace_schema | No |
| 20261021161109 | nplus_motorace_rpc | No |
| 20261021161129 | nplus_aviator_schema | No |
| 20261021161143 | nplus_aviator_rpc | No |
| 20261021161152 | nplus_aviator_worker_recovery | No |
| 20261021161206 | nplus_aviator_persistent_scheduler | No |
| 20261021161217 | nplus_admin_user_tools | No |
| 20261021161233 | nplus_admin_game_status | No |
| 20261021161242 | nplus_admin_null_profile_guard | No |
| 20261021161251 | nplus_recent_demo_activity | No |
| 20261021162503 | post_rollout_revoke_phone_enumeration | No |
| 20261021162645 | enable_server_backed_virtual_demo_games | No |
| 20261022055326 | 20261021182718_nplus_server_settlement_foundation | No |
| 20261022055330 | 20261021182719_nplus_motorace_schema | No |
| 20261022055334 | 20261021182720_nplus_motorace_rpc | No |
| 20261022055340 | 20261021182721_nplus_aviator_schema | No |
| 20261022055345 | 20261021182722_nplus_aviator_rpc | No |
| 20261022055350 | 20261021182723_nplus_aviator_worker_recovery | No |
| 20261022055354 | 20261021182724_nplus_aviator_persistent_scheduler | No |
| 20261022055400 | 20261021182725_nplus_admin_user_tools | No |
| 20261022055404 | 20261021182726_nplus_admin_game_status | No |
| 20261022055410 | 20261021182727_nplus_admin_null_profile_guard | No |
| 20261022055424 | 20261021182728_nplus_recent_demo_activity | No |
| 20261022062741 | enable_supported_virtual_demo_games_preview | No |
| 20261022064315 | pause_unverified_games_and_lockdown_settlement_rpcs_20261022 | No |
| 20261023081657 | fix_profiles_rls_admin_login_recursion_20261023 | No |
| 20261023081758 | secure_admin_demo_wallet_adjustment_rpc_20261023 | No |
| 20261023081916 | align_admin_wallet_adjust_rpc_signature_20261023 | No |
| 20261023092858 | optimize_rls_policies_and_foreign_key_indexes_20261023 | Yes |
| 20261023093056 | drop_duplicate_referral_unique_indexes_20261023 | Yes |

## Required before future schema rollout

1. Create and test a fresh isolated database from the repository's migration source; separately restore a private production backup into a second isolated database.
2. Map each live history row to the exact SQL content that was applied, using the deployed migration history, source branches, and current schema. Do not infer equivalence from similar names.
3. Reconcile the four currently tracked but non-matching versioned files, plus the missing 38 live migration records, without executing any historical migration a second time on production.
4. Verify the clean replay ends with the expected schema, positive generic wallet credits blocked, admin RPCs denied to non-admin users, and all six game settings disabled.
5. Only after a tested mapping exists, decide whether the repo should preserve the historical chain or establish a documented baseline. Record any history-repair operations in a separate reviewed procedure.

**Do not run `supabase db push`, rerun historical SQL manually, or merge the old draft migration files into `main` as-is to try to fix this.** Some draft filenames contain an embedded old timestamp as part of the name while the live history has a different applied version; blindly tracking those filenames could cause a duplicate execution.

Current safety state verified separately: the six game settings are disabled, the live positive-credit guard denies arbitrary generic credits, and the two latest cleanup migrations are applied and tracked. This document records metadata only; it does not contain user rows, credentials, or backup contents.
