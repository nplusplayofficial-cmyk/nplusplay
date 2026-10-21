# N+ PLAY Aviator Scheduler and Recovery — No-Cost Design

Updated: 2026-10-19
Status: design only; no scheduler deployed and no production SQL changed.

## Decision

Do not add a `pg_cron` job or a GitHub Actions timer as a pretend fix. The current `nplus_aviator_demo_current_round()` RPC requires `auth.uid()`, so an unauthenticated scheduled caller cannot safely run it. It also performs settlement work as a side effect of client polling. A browser-independent worker needs a distinct, server-only entry point and a verified execution environment.

Static hosting (including GitHub Pages) serves files; it does not keep a background process alive. A scheduled CI job is not a substitute for a latency-sensitive round loop: execution can be delayed, suspended, or skipped, and putting a Supabase service-role key into browser code is never acceptable.

## Safe architecture target

1. **One server-authoritative round state** in PostgreSQL. A unique active-round constraint and row/advisory locks prevent parallel workers from creating overlapping rounds.
2. **Separate server-only maintenance RPC** that can be executed only by a trusted backend role. It must not accept a crash point, multiplier, user ID, payout, or wallet delta from the caller. It should use database time and server-generated outcomes.
3. **Idempotent state transitions**: round creation, auto-cashout, crash finalization, loss settlement and ledger writes each happen at most once. Use unique constraints/idempotency keys, not only client-side flags.
4. **Least-privilege execution**: revoke execution from PUBLIC, anon and authenticated for the maintenance RPC; grant only to the chosen trusted server role. Never expose service-role credentials to the frontend or logs.
5. **Worker heartbeat and recovery**: record last successful run, run duration, error count and round ID. If a worker misses its heartbeat, fail closed (disable new demo bets) rather than silently advancing inconsistent rounds.
6. **Read APIs remain user-scoped**: clients can request their own bets and public-safe round state, but cannot invoke privileged maintenance or choose outcomes.
7. **Demo-only policy**: no real-money deposits, withdrawals, wagers or payouts. Admin test overrides must not affect ordinary user rounds.

## No-cost feasibility gate

Before implementation, verify the exact free hosting plan available to the owner:
- Does it support a persistent scheduled invocation with documented timing and retry semantics?
- Can it invoke a private server-side function without placing privileged secrets in the client?
- Are execution quotas, sleep/idle rules, and concurrency limits compatible with the round interval?
- Can failures be observed and alerted without a paid service?

If the current Supabase free project exposes an appropriate scheduler, test it only in a disposable/local environment first. Do not assume feature availability from a menu label, and do not create a paid branch or upgrade to test it. If no suitable free scheduler exists, keep Aviator explicitly marked as requiring an active authenticated client to advance rounds; do not claim autonomous 24/7 operation.

## Required tests before any rollout

- Two concurrent worker calls create one round only.
- Repeated calls settle each eligible auto-cashout once and create one ledger entry.
- A worker restart after each transition resumes without duplicate payouts or stuck open bets.
- Worker outage disables new betting after the agreed heartbeat threshold.
- Authenticated and anonymous clients are denied the maintenance RPC.
- An ordinary client cannot submit crash point, multiplier, wallet delta, payout, or another user's ID.
- Browser close/reload does not change authoritative outcome or duplicate settlement.
- Backup restore and all tests run against a disposable database; production wallet/ledger rows remain untouched.

## Current implementation gap

The current client calls `nplus_aviator_demo_current_round()` every 500 ms, and the RPC creates/advances rounds while an authenticated client is polling. This is not proof of persistent background scheduling. The RPC is not suitable as-is for a cron caller because it requires `auth.uid()` and performs user-facing state work. Do not schedule this function directly.

## Release status

**BLOCKED — design only.** No scheduler was created, no secrets were added, no SQL was applied to production, no wallet balances were changed, and no deployment occurred.
