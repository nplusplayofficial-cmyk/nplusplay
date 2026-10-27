# N+ PLAY migration replay baseline-drift report — 2026-10-27

## Result

- The private 2026-10-15 dump was restored locally into a new disposable database with owner/ACL restoration enabled. Restore acceptance passed: 5 profiles, 5 wallets, 140 ledger rows, 5 deposit requests, 6 game settings; zero wallet arithmetic mismatches, negative wallets, missing wallet history, or wallet/latest-ledger mismatches; 7 RLS-enabled public tables, 13 policies, and Vault present.
- Exact source fingerprints passed for all 29 captured SQL bodies and the 40-row replay order.
- The initial local replay passed migration bodies 1–38.
- Body 39, `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql`, first failed at `public.manual_deposits`. Guarded QA overlay preflights detected `public.withdraw_requests` and `public.user_bank_details` missing from the backup-derived partial replay baseline.
- After the dependency preflight was adjusted, the explicitly QA-only fixture was applied to the local partial replay database. It created empty schema-only shapes for the three legacy relations and reported zero rows in each; no production data was copied.
- The suffix runner's checkpoint verifier then rejected a state whose 37 returned predicates were all `t`. This was a PowerShell guard logic bug (it compared the count of failed predicates to 37 instead of zero); the runner fix and a regression test have now been committed. Bodies 39–40 have not yet been resumed.
- After the three-table QA overlay, captured migration bodies **39/40 and 40/40 both passed** in the local replay database.
- The read-only final invariant then failed: one or more browser roles retain direct write privileges on `public.demo_wallets` and/or `public.demo_wallet_transactions`. The assertion was not weakened; the local ACLs must be inspected and compared with the audited production grant state.
- No migration was skipped. Production was not modified.

## Read-only catalog evidence

Read-only catalog queries against the currently connected production project on 2026-10-27 found `public.manual_deposits`, `public.withdraw_requests`, and `public.user_bank_details` present, all owned by `postgres` with RLS enabled. `manual_deposits` has six columns, primary key `manual_deposits_pkey`, foreign key to `auth.users(id)`, and index `idx_manual_deposits_user_id_fk`; `withdraw_requests` has five columns, primary key `withdraw_requests_pkey`, foreign key to `auth.users(id)`, and index `idx_withdraw_requests_user_id_fk`. `user_bank_details` has eight columns, primary key `user_bank_details_pkey`, unique constraint `user_bank_details_user_id_key`, and foreign key `user_bank_details_user_id_fkey` to `auth.users(id)`.

Read-only searches of `supabase_migrations.schema_migrations` found captured body `20261023092858` mentions these relations, but does not create them. The overlay guard found `withdraw_requests` and a subsequent read-only preflight found `user_bank_details.user_id` missing from the backup-derived replay baseline, before creating any fixture objects. Thus the supplied 2026-10-15 backup and captured 40-body history do not, by themselves, reconstruct the current production schema. These relations were introduced/restored outside the captured 40-body sequence, or the supplied backup predates that schema state. This is a baseline/history gap, not a source fingerprint or SQL syntax issue.

The same read-only catalog review showed broad table-level grants to `anon` and `authenticated` on the legacy `manual_deposits` table even though RLS is enabled. Separately, a read-only catalog query on current production confirmed that `anon` and `authenticated` have no `INSERT`, `UPDATE`, or `DELETE` privileges on `demo_wallets`, `demo_wallet_transactions`, `deposit_requests`, or `withdrawal_requests`; `authenticated` retains SELECT on the wallet/ledger tables. A read-only search of captured migration bodies found no explicit GRANT/REVOKE statement targeting direct table privileges on the existing wallet/ledger tables. The local replay's failed invariant therefore signals another backup/history ACL-parity gap to inspect, not a reason to weaken the assertion. No production grant changes were made; review the separate PR #20 candidate and the final post-PR #16 browser call paths before any rollout.

## What the QA-only overlay does — and does not prove

`qa/fixtures/replay-baseline/manual-deposits-schema-overlay.sql` is an explicitly QA-only fixture that was successfully applied to `nplus_migration_replay_20261026` after guarded dependency checks. It created empty schema-only approximations of the three missing legacy relations and confirmed zero rows in each. It copies no production rows and refuses to run against another database. The resume checkpoint guard then failed due to a validation-code bug; that bug has been fixed in commit `ffaf7bb`, and a regression test was added in `bd66c30`. Versions 39–40 remain pending.

If the suffix check passes, that shows bodies 39–40 can run against the explicitly reconstructed table shape and that the final-state invariants pass in this local test. **It is not a clean 40-body replay from the 2026-10-15 dump**, and it does not reconstruct the table's previous RLS policy definitions or prove full restore parity.

## Required release decision

Keep the application **not release-ready** until an authoritative baseline/history for `manual_deposits`, `withdraw_requests`, and `user_bank_details` is obtained, the wallet/ledger ACL replay mismatch is reconciled, and the schema lineage is resolved. Prefer a verified newer backup that includes the relation, or an approved canonical pre-history schema migration/source with owner, ACL, constraints and policy provenance reviewed. Do not edit the captured applied-body fingerprints, skip body 39, insert fake migration-history rows, run the QA fixture in production, or change production wallets, user data, game flags, grants or cron jobs as a shortcut.
