# N+ PLAY migration replay baseline-drift report — 2026-10-27

## Result

- The private 2026-10-15 dump was restored locally into a new disposable database with owner/ACL restoration enabled. Restore acceptance passed: 5 profiles, 5 wallets, 140 ledger rows, 5 deposit requests, 6 game settings; zero wallet arithmetic mismatches, negative wallets, missing wallet history, or wallet/latest-ledger mismatches; 7 RLS-enabled public tables, 13 policies, and Vault present.
- Exact source fingerprints passed for all 29 captured SQL bodies and the 40-row replay order.
- The initial local replay passed migration bodies 1–38.
- Body 39, `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql`, failed at its first statement because `public.manual_deposits` does not exist in the database cloned from the 2026-10-15 backup.
- Migration body 40 was not run. No migration was skipped. Production was not modified.

## Read-only catalog evidence

A read-only catalog query against the currently connected production project on 2026-10-27 found `public.manual_deposits` present, owned by `postgres`, with RLS enabled, six columns (`id`, `user_id`, `amount`, `utr`, `status`, `created_at`), primary key `manual_deposits_pkey`, foreign key `manual_deposits_user_id_fkey` to `auth.users(id)`, and index `idx_manual_deposits_user_id_fk`.

A read-only search of `supabase_migrations.schema_migrations` found only one captured history body mentioning `manual_deposits`: version `20261023092858`. That body references the table but does not create it. Thus the supplied 2026-10-15 backup baseline and the captured 40-body history do not, by themselves, reconstruct the current production schema. The table was introduced or restored outside the captured 40-body sequence, or the supplied backup predates that schema state. This is a baseline/history gap, not a source fingerprint or SQL syntax issue.

The same read-only catalog review showed broad table-level grants to `anon` and `authenticated` on this legacy table even though RLS is enabled. No production grant changes were made; review the separate PR #20 candidate and the final post-PR #16 browser call paths before any rollout.

## What the QA-only overlay does — and does not prove

`qa/fixtures/replay-baseline/manual-deposits-schema-overlay.sql` is an explicitly QA-only fixture that creates an empty schema-only approximation of the missing relation inside the already-partial local replay database. It copies no production rows and refuses to run against any database other than `nplus_migration_replay_20261026`. The replay runner then guards the fixture marker and table shape before applying captured bodies 39–40.

If the suffix check passes, that shows bodies 39–40 can run against the explicitly reconstructed table shape and that the final-state invariants pass in this local test. **It is not a clean 40-body replay from the 2026-10-15 dump**, and it does not reconstruct the table's previous RLS policy definitions or prove full restore parity.

## Required release decision

Keep the application **not release-ready** until an authoritative baseline/history for `manual_deposits` is obtained and the schema lineage is resolved. Prefer a verified newer backup that includes the relation, or an approved canonical pre-history schema migration/source with owner, ACL, constraints and policy provenance reviewed. Do not edit the captured applied-body fingerprints, skip body 39, insert fake migration-history rows, run the QA fixture in production, or change production wallets, user data, game flags, grants or cron jobs as a shortcut.
