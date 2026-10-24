# N+ PLAY — Wallet, Admin & Referral QA (2026-10-23)

## Status
**Work #4: code fixes and live read-only checks prepared; NOT fully closed.** All changes are on `fix/wallet-admin-referral-flow-2026-10-23`, not merged or deployed. Production was not changed. No live requests, user identities, wallet balances, ledgers, referrals, migration rows, or grants were modified.

## Live read-only evidence
The live contract file `qa/test-wallet-admin-referral-live-readonly.sql` ran against project `pcrxlqduygvzchzxsmdv` with no SQL error. The file only runs catalog/aggregate assertions and does not mutate data.

- 5 profiles, 5 demo wallets, 146 wallet ledger rows.
- Negative wallets: 0.
- Profiles without wallets: 0.
- Ledger arithmetic mismatches: 0.
- Current wallet balance vs latest ledger entry mismatches: 0.
- Referral rows currently present: 0; no duplicate invitee attributions, orphan qualifications, unpaired tier claims, or unpaired reward-ledger rows were found.
- Authenticated clients cannot directly INSERT/UPDATE/DELETE `deposit_requests` or insert/update/delete `withdrawal_requests`; requests must use guarded server RPCs.
- Anonymous callers cannot execute Admin deposit approval/rejection or Admin wallet adjustment/withdrawal-review RPCs.
- Existing deposit_requests aggregate: 6 approved records totalling 7,200 virtual credits.
- Existing legacy manual_deposits aggregate: 6 pending records totalling 600 (legacy request amounts). These rows remain untouched and must not be sent to the new deposit approval RPC.
- Existing withdrawal_requests aggregate: 1 rejected request totalling 100. This remains untouched.
- Current referral configuration differs from the older test file: Admin-verified qualification uses 500 virtual credits and bonuses are explicitly claimed from configured event tiers. The one-invitee tier currently has a configured 55 virtual-point bonus, not the old automatic 20-credit reward on a 200-credit request.

No user IDs, emails, full UTR values, bank details, or individual wallet balances are recorded here.

## Problems found in current main UI

1. Account page's Deposit button led to the legacy UPI/UTR `deposit.html` (inserts to `manual_deposits`), but the current Admin deposit RPC and user's Deposit History use `deposit_requests`. That means the current Admin queue did not line up with new submissions.
2. Account page's Withdraw button led to legacy `withdraw.html`, which called `nplus_create_demo_withdrawal_request` without the required `p_request_token` and had a fallback to the old `withdraw_requests` table; Admin and history use `withdrawal_requests`.
3. Old Admin deposits screen read `manual_deposits` but tried to pass those IDs to RPCs that expect `deposit_requests`; its RPC-missing fallback was not a safe solution for the current schema.
4. The old Admin withdrawals UI showed bank details and labeled a status-only demo review as `APPROVE (PAID)`, and it fell back to direct table status mutation if the RPC was missing.

## Code changes prepared on this branch

- `deposit-demo.html`: selectable amount (100–50,000 virtual credits), authenticated, tokenized/idempotent server request RPC, no immediate wallet credit.
- `withdraw-demo.html`: authenticated demo request with token, balance guard and explicit status-only/no-cash messaging.
- `account.html`: routes the main wallet buttons to the two demo request pages.
- `deposit.html` and `withdraw.html`: legacy paths redirect into the demo-only flows so those pages no longer collect real-payment or bank data.
- `deposit-history.html` and `withdrawal-history.html`: links point to current demo routes.
- `admin-deposits.html`: separates `deposit_requests` (safe approve/reject via guarded RPCs) from the legacy `manual_deposits` queue. Legacy rows are displayed read-only; approval buttons are not shown for those rows.
- `admin-withdrawals.html`: hides bank-detail fields, labels approval as status-only, and no longer falls back to direct table updates if the secure RPC is missing.
- `sw.js`: shell cache version bumped to v8 and updated demo/Admin pages added.
- `qa/test-wallet-admin-referral-live-readonly.sql`: safe catalog/invariant checks; executed against production without errors.
- `qa/test-wallet-admin-referral-e2e.sql`: comprehensive disposable-only transaction test of deposit/withdraw request idempotency, Admin authorization, wallet adjustment/ledger, referral self/invalid/duplicate behavior, qualification and one-time tier claim, status-only withdrawal resolution, and positive-credit guard. This has **not** been executed because a disposable PostgreSQL test instance is not available in this session.
- `qa/test-demo-referrals.sql`: labeled as an outdated legacy contract, because its automatic 200/20 reward is not the current configured referral model.

## Required acceptance before merge/deploy

1. Run `qa/test-wallet-admin-referral-e2e.sql` only on an isolated disposable PostgreSQL database with the reconciled current schema/functions. Never run it on live production.
2. Browser test with dedicated synthetic accounts: request demo deposit → appears in Admin demo queue → Admin approves → exact wallet/ledger delta; rejection changes no wallet; duplicate approval is rejected.
3. Browser test: request demo withdrawal → appears in Admin queue/history; Admin review changes status only; wallet/ledger stay unchanged; no payout or bank-detail exposure.
4. Browser test referral path end-to-end using synthetic referrer/invitee: unique code, invalid/self/duplicate rejection, Admin qualification threshold, one tier claim, exactly one matching ledger reward, second claim denied.
5. Confirm all old 6 pending `manual_deposits` remain unchanged and decide their separate reconciliation path before processing them. Do not bulk-convert or credit them automatically.
6. Confirm expected current referral event rules and amount/tier schedule in product requirements; do not restore the old 200/20 model just to satisfy its legacy test.
7. Test the new branch in the browser/PWA and deploy only after Work #1 migration source/replay/backup gates are resolved, then verify the built site and service-worker cache update.

## Safety note
The intended wallet and reward paths remain virtual demo credits with no cash value. Withdrawal review is deliberately status-only. Keep all six game settings disabled until their separate settlement/browser release gates pass.

**Final: Work #4 is partially complete. Read-only production invariants pass and integration fixes/regression files are staged, but disposable E2E/browser acceptance is still required before marking it complete.**
