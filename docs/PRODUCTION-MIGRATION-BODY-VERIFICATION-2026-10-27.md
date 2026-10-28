# Production migration body verification — 2026-10-27

## Result

**All 29 distinct SQL bodies stored in the active production migration history were compared character-for-character against 29 SQL files in the integration candidate's `docs/recovered-live-migration-sql-2026-10-23/` archive. All 29 comparisons were exact matches.** The production history has 40 rows: 11 later rows repeat an earlier body exactly, so all 40 history rows are mapped to 29 unique applied SQL bodies.

This closes the historical-body *availability and exact-match* gap for the 40 recorded rows. It does **not** prove the clean migration replay or pre-history schema baseline is complete.

## Method

- Used read-only SELECT against `supabase_migrations.schema_migrations` for `version`, `name`, and `array_to_string(statements, E'\\n')`.
- Compared that joined stored body to the archived candidate file content as raw strings. For every row below: character counts matched and the string equality check returned true.
- `body_md5` is PostgreSQL `md5(array_to_string(statements, E'\\n'))`, recorded to make the live-body snapshot auditable. It is a fingerprint, not a signature.
- No SQL migration was executed; no database rows, functions, grants, RLS, wallets, game settings, Auth or scheduler configuration were modified.

## The 29 exact unique-body matches

| Live version | Live migration name | Body characters | Live body MD5 | Exact-matching archived file |
|---|---|---:|---|---|
| 20261020135823 | block_generic_wallet_credits_before_game_rpc_deployment | 2,371 | `2850de2e52763443e12cf336e5bda002` | `docs/recovered-live-migration-sql-2026-10-23/20261020135823_block_generic_wallet_credits_before_game_rpc_deployment.sql` |
| 20261020162640 | temporarily_pause_games_until_authoritative_backend_rollout | 490 | `370856a6454d23c768ad1cb871ce1a3d` | `docs/recovered-live-migration-sql-2026-10-23/20261020162640_temporarily_pause_games_until_authoritative_backend_rollout.sql` |
| 20261020162811 | null_safe_admin_rpc_authorization_guard | 24,321 | `9f8b84431d2717292fbe528cab6a2e4a` | `docs/recovered-live-migration-sql-2026-10-23/20261020162811_null_safe_admin_rpc_authorization_guard.sql` |
| 20261021155813 | admin_game_status_fail_closed_guard | 3,554 | `c9b30fb18008b9b8b3d61fe3bdbb0c25` | `docs/recovered-live-migration-sql-2026-10-23/20261021155813_admin_game_status_fail_closed_guard.sql` |
| 20261021160439 | account_preferences_release_support | 2,112 | `670231ad75fadaf0d55a6791ec4c70a4` | `docs/recovered-live-migration-sql-2026-10-23/20261021160439_account_preferences_release_support.sql` |
| 20261021160443 | demo_wallet_requests_release_support | 8,761 | `0683f8ea730b1861ac71ff63c1181609` | `docs/recovered-live-migration-sql-2026-10-23/20261021160443_demo_wallet_requests_release_support.sql` |
| 20261021160446 | admin_deposit_actions_release_support | 3,998 | `425287208f2add7902d084748980f7e8` | `docs/recovered-live-migration-sql-2026-10-23/20261021160446_admin_deposit_actions_release_support.sql` |
| 20261021160503 | demo_referrals_base_release_support | 11,935 | `dac41d2de70765aaa230e5fec8d172e1` | `docs/recovered-live-migration-sql-2026-10-23/20261021160503_demo_referrals_base_release_support.sql` |
| 20261021160917 | nplus_vip_referral_demo | 53,258 | `e09b3db6a2adce61c3d587a7f0856941` | `docs/recovered-live-migration-sql-2026-10-23/20261021160917_nplus_vip_referral_demo.sql` |
| 20261021160935 | nplus_server_settlement_foundation | 24,127 | `0f401164b791555350fe667adf579821` | `docs/recovered-live-migration-sql-2026-10-23/20261021160935_nplus_server_settlement_foundation.sql` |
| 20261021161052 | nplus_motorace_schema | 2,036 | `4757f2cab064399bd17135c5cba3bd1f` | `docs/recovered-live-migration-sql-2026-10-23/20261021161052_nplus_motorace_schema.sql` |
| 20261021161109 | nplus_motorace_rpc | 14,999 | `62ddf12081dde7f41ed2c330536ba4fe` | `docs/recovered-live-migration-sql-2026-10-23/20261021161109_nplus_motorace_rpc.sql` |
| 20261021161129 | nplus_aviator_schema | 2,592 | `35729c3cbfc089da87d9dab49a0bef30` | `docs/recovered-live-migration-sql-2026-10-23/20261021161129_nplus_aviator_schema.sql` |
| 20261021161143 | nplus_aviator_rpc | 21,231 | `e7f9ea285515cbfc7d9722219795569e` | `docs/recovered-live-migration-sql-2026-10-23/20261021161143_nplus_aviator_rpc.sql` |
| 20261021161152 | nplus_aviator_worker_recovery | 15,522 | `f9eb22c6ab349c747f221c3edb544397` | `docs/recovered-live-migration-sql-2026-10-23/20261021161152_nplus_aviator_worker_recovery.sql` |
| 20261021161206 | nplus_aviator_persistent_scheduler | 1,172 | `aafd879eb774f25765595c1b13369210` | `docs/recovered-live-migration-sql-2026-10-23/20261021161206_nplus_aviator_persistent_scheduler.sql` |
| 20261021161217 | nplus_admin_user_tools | 5,989 | `f071a5385b87239b255b91a28e700c60` | `docs/recovered-live-migration-sql-2026-10-23/20261021161217_nplus_admin_user_tools.sql` |
| 20261021161233 | nplus_admin_game_status | 2,004 | `d98bd9344d6591971ca3212007cf3967` | `docs/recovered-live-migration-sql-2026-10-23/20261021161233_nplus_admin_game_status.sql` |
| 20261021161242 | nplus_admin_null_profile_guard | 25,576 | `baf2caaf9cd8ec227319ae43ecc08eb0` | `docs/recovered-live-migration-sql-2026-10-23/20261021161242_nplus_admin_null_profile_guard.sql` |
| 20261021161251 | nplus_recent_demo_activity | 1,530 | `4ac4a9427f9f47145197da5e1068ba0d` | `docs/recovered-live-migration-sql-2026-10-23/20261021161251_nplus_recent_demo_activity.sql` |
| 20261021162503 | post_rollout_revoke_phone_enumeration | 1,115 | `71e8ad4581449eb4aea6c321315bfc46` | `docs/recovered-live-migration-sql-2026-10-23/20261021162503_post_rollout_revoke_phone_enumeration.sql` |
| 20261021162645 | enable_server_backed_virtual_demo_games | 1,050 | `4354d93ff2b85cc37c047afc263e35c5` | `docs/recovered-live-migration-sql-2026-10-23/20261021162645_enable_server_backed_virtual_demo_games.sql` |
| 20261022062741 | enable_supported_virtual_demo_games_preview | 4,525 | `3832fd6a90faed6f292ab4650a2f29c2` | `docs/recovered-live-migration-sql-2026-10-23/20261022062741_enable_supported_virtual_demo_games_preview.sql` |
| 20261022064315 | pause_unverified_games_and_lockdown_settlement_rpcs_20261022 | 872 | `4265e6ddcf88987f1f0ea85a4d4ea516` | `docs/recovered-live-migration-sql-2026-10-23/20261022064315_pause_unverified_games_and_lockdown_settlement_rpcs_20261022.sql` |
| 20261023081657 | fix_profiles_rls_admin_login_recursion_20261023 | 547 | `a685847a88eec5470fa7e9c4295986fb` | `docs/recovered-live-migration-sql-2026-10-23/20261023081657_fix_profiles_rls_admin_login_recursion_20261023.sql` |
| 20261023081758 | secure_admin_demo_wallet_adjustment_rpc_20261023 | 3,059 | `4ffc0b1a970bcc33698300f66a6c3cb5` | `docs/recovered-live-migration-sql-2026-10-23/20261023081758_secure_admin_demo_wallet_adjustment_rpc_20261023.sql` |
| 20261023081916 | align_admin_wallet_adjust_rpc_signature_20261023 | 3,040 | `14cb2a06f11f7f94712d1a49faa9a0ec` | `docs/recovered-live-migration-sql-2026-10-23/20261023081916_align_admin_wallet_adjust_rpc_signature_20261023.sql` |
| 20261023092858 | optimize_rls_policies_and_foreign_key_indexes_20261023 | 5,177 | `26f384c480ba6353c749f5cd8adb6da9` | `docs/recovered-live-migration-sql-2026-10-23/20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql` |
| 20261023093056 | drop_duplicate_referral_unique_indexes_20261023 | 284 | `5660665b15239a33df937e709ee86fd3` | `docs/recovered-live-migration-sql-2026-10-23/20261023093056_drop_duplicate_referral_unique_indexes_20261023.sql` |

## The 11 repeated history rows

| Repeated live version | Stored name | Exact unique body it repeats | Comparison |
|---|---|---|---|
| 20261022055326 | 20261021182718_nplus_server_settlement_foundation | `20261021160935` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055330 | 20261021182719_nplus_motorace_schema | `20261021161052` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055334 | 20261021182720_nplus_motorace_rpc | `20261021161109` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055340 | 20261021182721_nplus_aviator_schema | `20261021161129` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055345 | 20261021182722_nplus_aviator_rpc | `20261021161143` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055350 | 20261021182723_nplus_aviator_worker_recovery | `20261021161152` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055354 | 20261021182724_nplus_aviator_persistent_scheduler | `20261021161206` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055400 | 20261021182725_nplus_admin_user_tools | `20261021161217` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055404 | 20261021182726_nplus_admin_game_status | `20261021161233` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055410 | 20261021182727_nplus_admin_null_profile_guard | `20261021161242` | Exact same stored-body MD5/content as the referenced unique body |
| 20261022055424 | 20261021182728_nplus_recent_demo_activity | `20261021161251` | Exact same stored-body MD5/content as the referenced unique body |

For those 11 rows, the read-only production listing reports the same body character count and MD5 as the earlier referenced unique version. This is evidence of repeated body application in history, not a reason to execute the statements twice again during a new replay. The replay plan must explicitly examine duplicate ordering/idempotency.

## Remaining canonical replay blocker: three legacy relations

The current production catalog confirms these relations exist and has RLS enabled:

- `public.manual_deposits`
- `public.user_bank_details`
- `public.withdraw_requests`

The 40 live migration bodies were scanned. Only `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023` mentions these relations, and that body does not create them. None of the 29 distinct migration bodies contains a CREATE TABLE for any of the three relations. The supplied 2026-10-15 backup-derived replay baseline lacks them.

Therefore the current schema comes from a pre-history/baseline SQL operation or a schema deployment not captured by these 40 rows. The current live schema snapshot records today's columns, constraints, indexes, owner, RLS policies and ACLs, but cannot prove their historical origin or original grants/policies. A clean canonical replay still requires trusted original baseline DDL/deployment evidence with provenance; do not synthesize it from today's shape, treat the QA-only overlay as canonical, or patch migration history.

Related evidence:
- [Current legacy-table schema snapshot](./PRODUCTION-LEGACY-TABLE-SCHEMA-SNAPSHOT-2026-10-27.md)
- [Replay baseline drift report](./REPLAY-BASELINE-DRIFT-2026-10-27.md)
- [Migration source map](./SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md)

## Release status

- Exact SQL body mapping for the 40 recorded migration-history rows: **PASS (read-only exact comparison; 29 unique bodies + 11 repeated bodies)**.
- Clean canonical replay from the supplied backup without QA overlays: **BLOCKED** by the three missing legacy relations and their historical provenance.
- Hosted auth/admin/wallet/referral user journeys: **PENDING** safe synthetic accounts and OTP inbox access.
- No production migration/deployment is authorized by this evidence.
