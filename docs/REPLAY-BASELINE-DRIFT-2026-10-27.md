# N+ PLAY migration replay baseline-drift report — 2026-10-27

## Result

- The private 2026-10-15 dump was restored locally into a new disposable database with owner/ACL restoration enabled. Restore acceptance passed: 5 profiles, 5 wallets, 140 ledger rows, 5 deposit requests, 6 game settings; zero wallet arithmetic mismatches, negative wallets, missing wallet history, or wallet/latest-ledger mismatches; 7 RLS-enabled public tables, 13 policies, and Vault present.
- Exact source fingerprints passed for all 29 captured SQL bodies and the 40-row replay order.
- The initial local replay passed migration bodies 1–38.
- Body 39, `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql`, first failed at `public.manual_deposits`. A read-only guarded QA overlay attempt then detected a second missing relation, `public.withdraw_requests`, before creating any fixture objects. Both relations are missing from the backup-derived partial replay baseline; the overlay transaction was rejected and no migration 39/40 was resumed by that attempt.
- Migration body 40 has not been run. No migration was skipped. Production was not modified.

## Read-only catalog evidence

Read-only catalog queries against the currently connected production project on 2026-10-27 found both `public.manual_deposits` and `public.withdraw_requests` present, owned by `postgres`, with RLS enabled. `manual_deposits` has six columns (`id`, `user_id`, `amount`, `utr`, `status`, `created_at`), primary key `manual_deposits_pkey`, foreign key `manual_deposits_user_id_fkey` to `auth.users(id)`, and index `idx_manual_deposits_user_id_fk`. `withdraw_requests` has five columns (`id`, `user_id`, `amount`, `status`, `created_at`), primary key `withdraw_requests_pkey`, foreign key `withdraw_requests_user_id_fkey` to `auth.users(id)`, and index `idx_withdraw_requests_user_id_fk`.

Read-only searches of `supabase_migrations.schema_migrations` found the captured body `20261023092858` mentions each table, but does not create either one. The QA fixture's guard then found `withdraw_requests` absent from the backup-derived replay baseline, before creating either fixture table. Thus the supplied 2026-10-15 backup and captured 40-body history do not, by themselves, reconstruct the current production schema. These relations were introduced/restored outside the captured 40-body sequence, or the supplied backup predates that schema state. This is a baseline/history gap, not a source fingerprint or SQL syntax issue.

The same read-only catalog review showed broad table-level grants to `anon` and `authenticated` on this legacy table even though RLS is enabled. No production grant changes were made; review the separate PR #20 candidate and the final post-PR #16 browser call paths before any rollout.

## What the QA-only overlay does — and does not prove

`qa/fixtures/replay-baseline/manual-deposits-schema-overlay.sql` is an explicitly QA-only fixture intended to create empty schema-only approximations of both missing relations inside the already-partial local replay database. It copies no production rows and refuses to run against any database other than `nplus_migration_replay_20261026`. It also preflights other referenced tables/columns first; the latest attempt stopped at the missing `withdraw_requests` relation before creating anything. The replay runner has a guarded suffix path for versions 39–40 only after the fixture and checkpoint checks pass.

If the suffix check passes, that shows bodies 39–40 can run against the explicitly reconstructed table shape and that the final-state invariants pass in this local test. **It is not a clean 40-body replay from the 2026-10-15 dump**, and it does not reconstruct the table's previous RLS policy definitions or prove full restore parity.

## Required release decision

Keep the application **not release-ready** until an authoritative baseline/history for both `manual_deposits` and `withdraw_requests` is obtained and the schema lineage is resolved. Prefer a verified newer backup that includes the relation, or an approved canonical pre-history schema migration/source with owner, ACL, constraints and policy provenance reviewed. Do not edit the captured applied-body fingerprints, skip body 39, insert fake migration-history rows, run the QA fixture in production, or change production wallets, user data, game flags, grants or cron jobs as a shortcut.
