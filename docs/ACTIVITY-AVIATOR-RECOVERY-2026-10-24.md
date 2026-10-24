# Recent Activity + Aviator Recovery Audit — 2026-10-24

## Status

**Partial — homepage aggregate feed source and privacy-safe RPC are ready; production Aviator scheduler is now verified as active through read-only catalog/health checks. Hosted homepage deployment and full authenticated integration verification remain open.**

## Recent Activity

- The homepage displays a server-backed aggregate feed for WINGO, MotoRace and Aviator.
- Added `sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql`: RPC returns only `game_key` and `activity_count`; no player ID, name, email, stake, payout, selection or outcome.
- Requested window is clamped server-side to 1–60 minutes. Public access is only to this aggregate RPC.
- The homepage uses an allowlist and text-only DOM APIs, and displays an unavailable/empty state instead of fabricated sample activity.
- `activity.html` requires a signed-in user and loads wallet ledger entries through the wallet bridge plus per-user game history RPCs.

## Aviator Recovery

- Existing SQL uses a transaction advisory lock for round resolution/creation.
- Bet request IDs have a unique database constraint.
- Server cash-out is idempotent for already cashed-out bets.
- Current-round and cash-out RPCs include recovery for delayed polling: eligible server auto-cash-outs are credited before remaining open bets are marked lost.
- Existing disposable SQL tests exercise repeated cash-out, late polling recovery, and wallet ledger credit counts.
- Browser page polls the server round RPC while open and resyncs on focus/visibility/pageshow.

## Scheduler runtime — corrected after read-only production verification

The original source-only check incorrectly described the scheduler as absent. A direct read-only query against the production catalog on 2026-10-24 found:

- `pg_cron` extension version 1.6.4 and `cron.job`.
- Active `nplus-aviator-worker` job scheduled every second; its command calls `public.nplus_aviator_demo_worker_tick()`.
- 84,957 successful cron-run records in the observed 24-hour window; no other status group was returned.
- The worker health row showed a recent success (less than five seconds old), zero consecutive failures, no last error and a recent round ID.
- Anon/authenticated cannot execute the privileged worker-tick function directly; the job command did not contain an HTTP/Vault/service-role-secret marker in the checks performed.

Full timestamped evidence and caveats are in [AVIATOR-SCHEDULER-LIVE-VERIFICATION-2026-10-24.md](./AVIATOR-SCHEDULER-LIVE-VERIFICATION-2026-10-24.md).

This verifies that the configured production scheduler was running at the checked time. It does **not** replace backup acceptance, canonical migration replay, or hosted browser integration tests. The scheduler SQL body is retained only as recovered evidence under `docs/recovered-live-migration-sql-2026-10-23/`; do not rerun it or copy it into `supabase/migrations` until Work #1's source/replay review is complete.

## Validation

- `qa/test-activity-aviator-audit.cjs`: source-level privacy, route, idempotency, scheduler-source and recovery checks.
- `qa/test-recent-demo-activity.sql`: disposable PostgreSQL test for aggregate result shape, supported game keys, bounded window and execute grants.
- Static QA and Release Smoke CI are green on the branch; a green static audit does not prove the homepage feed has been deployed or that every authenticated hosted path works.

## Safety

QA branch only. No production schema, game flags, wallets, balances, user records or scheduler settings were changed.
