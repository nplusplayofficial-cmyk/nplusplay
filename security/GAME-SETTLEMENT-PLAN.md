# N+ PLAY — Server-Authoritative Demo Game Settlement Plan

Date: 15 October 2026

Status: design / review only. No production SQL has been run for this plan.

## Safety invariants

- Preserve the existing static HTML/CSS/JavaScript site and all current game layouts.
- Virtual/demo credits only. Do not add real-money deposits, cash withdrawals, payment gateways, or cash payouts.
- Never reset, overwrite, or silently adjust existing wallet balances.
- Keep PR #2 as a draft. Do not merge this work into `main` until runtime regression tests pass.
- Do not revoke authenticated execute on `nplus_wallet_change` until every existing legitimate bet flow has been migrated and tested.
- Do not run any SQL from a draft branch against production without a separate review and an isolated restore/runtime test.

## Confirmed code/database findings

- The current live `public.nplus_wallet_change(p_delta, p_type, p_source, p_note)` accepts authenticated caller-supplied positive deltas. It locks the caller's wallet and writes a ledger row, but it does not verify that a server-authoritative winning result earned a credit.
- Direct browser table writes to `demo_wallets` and `demo_wallet_transactions` are blocked in live grants; authenticated own-wallet/ledger reads are preserved.
- There are currently no server-side game-round or game-bet tables in the public schema. The public application tables currently include profiles, demo_wallets, demo_wallet_transactions, deposit_requests, game_settings, demo_game_controls and wingo_manual_results.
- Game state and/or results are currently calculated and stored client-side in localStorage. Examples:
  - `wingo.html`: local period-derived result, local pending bets and positive `GAME_WIN` wallet calls.
  - `motorace.html`: client-side result generation and positive `GAME_WIN` wallet calls.
  - `aviator.html`: client-side crash point/multiplier/cashout and positive `GAME_WIN` wallet calls; also has a local-balance fallback if the wallet bridge is unavailable.
  - `5d.html`, `k3.html` and `trx-wingo.html`: wallet debits are server-RPC-backed, while current bet/result history is localStorage-based; the reviewed code contains no corresponding `GAME_WIN` calls in those pages.
- Therefore the older generic wallet RPC is a release blocker even though direct wallet table writes are denied.

## Proposed architecture

1. Add server-owned round and bet records, with unique constraints for round identity and client idempotency keys. Store game key, canonical round start/end, user ID, stake, validated selection, status, payout and timestamps.
2. Add a server-side place-bet RPC that:
   - requires `auth.uid()`;
   - accepts only allowlisted game names, supported durations, validated selections and bounded positive stakes;
   - verifies the round is still open using server time (never trust a client-supplied current result or deadline);
   - locks the wallet row and deducts the stake while inserting both bet and ledger rows atomically;
   - makes retries idempotent, so the same client request cannot debit twice.
3. Add server-side round settlement that:
   - refuses to settle before the server-calculated close time;
   - locks a single round row and creates its outcome once;
   - calculates every payout from stored validated selections and the server-owned outcome;
   - updates bet status, wallet and transaction ledger atomically;
   - rejects replays and duplicate credit; a repeated request returns the already-settled result instead of crediting again.
4. Keep outcomes hidden from public clients until the relevant round closes. Do not reuse current predictable client-side hashes as authoritative results.
5. Treat Aviator separately: server must own the round/crash point and validate cashout against server time and the authoritative round state. Client-side multiplier alone must never authorize a credit.
6. Migrate and regression-test all six pages while preserving their visual design: WINGO, K3, 5D, TRX WINGO, MotoRace and Aviator.
7. Only after all callers have moved, change the legacy generic wallet RPC so authenticated clients cannot credit arbitrary positive `GAME_WIN` amounts. Preserve necessary negative bet debits only where the replacement flow does not yet handle them.
8. Add static checks that prevent game pages from directly issuing positive `GAME_WIN` calls, then test against isolated test accounts.

## Required tests before release

- Bet below, at and above the allowed limits; insufficient balance; closed/future/wrong-duration rounds.
- Duplicate request with the same idempotency key; parallel bet placement; concurrent settlement requests.
- Every game selection and payout case, including losing bets and zero payouts.
- Tampered client result, client multiplier, stake, selection and period/deadline.
- Retry after a network failure, page reload, multiple tabs and mobile browser.
- New test account receives exactly 108 demo credits; existing test-account balances remain unchanged.
- Deposit requests still remain pending until admin approval; approval credits exactly once; rejection does not credit.
- Recheck RLS, table grants, function execute grants and Supabase security/performance advisors.
- Run the QA workflow and retain evidence for every runtime test. Static HTML checks alone are not sufficient.

## Current status

This file is a plan only. No production database changes were made while drafting it. The backup archive has been read successfully but has not been restore-tested; any future restore test must use a separate isolated database, never production.
