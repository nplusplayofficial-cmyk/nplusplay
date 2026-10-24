# Recent Activity + Aviator Recovery Audit — 2026-10-24

## Status

**Partial — homepage aggregate feed contract added; Aviator demand-driven recovery exists; autonomous scheduler is not configured. Do not mark the whole item complete yet.**

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

## Release blocker: no autonomous scheduler

No `pg_cron`, scheduled job, or server worker invoking Aviator recovery was found in repository SQL/workflows. Recovery is **demand-driven**: it runs when an authenticated client calls the round or cash-out RPC. This is not a guaranteed background scheduler and does not settle rounds while no clients call the RPC.

Do not enable or claim scheduler readiness until the hosting project's supported scheduler is identified, an idempotent service-only recovery entry point is designed, and a disposable integration test proves stale-round recovery without exposing a service secret to the browser. Do not blindly enable extensions or schedule production jobs.

## Validation

- `qa/test-activity-aviator-audit.cjs`: source-level privacy, route, idempotency and recovery checks.
- `qa/test-recent-demo-activity.sql`: disposable PostgreSQL test for aggregate result shape, supported game keys, bounded window and execute grants.
- The SQL/browser CI run must finish successfully. A green static audit does not prove the hosted Supabase function is deployed, and the scheduler blocker remains until separately resolved.

## Safety

QA branch only. No production schema, game flags, wallets, balances, user records or scheduler settings were changed.
