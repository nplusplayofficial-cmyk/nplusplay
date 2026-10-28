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

## Production rollout status — 2026-10-28

The reviewed migration SQL is now applied to the live Supabase project and recorded as:
- `20261028134905` — `server_authoritative_k3_5d_trx_demo`
- `20261028134917` — `demo_referral_200_20_rule`

Read-only post-apply verification confirmed the lottery tables exist with RLS enabled and no direct browser-role grants; internal settlement helpers are not executable by browser roles; authenticated snapshot/place-bet functions are available; the referral approval trigger is installed; no existing referral was back-credited; the wallet/ledger invariants remain clean.

**All six game flags are now ON** through the owner-approved activation migration `20261028183128_enable_all_demo_game_flags_authorized_release`. PR #22 merged at `09c432a6fc4256898772084aa78f7ec671b3e5d4`; GitHub Pages deployment #456 succeeded for that commit. Post-merge Static QA #774 also passed. The activation migration repeated the server-component preflight, checked AVIATOR scheduler/worker health and wallet invariants, enabled all six flags in one transaction, and recorded old/new state in a private audit table. Post-activation read-only checks show the flags true, 10/10 expected payout multiplier checks pass, worker health remains clean, and wallet/ledger invariants remain clean. Hosted signup/email OTP/recovery/browser acceptance remains unverified; owner authorized proceeding while recording that limitation.

## Release guardrails

1. No real-money deposit, bet, payout, or cash withdrawal. All balances/rewards are non-redeemable virtual demo points only.
2. Preserve all existing users, wallet balances and ledger rows; no referral back-credit.
3. K3/5D/TRX server settlement migration and regression suite are installed/passed. Unsupported bet categories remain disabled by UI and server checks.
4. The final flag activation is complete and was executed by a guarded, audited release migration rather than an impersonated Admin session. The `updated_by` field remains NULL rather than attributing the privileged activation to an Admin. The [N+ ADMIN](https://nplusplayofficial-cmyk.github.io/nplusplay/admin-games.html) control page now reads the persisted server status; routine future toggles should use the authenticated Admin RPC.
5. Hosted signup/email acceptance is not claimed as passed until actually tested with a controlled inbox. Pages deployment is verified by deployment run #456.
