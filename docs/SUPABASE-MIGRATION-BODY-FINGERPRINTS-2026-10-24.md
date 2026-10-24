# Supabase applied-migration body fingerprints — 2026-10-24

## Scope and safety

Read-only verification against the NPLUS-PLAY Supabase project `pcrxlqduygvzchzxsmdv` on 2026-10-24. The query read `supabase_migrations.schema_migrations` and returned only each row's version/name, statement count, body length, MD5 fingerprint, and count of rows with the same fingerprint. It did not return or write SQL bodies.

No schema, migration-history row, wallet, user record, game setting, grant, or production object was changed.

Fingerprint formula:

```sql
md5(array_to_string(statements, E'\\n'))
```

The hash is a comparison aid, not a security signature. Identical hashes and lengths are evidence of matching stored statement text for this query; they do not prove that replaying the statement is safe.

## Live history summary

- Applied migration-history rows: **40**
- Rows with exactly one stored statement: **40**
- Distinct stored SQL-body fingerprints: **29**
- Duplicate-body rows beyond the first copy: **11** (11 pairs; 22 rows total)
- Production game settings at the last read-only catalog check (2026-10-23): all six disabled — WINGO, K3, 5D, TRX, MOTO, AVIATOR.

## Per-row fingerprints

| Version | Recorded name | Body chars | MD5 fingerprint | Rows with same body |
|---|---|---:|---|---:|
| 20261020135823 | block_generic_wallet_credits_before_game_rpc_deployment | 2371 | 2850de2e52763443e12cf336e5bda002 | 1 |
| 20261020162640 | temporarily_pause_games_until_authoritative_backend_rollout | 490 | 370856a6454d23c768ad1cb871ce1a3d | 1 |
| 20261020162811 | null_safe_admin_rpc_authorization_guard | 24321 | 9f8b84431d2717292fbe528cab6a2e4a | 1 |
| 20261021155813 | admin_game_status_fail_closed_guard | 3554 | c9b30fb18008b9b8b3d61fe3bdbb0c25 | 1 |
| 20261021160439 | account_preferences_release_support | 2112 | 670231ad75fadaf0d55a6791ec4c70a4 | 1 |
| 20261021160443 | demo_wallet_requests_release_support | 8761 | 0683f8ea730b1861ac71ff63c1181609 | 1 |
| 20261021160446 | admin_deposit_actions_release_support | 3998 | 425287208f2add7902d084748980f7e8 | 1 |
| 20261021160503 | demo_referrals_base_release_support | 11935 | dac41d2de70765aaa230e5fec8d172e1 | 1 |
| 20261021160917 | nplus_vip_referral_demo | 53258 | e09b3db6a2adce61c3d587a7f0856941 | 1 |
| 20261021160935 | nplus_server_settlement_foundation | 24127 | 0f401164b791555350fe667adf579821 | 2 |
| 20261021161052 | nplus_motorace_schema | 2036 | 4757f2cab064399bd17135c5cba3bd1f | 2 |
| 20261021161109 | nplus_motorace_rpc | 14999 | 62ddf12081dde7f41ed2c330536ba4fe | 2 |
| 20261021161129 | nplus_aviator_schema | 2592 | 35729c3cbfc089da87d9dab49a0bef30 | 2 |
| 20261021161143 | nplus_aviator_rpc | 21231 | e7f9ea285515cbfc7d9722219795569e | 2 |
| 20261021161152 | nplus_aviator_worker_recovery | 15522 | f9eb22c6ab349c747f221c3edb544397 | 2 |
| 20261021161206 | nplus_aviator_persistent_scheduler | 1172 | aafd879eb774f25765595c1b13369210 | 2 |
| 20261021161217 | nplus_admin_user_tools | 5989 | f071a5385b87239b255b91a28e700c60 | 2 |
| 20261021161233 | nplus_admin_game_status | 2004 | d98bd9344d6591971ca3212007cf3967 | 2 |
| 20261021161242 | nplus_admin_null_profile_guard | 25576 | baf2caaf9cd8ec227319ae43ecc08eb0 | 2 |
| 20261021161251 | nplus_recent_demo_activity | 1530 | 4ac4a9427f9f47145197da5e1068ba0d | 2 |
| 20261021162503 | post_rollout_revoke_phone_enumeration | 1115 | 71e8ad4581449eb4aea6c321315bfc46 | 1 |
| 20261021162645 | enable_server_backed_virtual_demo_games | 1050 | 4354d93ff2b85cc37c047afc263e35c5 | 1 |
| 20261022055326 | 20261021182718_nplus_server_settlement_foundation | 24127 | 0f401164b791555350fe667adf579821 | 2 |
| 20261022055330 | 20261021182719_nplus_motorace_schema | 2036 | 4757f2cab064399bd17135c5cba3bd1f | 2 |
| 20261022055334 | 20261021182720_nplus_motorace_rpc | 14999 | 62ddf12081dde7f41ed2c330536ba4fe | 2 |
| 20261022055340 | 20261021182721_nplus_aviator_schema | 2592 | 35729c3cbfc089da87d9dab49a0bef30 | 2 |
| 20261022055345 | 20261021182722_nplus_aviator_rpc | 21231 | e7f9ea285515cbfc7d9722219795569e | 2 |
| 20261022055350 | 20261021182723_nplus_aviator_worker_recovery | 15522 | f9eb22c6ab349c747f221c3edb544397 | 2 |
| 20261022055354 | 20261021182724_nplus_aviator_persistent_scheduler | 1172 | aafd879eb774f25765595c1b13369210 | 2 |
| 20261022055400 | 20261021182725_nplus_admin_user_tools | 5989 | f071a5385b87239b255b91a28e700c60 | 2 |
| 20261022055404 | 20261021182726_nplus_admin_game_status | 2004 | d98bd9344d6591971ca3212007cf3967 | 2 |
| 20261022055410 | 20261021182727_nplus_admin_null_profile_guard | 25576 | baf2caaf9cd8ec227319ae43ecc08eb0 | 2 |
| 20261022055424 | 20261021182728_nplus_recent_demo_activity | 1530 | 4ac4a9427f9f47145197da5e1068ba0d | 2 |
| 20261022062741 | enable_supported_virtual_demo_games_preview | 4525 | 3832fd6a90faed6f292ab4650a2f29c2 | 1 |
| 20261022064315 | pause_unverified_games_and_lockdown_settlement_rpcs_20261022 | 872 | 4265e6ddcf88987f1f0ea85a4d4ea516 | 1 |
| 20261023081657 | fix_profiles_rls_admin_login_recursion_20261023 | 547 | a685847a88eec5470fa7e9c4295986fb | 1 |
| 20261023081758 | secure_admin_demo_wallet_adjustment_rpc_20261023 | 3059 | 4ffc0b1a970bcc33698300f66a6c3cb5 | 1 |
| 20261023081916 | align_admin_wallet_adjust_rpc_signature_20261023 | 3040 | 14cb2a06f11f7f94712d1a49faa9a0ec | 1 |
| 20261023092858 | optimize_rls_policies_and_foreign_key_indexes_20261023 | 5177 | 26f384c480ba6353c749f5cd8adb6da9 | 1 |
| 20261023093056 | drop_duplicate_referral_unique_indexes_20261023 | 284 | 5660665b15239a33df937e709ee86fd3 | 1 |

## Exact duplicate-body groups

These pairs have equal body length and matching MD5 fingerprints in the read-only snapshot:

- `20261021160935` / `20261022055326` — server settlement foundation
- `20261021161052` / `20261022055330` — MotoRace schema
- `20261021161109` / `20261022055334` — MotoRace RPC
- `20261021161129` / `20261022055340` — Aviator schema
- `20261021161143` / `20261022055345` — Aviator RPC
- `20261021161152` / `20261022055350` — Aviator worker recovery
- `20261021161206` / `20261022055354` — persistent scheduler
- `20261021161217` / `20261022055400` — Admin user tools
- `20261021161233` / `20261022055404` — Admin game status
- `20261021161242` / `20261022055410` — Admin null-profile guard
- `20261021161251` / `20261022055424` — recent demo activity

## What this evidence closes — and does not close

**Closed by this read-only pass:** current history count, one-statement-per-row count, per-row body fingerprints, and exact duplicate-body groups.

**Not closed:**

1. Every live body must still be mapped to a reviewed canonical source file. Some current `main` source files differ from the applied body even when filenames/versions are similar; refer to the source-map report below.
2. Repeated bodies require an explicit ordered replay-safety review. Matching fingerprints do not prove idempotence.
3. No clean replay of a canonical migration chain has been run in an isolated PostgreSQL/Supabase-compatible database in this session.
4. The private backup `nplus-play-full-2026-10-15.dump` is on the user's Windows workstation and is not mounted in this runtime. It must remain private and must not be uploaded to GitHub.
5. Previous local restore evidence used `--no-owner --no-acl`. A second restore preserving ownership and ACLs, and comparing grants/RLS/functions/triggers/indexes/state, is still required.

## References

- [Migration reconciliation status](./SUPABASE-MIGRATION-RECONCILIATION-STATUS-2026-10-23.md)
- [Per-version migration source map](./SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md)
- [Live migration drift report](./SUPABASE-LIVE-MIGRATION-DRIFT-2026-10-23.md)

**Work #1 remains OPEN until clean replay and production-faithful backup restore are actually executed and pass.** 
