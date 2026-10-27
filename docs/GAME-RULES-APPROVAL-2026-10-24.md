# Game Rules Approval Gate — 2026-10-24

## Status

**NOT APPROVED — K3, 5D and TRX WINGO must remain disabled.**

This review intentionally does not invent payout multipliers or scoring rules. The repository pages explicitly mark all three games as paused while payout rules are reviewed. Their current results are client-generated/demo presentation; they are not server-authoritative settled rounds.

## Findings

- `k3.html`: the bet confirmation action only displays the pause notice. Results and history are generated/stored client-side.
- `5d.html`: the bet action returns immediately with a pause notice; no wallet debit occurs from this page. Results/history are client-side.
- `trx-wingo.html`: the bet action returns immediately with a pause notice; no wallet debit occurs from this page. Results/history are client-side.
- `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql`: migration disables K3/5D/TRX and the Admin status RPC rejects attempts to enable them.
- `admin-games.html`: the Admin UI also hard-pauses these keys.
- Existing settlement SQL/tests cover WINGO, MotoRace and Aviator, but do not provide an approved server settlement contract for K3, 5D or TRX WINGO.

## Acceptance gates before any enablement

1. Product owner approves a written rules table for each game: selection formats, valid values, round duration/cutoff, result derivation, win conditions, exact payout formula, rounding, tie/edge cases, cancellation/refund handling.
2. Implement each game with server-owned rounds, result/outcome, bet validation, wallet debit, settlement and immutable ledger entries. Client-supplied results/payouts must never be trusted.
3. Add disposable PostgreSQL tests for valid/invalid selections, exact payout calculations, insufficient balance, idempotent requests, late bets, repeated settlement, restart/recovery, ledger arithmetic and privilege/RLS boundaries.
4. Add browser tests for desktop/mobile, reloads and concurrent requests; confirm no outcome leakage before round close.
5. Keep the Admin RPC guard and game flags disabled until all checks pass and the release is explicitly approved.

## Scope and safety

- This branch adds QA gates only; it does not alter production Supabase, wallet rows, game flags or live migrations.
- Static checks cannot prove payout correctness or runtime behavior.
- Do not run unreviewed migrations against production.
