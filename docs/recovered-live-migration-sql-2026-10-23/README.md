# Recovered live-migration SQL evidence — 2026-10-23

## Important: this is an evidence archive, not a migration directory

The 29 SQL files in this folder are source snapshots used to reconcile the live Supabase migration history. They are **not** a reviewed canonical migration chain. Do not execute them, copy them into `supabase/migrations`, or run `supabase db push` based on this folder alone.

The snapshots were recovered from the current repository candidates and a read-only comparison against stored SQL bodies in `supabase_migrations.schema_migrations`. Per-version evidence and body fingerprints are in:

- `../SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md`
- `../SUPABASE-MIGRATION-RECONCILIATION-STATUS-2026-10-23.md`
- `../SUPABASE-MIGRATION-BODY-FINGERPRINTS-2026-10-24.md`

## Why 29 files represent 40 applied history rows

The live history had 40 rows and 29 distinct SQL bodies at the last read-only snapshot. Eleven pairs of rows contain the same SQL body. A replay plan must preserve the original 40-row order and decide whether each duplicate execution is safe to repeat; deduplicating history or re-running a snapshot on production is not an acceptable shortcut.

Exact repeated-body pairs:

| First applied version | Repeat version |
|---|---|
| 20261021160935 | 20261022055326 |
| 20261021161052 | 20261022055330 |
| 20261021161109 | 20261022055334 |
| 20261021161129 | 20261022055340 |
| 20261021161143 | 20261022055345 |
| 20261021161152 | 20261022055350 |
| 20261021161206 | 20261022055354 |
| 20261021161217 | 20261022055400 |
| 20261021161233 | 20261022055404 |
| 20261021161242 | 20261022055410 |
| 20261021161251 | 20261022055424 |

## Required gates before canonicalization

1. Review every source/hash mapping, execution order, role/extension prerequisite, and precondition in the source map.
2. Decide and document duplicate-body replay safety.
3. Replay the reviewed sequence in a fresh disposable Supabase-compatible PostgreSQL environment.
4. Separately restore the private 2026-10-15 backup with original owners and ACLs preserved; compare wallet/ledger integrity, objects, policies, grants and game settings.
5. Compare the resulting clean schema to the read-only production snapshot.
6. Only then create canonical migration files/history repair proposal. Never modify production history to make counts match.

The private backup is not included in this folder or repository. It may contain authentication, wallet and Vault data and must remain on the user's private workstation.
