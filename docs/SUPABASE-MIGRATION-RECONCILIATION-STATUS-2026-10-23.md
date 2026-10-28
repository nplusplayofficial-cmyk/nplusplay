# Supabase migration reconciliation status — 2026-10-23

## Decision

**Work #1 is still OPEN. Do not run migrations or alter production history.**

This status is an audit-only record for Supabase project pcrxlqduygvzchzxsmdv. The work described here used read-only live SQL queries and GitHub writes only to the audit branch. No production schema, migration rows, wallet entries, game settings, or user data were changed.

## Verified now

- Live migration history contains 40 rows; each row has one stored SQL statement in supabase_migrations.schema_migrations.statements.
- A read-only SQL summary produced 29 distinct SQL bodies and 11 repeated exact-body entries.
- Full stored-body comparison confirmed exact SQL matches for a substantial subset of repository candidates and identified mismatches in several main-branch scripts. Per-version evidence is in SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md.
- Previously unlocated SQL for temporarily_pause_games_until_authoritative_backend_rollout, enable_server_backed_virtual_demo_games, enable_supported_virtual_demo_games_preview, and pause_unverified_games_and_lockdown_settlement_rpcs_20261022 was recovered from the live applied-body history and archived under docs/recovered-live-migration-sql-2026-10-23/ on this branch. The null_safe_admin_rpc_authorization_guard body exactly matches the existing sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql source.
- All six game settings remain disabled: WINGO, K3, 5D, TRX, MOTO, AVIATOR.
- Current catalog snapshot was previously read-only verified as 33 public tables, 69 public functions, 2 non-internal public triggers, and 22 public RLS policies.

## What is not proven yet

1. Exact source comparison is not closed for every one of the 40 rows. Some checked-in files are different lengths/content from the live body, even when version/name looks aligned.
2. Duplicate applied-body pairs are identified but each operation still needs an idempotency and replay-safety review.
3. The clean canonical migration chain has not been replayed on a fresh disposable PostgreSQL/Supabase-compatible database.
4. The private 2026-10-15 backup has not passed a restore acceptance test preserving owner and ACL/grant behavior. The earlier restore transcript used --no-owner --no-acl, so it does not meet this acceptance gate.
5. Wallet positive-credit guard, non-admin RPC-denial checks, schema/object comparisons, and final-state equivalence still need executable replay/restore evidence.

## Safe next steps

1. Keep this work on the audit branch. Do not merge recovered files into main or supabase/migrations until a canonical sequence is reviewed.
2. Use the existing local restore lab and private dump, never GitHub, for backup testing. Restore into a new isolated local database, not production or the existing manual restore database.
3. Provision required roles/extensions in that isolated environment and run the restore without suppressing ownership/ACL errors. Record redacted output and compare tables, functions, triggers, policies, indexes, grants, and game settings.
4. Build a clean disposable database from the proposed migration sequence and test it separately from the restored backup. Check replay errors, positive wallet-credit blocking, and non-admin RPC denials.
5. Only after all gates pass, propose a separate migration-history repair plan. Do not use supabase db push, production replay, history edits, no-op migrations, or production resets as a shortcut.

## Cost and data safety

No Supabase development branch/project was created in this audit because a free/zero-cost isolated environment was not confirmed. The backup must remain private and must not be committed to the repository. Do not expose credentials or live user rows in audit artifacts.

## Evidence links

- Source map and per-version applied-SQL comparisons: https://github.com/nplusplayofficial-cmyk/nplusplay/blob/audit/supabase-migration-history-map-2026-10-23/docs/SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md
- Recovered live SQL evidence directory: https://github.com/nplusplayofficial-cmyk/nplusplay/tree/audit/supabase-migration-history-map-2026-10-23/docs/recovered-live-migration-sql-2026-10-23/

**Final status: source recovery substantially improved; replay/restore acceptance remains blocked. Work #1 must not be marked complete yet.**


## Additional duplicate-body review

A text-pattern triage of the 11 exact duplicate body pairs did not find unguarded table/index creation, add-constraint/add-column, INSERT, UPDATE, or DELETE patterns in those bodies. This does not prove idempotency or replay safety; a clean disposable replay remains mandatory.


## 2026-10-27 read-only live-body reconciliation update

The 2023 source counts and the Missing/Ambiguous labels in the historical sections above are superseded for **SQL bodies recorded in migration history** by a new direct comparison of production-stored SQL bodies to the integration branch's archived recovered SQL files.

- Directly read `supabase_migrations.schema_migrations.statements` using SELECT only.
- Exact character-for-character match: **29 / 29 distinct applied bodies** against the archived SQL files. All character counts matched; production-side MD5 fingerprints and source paths are documented in [PRODUCTION-MIGRATION-BODY-VERIFICATION-2026-10-27.md](./PRODUCTION-MIGRATION-BODY-VERIFICATION-2026-10-27.md).
- The 40 migration-history rows comprise the 29 distinct bodies plus 11 repeats that have an exact body fingerprint match to an earlier row.
- The five SQL bodies previously labelled missing are now located and exact-matched to the production-stored bodies; the previously ambiguous VIP referral, Admin user-tools and null-profile-guard bodies are also resolved against the archived bodies.

**Still open:** clean canonical replay / disaster-recovery parity. The 40 applied SQL bodies never create `manual_deposits`, `user_bank_details` or `withdraw_requests`; only the later index/policy optimization body references them. The supplied 2026-10-15 backup-derived baseline lacks these relations. Their authoritative pre-history DDL, provenance and historical policies/ACLs are still missing, so do not invent a migration or mark replay complete. No production changes were made.
