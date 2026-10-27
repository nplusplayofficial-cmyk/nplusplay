# N+ PLAY SECURITY DEFINER focused review — 2026-10-27

## Scope and limits

Read-only inspection of the active NPLUS-PLAY Supabase project's PostgreSQL catalog and selected function bodies, plus source/QA files on integration candidate commit `2fdedd6db4e7242d3ade48f3a108fffa4c0b29d2`. No production DDL, grants, rows, wallet balances, game flags, Auth settings, or scheduler settings were changed. This is a focused review, not a closure of all 53 Security Advisor findings.

## Catalog inventory observed

- The refreshed catalog inventory previously recorded on 2026-10-27 contains 69 public SECURITY DEFINER functions; each observed owner was `postgres` and each had a fixed `search_path` setting.
- Most audited business RPCs use `search_path=pg_catalog, public`; a smaller set of legacy RPCs use `search_path=public`.
- The focused ACL query found anonymous EXECUTE disabled for all inspected public SECURITY DEFINER functions except `public.nplus_recent_demo_activity(integer)`, which remains an intentional aggregate-only anonymous homepage endpoint. Its public contract still needs to stay limited to aggregate counts and bounded lookback.
- Authenticated EXECUTE on an Admin RPC is not the authorization boundary by itself. The inspected Admin functions also check the current user's profile role in the function body or call `public.nplus_is_admin()`.
- This catalog snapshot does not establish that all 53 authenticated-callable Security Advisor warnings have been individually reviewed. Do not blanket-revoke these functions.

## Function body review

| Function / group | Read-only observation | Remaining evidence needed |
|---|---|---|
| `nplus_admin_adjust_demo_wallet(uuid,numeric,text)` | Requires `auth.uid()`, current profile role `admin`, target wallet row lock, bounded finite non-zero amount (±1,000,000 and two decimal places), non-empty reason, and rejects negative resulting balance. Wallet update and ledger insert happen within the function transaction. Anonymous EXECUTE is absent. | Hosted Admin/non-admin tests and clean canonical replay. |
| `nplus_set_game_status(text,boolean)` | Requires signed-in Admin; rejects unknown keys and refuses to enable K3/5D/TRX. Anonymous EXECUTE is absent. | Keep all six games disabled until release gates close; hosted authorization test remains outstanding. |
| `nplus_approve_deposit(uuid)` / `nplus_reject_deposit(uuid)` | Both require Admin and lock a pending request. Approval credits only virtual demo wallet and writes a ledger row; rejection only changes request status. Anonymous EXECUTE is absent. | Hosted idempotency/repeat-review checks on synthetic test accounts. |
| `nplus_admin_resolve_demo_withdrawal(uuid,text,text)` | Requires Admin, locks a pending request and only changes status/review metadata. Function response explicitly says no wallet change and no cash payment. Anonymous EXECUTE is absent. | Hosted request/history/admin review checks. |
| `nplus_demo_admin_qualify_referral(uuid,numeric)` | Requires `public.nplus_is_admin()`, only transitions a pending referral, records qualification, and does not credit the referral wallet directly. Anonymous EXECUTE is absent. **A finite-number validation gap was discovered** (details below). | Apply the candidate-only guard on a reviewed canonical migration plan; hosted Admin input test remains pending. |
| `nplus_demo_claim_referral_bonus(integer)` | Requires a signed-in actor, checks campaign window and a configured tier, verifies invitee and qualification counts, inserts a unique tier-claim row, then writes a virtual wallet delta and matching ledger row. Anonymous EXECUTE is absent. | Runtime concurrency/retry tests are local-only; hosted flow remains pending. |
| `nplus_moto_demo_reveal_round(bigint)` | Requires a signed-in actor, only addresses the current round, and does not reveal outcome before the close window. Anonymous EXECUTE is absent. | Full outcome-leakage/concurrency acceptance and all release gates. |

## Confirmed referral qualification validation defect

Read-only SQL against the live database confirmed:

- `'NaN'::numeric < 500.00` evaluates to `false`.
- `'NaN'::numeric >= 500.00` evaluates to `true`.
- `'NaN'::numeric(14,2)` is accepted as a stored numeric value.

The live `nplus_demo_admin_qualify_referral(uuid,numeric)` body checked only whether `p_verified_virtual_amount < 500`. Because a NaN numeric compares as greater than finite values in PostgreSQL, the threshold-only predicate can allow NaN through, and the later qualification-count comparison can treat it as meeting a tier threshold. This still requires an authenticated Admin caller; it is **not** an anonymous authorization bypass, but it is a malformed Admin-input validation defect.

Candidate-only follow-up now prepared on the integration branch:

- `sql/NPLUS_PLAY_REFERRAL_FINITE_QUALIFICATION_GUARD_CANDIDATE_2026-10-27.sql` rejects NULL, NaN, positive Infinity and negative Infinity before threshold logic. It uses `CREATE OR REPLACE` and intentionally does not change grants/owners or write any data.
- `qa/test-demo-referral-finite-amount.sql` runs against a dedicated disposable PostgreSQL database and covers NaN/infinity/null/below-minimum rejection, a valid 500-point qualification, exactly-once behavior, and non-admin denial.
- `qa/test-demo-referral-finite-amount.cjs` is a static source-contract guard, wired into the candidate Static QA workflow.

The candidate patch has not been applied to production. The new disposable SQL test must pass in Actions before its behavior is considered locally verified.

## Additional WINGO overload observation

The live catalog currently has both `nplus_admin_set_wingo_demo(integer,text,text,integer)` and `nplus_admin_set_wingo_demo(integer,text,text,integer,text)`. The four-argument overload has two defaults and the five-argument overload has three defaults, so a four-argument SQL call can be ambiguous. Both signatures are owned by `postgres`, have a fixed search path, allow authenticated EXECUTE, and deny anonymous EXECUTE. The inspected current `admin-reports.html` call supplies five named arguments; `admin-games.html` uses the separate manual-save/clear RPCs. No current four-argument browser call was found in these two Admin pages. Keep the existing disposable disambiguation test and candidate patch; reconcile this overload with the canonical migration plan before applying any DDL.

## Still open

1. A clean canonical 40-body migration replay from the supplied 2026-10-15 backup, with authoritative schema/owner/ACL/policy lineage for `manual_deposits`, `withdraw_requests`, and `user_bank_details`.
2. Function-by-function review of all 53 authenticated SECURITY DEFINER Advisor findings, not just the focused subset above.
3. Hosted signup/OTP/login/password recovery, Admin/non-admin, wallet/deposit/withdrawal/referral and final hosted-browser tests using safe synthetic accounts.
4. K3/5D/TRX settlement rules and server-owned settlement remain unapproved; keep them disabled.
5. Final live site verification after the release gates pass.

No production mutations were made during this review.


## Candidate regression status update — 2026-10-27

The finite Admin referral qualification regression, finite Safe transfer regression, and both browser-role legacy-table ACL fixtures now pass in Static QA #627 on integration candidate commit `961b4e90fceaca339ab3b481411358ab7e7aea3b`. The Release Smoke #214 also passed on that commit.

These tests verify only candidate SQL in disposable PostgreSQL; the corresponding function-body replacements and ACL migration have **not** been applied to the live database. The live finite-amount guards remain absent by design until canonical replay/hosted test gates and explicit release approval are satisfied.


## Expanded finite numeric input review — 2026-10-27

A read-only catalog review found eight authenticated SECURITY DEFINER RPCs whose user-input numeric paths needed finite-value validation, then added two stored-amount consumers for defense-in-depth:

- deposit request amount and withdrawal request amount (previously rounded/narrowed in the declaration initializer before validation);
- Admin gift-code amount;
- Aviator stake and optional auto-cashout;
- MotoRace stake and WINGO stake;
- virtual Safe transfer amount;
- Admin referral qualification verified amount.

Candidate-only replacements are bundled in `sql/NPLUS_PLAY_FINITE_NUMERIC_RPC_GUARDS_CANDIDATE_2026-10-27.sql`. The patch rejects NULL/NaN/±Infinity before range comparisons or numeric narrowing; it preserves the role checks, fixed `search_path`, existing bounds, row locks, idempotency and wallet/ledger logic. It contains ten full function replacements derived from the live read-only definitions.

The static source-order guard and disposable PostgreSQL numeric-semantics test are wired into Static QA. This is not full RPC end-to-end testing and the bundle is not deployed. Its final approval still requires CI, reviewed source diff, canonical replay/restore parity, and hosted safe test accounts.


## Defense-in-depth on stored deposit/gift amounts — 2026-10-27

The latest read-only catalog review checked direct table ACLs/RLS for demo transaction entry points. Authenticated has SELECT-only on `deposit_requests` and `withdrawal_requests`; authenticated has no direct table grants on Aviator/Moto/WINGO bet tables or gift-code tables. Owner-scoped RLS alone is not the only barrier—the direct write ACLs are absent on those tables.

Two additional read/write boundary guards were added to the same candidate bundle:

- `nplus_approve_deposit(uuid)` now rejects a stored request amount that is NULL, NaN, +Infinity or -Infinity before taking the wallet-row lock or changing the wallet/ledger.
- `nplus_demo_gift_redeem(text)` now rejects a malformed stored gift-code amount before writing a claim, incrementing claims_count or crediting the virtual wallet.

A read-only aggregate check over 21 amount/balance/stake/payout columns across wallet transactions, Safe balances/transfers, gift codes/claims, deposit/withdraw requests, referrals, and game bets returned **zero current non-finite rows**. This is a snapshot of current data, not a guarantee against future inputs; candidate guards remain necessary.

These two added checks are candidate-only and require CI verification. No live stored rows, grants, functions or wallet balances were modified.


## Complete focused function group review update — 2026-10-27

The following additional SECURITY DEFINER groups were checked read-only by function body, ACL and current usage:

- Admin read-only reports: commission summary, approved-deposit summary, user directory, per-user wallet transaction history, WINGO live bets/round summary, referral administration, support inbox, and VIP administration dashboard. Each reviewed report path contains an Admin role gate; paginated/list paths clamp limits (typically 200, with referral/support lists capped at 500).
- Admin mutation RPCs: deposit approve/reject require Admin and lock pending requests; withdrawal review requires Admin, locks pending request, and explicitly changes status/review metadata only (no wallet change/cash payment); manual WINGO save/clear/set overloads require Admin and validate duration/result shape; game status requires Admin, rejects unknown keys and blocks K3/5D/TRX enabling.
- User-scoped writes: Aviator cashout checks the authenticated user's bet, locks the round/bet, handles duplicate cash-out idempotently, and emits wallet/ledger updates only in server code; MotoRace reveal only accepts the current round and refuses reveal until the closing cutoff; attendance/gift/referral reward paths use actor-scoped uniqueness/claim checks; support submit bounds category/subject/message; VIP and Safe dashboards are actor scoped.
- User-scoped reads: Aviator/Moto/WINGO history and personal bet functions filter on `auth.uid()` and clamp page sizes (typically 200; completed round history up to 500). Activity endpoint `nplus_recent_demo_activity(integer)` remains the only anonymous-executable SECURITY DEFINER endpoint and returns aggregate counts without user IDs, with a bounded lookback.
- Admin WINGO overloads remain a migration-order item: both four- and five-argument defaulted signatures exist live; current reviewed `admin-reports.html` call supplies five named arguments. Disposable overload regression is passing in CI, but canonical migration ordering must be reviewed before applying DDL.
- The dynamic `EXECUTE` in `nplus_set_game_status` is restricted to the scheduler-health lookup after Admin role check, an allow-listed game key, and a parameterized `USING` value; it is not generic user-controlled SQL.

Read-only aggregate scan over 21 live amount/balance/stake/payout columns returned zero rows containing NaN or ±Infinity. This supports the snapshot that existing numeric columns are clean as of this check, but does not replace the new candidate input guards or establish historical data provenance.

Scope note: this closes the targeted/high-risk code-review pass for the listed function groups and numeric entry points. It does not close every individual one of the 53 Advisor warnings as an independent signed-off finding; residual Advisor triage remains a release checklist item.


### Admin deposit approval bounds aligned

The candidate `nplus_approve_deposit(uuid)` now additionally enforces the same 100–50,000 virtual-point amount bounds as `nplus_create_demo_deposit_request`, alongside NULL/NaN/±Infinity rejection before wallet mutation. The static guard asserts both bounds are present in the candidate definition. No live function was altered.


## Full SECURITY DEFINER catalog triage — 2026-10-27

A fresh read-only catalog inventory screened all public SECURITY DEFINER functions in the live project:

| Check | Observed |
|---|---:|
| Total public SECURITY DEFINER functions | 69 |
| Owner is `postgres` | 69 / 69 |
| Fixed `search_path` setting | 69 / 69 |
| Authenticated EXECUTE | 53 |
| Anonymous EXECUTE | 1 |
| Authenticated functions with an `auth.uid()` source marker | 49 / 53 |
| Remaining authenticated functions with an Admin-helper/role-guard source marker | 3 / 53 |
| Authenticated write-pattern functions with no detected actor/Admin guard marker | 0 |
| Functions using PL/pgSQL dynamic `EXECUTE` | 1 |

The one anonymous-executable endpoint is `nplus_recent_demo_activity(integer)`, which was separately checked as aggregate-only with a bounded lookback and no user identifiers. The three authenticated functions without direct `auth.uid()` text are Admin read paths that use the shared `nplus_is_admin()` helper. The single dynamic `EXECUTE` occurs in `nplus_set_game_status(text,boolean)` for an allow-listed Aviator scheduler-health lookup after Admin authorization; its value is parameterized rather than interpolated into the SQL identifier/text.

Catalog check also confirms `anon`, `authenticated`, and PostgreSQL `PUBLIC` do not have CREATE privilege on the `public` schema. Targeted source inspection covered Admin wallet/deposit/withdrawal/game/WINGO/referral/security RPCs; user-scoped bet/cashout/history APIs; and attendance/gift/referral/Safe/support/VIP paths. List APIs clamp page sizes; write paths lock affected request/wallet/round rows or use unique claims for idempotency.

**Scope honesty:** this is a complete catalog/authorization-pattern triage of all 53 authenticated-executable functions plus targeted source review of the risky groups, not a signed-off closure ticket for each of the 53 individual Advisor warnings. Remaining per-finding risk acceptance still needs a formal release review; do not mark all Advisor warnings closed solely from the counts above.

## Current data-integrity snapshot

Read-only aggregate checks of 21 numeric amount/balance/stake/payout fields across `demo_wallets`, `demo_wallet_transactions`, Safe balances/transfers, gift codes/claims, deposit/withdraw requests, referral qualifications/rewards, and Aviator/Moto/WINGO bet fields found **zero NaN/Infinity/-Infinity rows** as of 2026-10-27. No row contents or user identifiers were selected for this check.

## Latest exact-head CI

- Pre-documentation candidate commit `3ba6c56e591cd522f07e2d7cc6ff1be2f6787ced`: Static QA #632 run `40493302375` passed, including source syntax, referral finite guard, 10-function numeric RPC source-order guard, disposable PostgreSQL finite-value semantics, legacy ACL assertions, and desktop/mobile browser smoke.
- Release Smoke #220 run `40493302177` passed on the same commit.
- Candidate bundle contains 10 replacement definitions and is not deployed. Any documentation-only follow-up creates a new CI head; verify the exact final head before release.
