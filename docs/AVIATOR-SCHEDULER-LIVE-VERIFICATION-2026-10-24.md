# Aviator scheduler — read-only live verification (2026-10-24)

## Executive result

**The production Aviator scheduler is present and actively running.** This corrects the earlier source-only audit statement that no scheduler was configured. The prior audit looked only at the `main` branch's tracked SQL/workflows; it did not query the live `pg_cron` catalog or the worker-health row.

No production changes were made in this verification. All queries were SELECT-only. No scheduler was enabled, disabled, replaced, or rescheduled.

## Runtime evidence observed

- PostgreSQL extension `pg_cron`: version `1.6.4`.
- `cron.job` exists.
- Job `nplus-aviator-worker`: active, schedule `1 seconds`; job command fingerprint `5003a6a0`.
- The stored job command contains a call to `nplus_aviator_demo_worker_tick`. It does not contain `net.http_post`, `vault.decrypted_secrets`, or a literal `service_role` marker. The command itself was not returned or copied into this report.
- In the observed 24-hour window, `cron.job_run_details` returned 84,957 rows with status `succeeded` for worker job 3 and no other status group. Average recorded duration was 0.007 seconds. The last recorded result returned `1 row`.
- Worker-health row at observation time:
  - `last_success_at` was 0.912 seconds old;
  - the success timestamp was within five seconds;
  - `consecutive_failures = 0`;
  - `last_error IS NULL`;
  - `last_error_at IS NULL`;
  - a last round ID was present.
- The internal worker entry point `nplus_aviator_demo_worker_tick()` is not executable by `anon` or `authenticated` according to current privilege checks. It remains a privileged server-side routine; never expose it through browser code.

These values are a timestamped operational snapshot, not a promise of future uptime. They establish that the configured cron runner and the internal worker-health heartbeat were working at the time checked.

## Repository source evidence

The scheduler SQL source has been copied to this folder as a **recovered evidence file only**:

`docs/recovered-live-migration-sql-2026-10-23/20261021182724_nplus_aviator_persistent_scheduler.sql`

The prior live-body comparison report maps the applied records `20261021161206` and `20261022055354` to the same 1,172-character SQL body. That body is tracked on a source-recovery branch; this evidence copy is not a canonical migration and must not be manually rerun. See the migration fingerprints/source-map reports for the wider reconciliation gate.

## What this does and does not prove

**Verified:** scheduler exists; scheduled worker is active; recent cron invocations are succeeding; worker health has a recent success and zero consecutive failures at the checked moment; internal worker entry-point execute privileges are not granted to browser roles.

**Still not proven:** real authenticated browser end-to-end behavior on the hosted site, full clean migration replay, a production-faithful backup restore, or every possible race/recovery edge case. The static/disposable SQL suites cover specified scenarios but are not a substitute for a separate reviewed integration test.

## Safety

No wallet/user data, round/bet rows, game settings, SQL definitions, migration rows, grants, or cron jobs were changed. Do not copy this recovered SQL into `supabase/migrations` or execute it to "refresh" the existing schedule; that must wait for migration-source reconciliation and a reviewed release plan.
