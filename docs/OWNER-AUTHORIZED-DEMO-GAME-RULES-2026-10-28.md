# N+ PLAY — Owner-authorized demo game rules (2026-10-28)

The owner instructed the release team to approve the remaining release decisions and complete the demo-only launch. This document records the concrete, conservative default rules selected under that instruction. They apply only to virtual demo points; there is no real-money stake, cash payout, or redeemable value.

## Rules for the server-authoritative K3, 5D, and TRX demo games

All outcomes are generated and stored server-side. The browser must not generate the authoritative outcome, directly debit/credit wallets, or decide payout. Direct table access for browser roles remains revoked. The final five seconds of each round are closed to new bets. A bet can be debited once per idempotency token and a round can be settled once only. The gross payout multiplier includes the original stake.

### K3 (1, 3, 5, or 10 minute round)

- Server generates three independent six-sided dice; sum is 3–18.
- Small means sum 3–10; Big means 11–18.
- Even/Odd refers to the dice sum.
- Supported selections for initial launch: Big/Small and Even/Odd only. Each winning selection returns 2.0× its stake gross. Unsupported exact-sum, pair, triple and combination selections must be disabled in the UI and rejected by the server until their own multiplier table is approved.
- The browser may show only settled server history, never a predicted result for the active period.

### 5D (1, 3, 5, or 10 minute round)

- Server generates five independent digits, each 0–9, labelled A–E.
- For a selected position A–E, an exact digit selection pays 10.0× gross; Big/Small (0–4 / 5–9) pays 2.0× gross; Even/Odd pays 2.0× gross.
- Exact total-sum selections are disabled for initial launch until a complete sum multiplier table is approved and implemented.
- The five digits and their aggregate are only displayed after server settlement.

### TRX WINGO (1 minute round)

- Server generates five independent digits, each 0–9; color and size are derived from the last digit, not from browser state and not from a real TRON blockchain.
- Green digits: 1, 3, 7, 9 (2.5× gross); Red: 2, 4, 6, 8 (2.5× gross); Violet: 0, 5 (5.0× gross).
- Last-digit exact number selection pays 10.0× gross.
- Big means last digit 5–9; Small means last digit 0–4; either pays 2.0× gross.
- UI labels must say "server-generated demo result", not "live blockchain result". Any displayed hash is demo reference data, not a blockchain proof.

## Referral contract

Choose the earlier explicit requirement: one approved DEMO_CREDIT request of at least 200 virtual points by a referred account triggers exactly one 20 virtual-point reward for its inviter. Only an approved server-recorded request qualifies; no real deposit qualifies, no self-referral, no duplicate credit, and no retroactive/back-credit until the owner explicitly authorizes a separate reconciliation.

## Accepted release limitations

- Historical provenance for original DDL/RLS policies/ACLs of `manual_deposits`, `user_bank_details`, and `withdraw_requests` cannot be proved from the available 2026-10-15 backup and recorded history. The owner accepts this documented limitation for a virtual-demo release, based on the passing reconstructed-baseline replay and current live catalog/grant checks. This acceptance is not a claim that original history was reconstructed.
- The current Supabase Free plan does not expose leaked-password protection. The owner accepts this specific plan limitation for a demo-only release, with compensating controls: verified email/OTP flow where configured, rate-limited authentication, no real-money/cash flows, strict server-side role/ownership guards, private tables with no browser grants, finite input bounds, and auditable wallet ledger. This does not claim the feature is enabled.
- Hosted email OTP/signup/login/recovery has not been proven by the local CI or local replay. Owner authorization to proceed does not change that fact; record actual hosted results after a controlled-inbox test when available.

## Release guardrails

1. No real-money deposit, bet, payout, or cash withdrawal. All balances/rewards are virtual demo points only.
2. Preserve all existing users, wallet balances and ledger rows.
3. A game must have its server settlement migration and disposable PostgreSQL regression pass before enabling its flag. Do not enable K3/5D/TRX merely because the UI renders.
4. Production game flags remain off until the migration is reviewed, applied in the intended order, and runtime smoke succeeds. Enabling a feature is a separate explicit step.
5. Do not claim hosted signup/email acceptance or Pages deployment until those actions have actually been verified.
