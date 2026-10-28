# Aviator scheduler — production read-only audit (2026-10-24)

## Findings

A read-only catalog and scheduler-history check against the NPLUS-PLAY Supabase project confirmed that the Aviator scheduler is present and running. This supersedes the earlier source-only finding in the initial activity audit report, which did not search the historical persistent-scheduler migration and incorrectly concluded no scheduler was configured.

- `pg_cron` extension is installed (version 1.6.4).
- The `cron.job` catalog exists.
- Active job `nplus-aviator-worker` is scheduled every 1 second.
- Active job `nplus-aviator-job-history-cleanup` is scheduled daily at 03:17 server time, retaining recent job history.
- Worker job's stored command fingerprint is `5003a6a0`; source-level comparison confirmed that it points to `public.nplus_aviator_demo_worker_tick()`.
- The worker tick and internal round-advance function exist in production. Neither is executable by `anon` or `authenticated` in the privilege snapshot.
- In the 24-hour run-history query, 84,957 runs were reported with status `succeeded`; the query returned only the succeeded status group. The newest sampled runs were also successful.
- `public.nplus_aviator_worker_health` exists. Reading its row-level error details was not included in this audit.

## Recent Activity RPC

A live read-only catalog check confirmed `public.nplus_recent_demo_activity(integer)` exists and returns `TABLE(game_key text, activity_count bigint)`. Both `anon` and `authenticated` can execute that aggregate RPC. This result shape contains only a game key and count; it does not contain player identifiers, stakes, payouts, selections or outcomes.

## Source reconciliation note

The exact persistent-scheduler migration body has previously been fingerprint-matched to the draft source `feature/nplus-free-release-audit-2026-10-19:supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql`, and the live applied body is recorded under migration-history versions `20261021161206` and `20261022055354` in the existing migration source map. This historical source is intentionally documented here rather than placed under the canonical `supabase/migrations/` folder, to avoid causing the CLI to apply an already-applied scheduler definition as a new migration.

## Remaining verification

- This audit verified catalog configuration and scheduler run records, not payout correctness for every round and every failure scenario.
- The worker health row details were not read; no health-row assertions are claimed.
- Run the existing Aviator settlement SQL suite against a disposable PostgreSQL-compatible environment.
- Perform a controlled, logged hosted-app test once the client/UI deployment candidate is approved; do not change scheduler settings just to re-prove that it exists.
- Keep all game flags disabled until the separate release gate approves the games.

## Safety

Read-only live queries only. No production scheduler, migration history, game setting, wallet, ledger or user data was changed.