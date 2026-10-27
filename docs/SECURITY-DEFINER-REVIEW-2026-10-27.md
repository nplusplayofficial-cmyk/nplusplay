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


## Second confirmed finite-number input issue: virtual Safe transfer

A read-only live catalog probe on 2026-10-27 observed that `public.nplus_demo_safe_transfer(text,numeric)` is executable by `authenticated` and not by `anon`. Its previous implementation initialized `v_amount numeric(14,2) := p_amount` before validating the value, then checked only `v_amount <= 0` and `v_amount <> round(v_amount,2)`.

PostgreSQL numeric semantics were confirmed read-only:
- `'NaN'::numeric(14,2) <= 0` evaluates to false.
- `'NaN'::numeric(14,2) <> round('NaN'::numeric(14,2),2)` evaluates to false.
- `'NaN'::numeric(14,2) > 0` evaluates to true.
- The live wallet column is `numeric(18,2)`, which can store NaN.

This creates a plausible authenticated path to poison a user's own virtual wallet and Safe balance with NaN; it is not an anonymous access bypass or real-money payout path, but it is a data integrity defect. The live RPC and all related ACLs were only read; no attempt was made to invoke a mutating call against production.

A candidate-only function replacement is now added at `sql/NPLUS_PLAY_SAFE_TRANSFER_FINITE_AMOUNT_GUARD_CANDIDATE_2026-10-27.sql`. It checks NULL/NaN/infinities, upper numeric range and original-argument decimal precision before assigning to `numeric(14,2)`; it keeps the authenticated identity check, user-owned row locks, balance limits and ledger writes. It does not change grants or any rows.

Static source guard and isolated PostgreSQL runtime test were added to the Static QA workflow. Their result is pending for the newest candidate commit until Actions completes. Production is unchanged and the candidate replacement must not be applied until canonical migration/backup gates and explicit rollout review pass.
