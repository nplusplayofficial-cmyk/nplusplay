# N+ PLAY — Migration reconciliation evidence and remaining gates

**Checked:** 2026-10-23  
**Environment:** live Supabase project `pcrxlqduygvzchzxsmdv`; GitHub `main` plus available audit/release branches.  
**Safety:** read-only live catalog/history inspection only. No production migration, grant, table, wallet, or game-setting changes were made for this report.

## Executive result

Migration reconciliation is **not complete yet**. The investigation completed the available source discovery and refreshed the live schema snapshot. Two of the 40 migration records have exact version/name files in `main`; five historical SQL sources could not be found in the repository/available branch trees; five more records have ambiguous source candidates; and the remaining 28 have a candidate/path, but no evidence proving that the exact SQL currently in Git is the SQL that production executed.

The private 2026-10-15 backup was previously restored successfully into a separate local database, according to the existing local restore-lab transcript. That is useful restore evidence, but it was a **partial-fidelity restore** because `--no-owner --no-acl` was used. It does not close the migration-history reconciliation or prove a complete disaster-recovery restore.

## 1. Live migration-history snapshot

The current Supabase migration listing still reports **40 rows**:

- `main/supabase/migrations/` has six files.
- Exact version/name file matches: **2** — the two 2026-10-23 cleanup migrations.
- No exact SQL source found in checked repository/branch trees: **5**.
- Source candidates are ambiguous: **5**.
- Candidate/source path found, but exact applied SQL remains unproven: **28**.

The source map contains the row-by-row version/name/source notes:
[`SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md`](./SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md)  
The earlier full live listing is also recorded in:
[`SUPABASE-LIVE-MIGRATION-DRIFT-2026-10-23.md`](./SUPABASE-LIVE-MIGRATION-DRIFT-2026-10-23.md).

### Five historical SQL sources still missing

| Live version | Recorded migration name |
|---|---|
| `20261020162640` | `temporarily_pause_games_until_authoritative_backend_rollout` |
| `20261020162811` | `null_safe_admin_rpc_authorization_guard` |
| `20261021162645` | `enable_server_backed_virtual_demo_games` |
| `20261022062741` | `enable_supported_virtual_demo_games_preview` |
| `20261022064315` | `pause_unverified_games_and_lockdown_settlement_rpcs_20261022` |

The migration-list API returns version/name metadata, not the original SQL body. These names were also searched against available repository branches and prior project notes; no exact file/body was found. The similarly named current scripts are not acceptable replacements without proof of equivalence.

### Important candidate/ambiguity examples

- `20261020135823 block_generic_wallet_credits_before_game_rpc_deployment`: a `POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql` candidate exists, but the historical name and the script's rollout preconditions do not prove it is the same executed SQL.
- `20261021160917 nplus_vip_referral_demo`: the SQL and migration candidates in the repository have different contents/hashes; choose neither until the deployed source is recovered.
- `20261021161217 nplus_admin_user_tools` and `20261021161242 nplus_admin_null_profile_guard`: candidate file copies differ, so the executed content remains ambiguous.
- `20261021161152 nplus_aviator_worker_recovery`, `20261021161206 nplus_aviator_persistent_scheduler`, and `20261021161251 nplus_recent_demo_activity`: candidate sources are available in a draft branch, but the migration-list output does not prove byte-for-byte identity with the deployed SQL.
- Versions `20261022055326` through `20261022055424` record a later series whose names embed earlier migration filenames. That shows a repeated application/history event, not proof that a single copy can safely be replayed twice.

## 2. Fresh read-only live-schema snapshot

A new read-only SQL query was executed against the live project on 2026-10-23. It confirmed:

- Migration-history row count remains **40**.
- The expected current objects exist: `game_settings`; WINGO, MotoRace and Aviator round/bet tables; Aviator worker health; demo referral codes/referrals; `user_preferences`; `deposit_requests`; and `withdrawal_requests`.
- All six game-setting rows are disabled: `WINGO`, `K3`, `5D`, `TRX`, `MOTO`, `AVIATOR`.
- `nplus_phone_is_registered(text)` has no `anon` or `authenticated` EXECUTE privilege in the current snapshot.
- `nplus_wallet_change(numeric,text,text,text)` is not executable by `anon`; the current ACL still permits `authenticated` EXECUTE, so its internal positive-credit/authorization guard remains an important control.
- Both `nplus_admin_set_wingo_demo` overloads (four-argument and five-argument) exist; `anon` cannot execute them, while `authenticated` has EXECUTE privilege subject to the function's internal admin guard. The overlapping four-argument call remains a known signature-ambiguity cleanup item after migration reconciliation.

**Interpretation:** object presence and current settings are verified; they do not prove the original SQL for each historical version or show that a clean migration chain recreates this schema.

## 3. Existing private backup / restore-lab evidence

The existing local transcript records the backup at:

`C:\\Users\\Natarajan K\\NPLUS-PLAY-DB-BACKUP\\nplus-play-full-2026-10-15.dump`

Recorded archive checks:

- Size: 444,426 bytes.
- PostgreSQL custom archive, gzip compression, source/pg_dump version 17.11.
- `pg_restore --list` succeeded with 661 TOC entries.
- Backup contains Supabase Auth, Storage, Vault and app objects; keep it private and never commit/upload it to GitHub.

The restore lab created the separate local database `nplus_restore_manual` and ran:

```sh
pg_restore -U supabase_admin -d nplus_restore_manual --no-owner --no-acl --exit-on-error --single-transaction /tmp/nplus-play-backup.dump
```

The existing transcript reports that this command returned without error and that subsequent read-only checks found:

| Restored object/check | Recorded result |
|---|---:|
| Profiles | 5 |
| Wallets | 5 |
| Wallet ledger rows | 140 |
| Deposit requests | 5 |
| Game settings | 6 |
| Ledger arithmetic mismatches | 0 |
| Wallet vs. latest ledger mismatches | 0 |
| Wallets without ledger history | 0 |
| Public tables with RLS enabled | 7 |
| Public RLS policies | 13 |
| Supabase Vault extension present | Yes |

This restore evidence is from the saved local restore-lab transcript; the backup file itself is not mounted in this session and the restore was **not rerun here**.

### Restore-test limitation

Because the restore explicitly used `--no-owner --no-acl`, original ownership and ACL/grant restoration were skipped. The local role bootstrap was not proven identical to production. The test demonstrates that the backup can be restored into a separate database and that selected wallet-ledger integrity checks pass; it does **not** prove production-faithful owners, grants, all RLS semantics, auth-provider settings, or post-2026-10-15 migrations.

## 4. Why this cannot responsibly be marked complete yet

A canonical migration chain must be proven, not inferred from matching names or final objects. Production has 40 history records, including repeated application events; the available repository source does not uniquely identify the exact SQL for every record. Inventing replacement SQL or empty/no-op migrations would conceal the gap, while replaying candidate SQL in production could alter game locks, RPC privileges, wallet paths, or user-facing behavior.

No migration-history repair or production SQL mutation should be performed to make the file count match.

## 5. Remaining steps to close the reconciliation safely

1. Recover the original applied SQL for the five missing rows and resolve each ambiguous/candidate row from a trusted source (local `release-audit` working tree, PowerShell/transcript files, Supabase SQL Editor history/export, or controlled deployment logs). Record source file/blob hash and evidence for equivalence per version.
2. Reconcile the duplicate/repeated execution records and determine whether each repeat was intentional/idempotent. Do not replay one source twice merely because the history has two similarly named rows.
3. Build a disposable Supabase-compatible stack from the proposed canonical migration chain. Separately restore the private backup in an isolated test database. Do not upload the backup.
4. Compare resulting schema objects, policies, grants, function definitions, triggers, indexes and settings against the read-only live snapshot. Test the wallet-credit guard and non-admin RPC denial in the disposable environment.
5. Only after those tests pass, document a separate reviewed migration-history repair/baseline plan. Do not run `supabase db push`, rerun the historic SQL on production, or modify `supabase_migrations.schema_migrations` as a shortcut.

**Final status: backup data restore — partially validated; live schema/object snapshot — refreshed; migration source reconciliation and canonical clean replay — still blocked by missing/ambiguous historical SQL.**
