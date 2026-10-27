# Expanded SECURITY DEFINER review and release blockers — 2026-10-27

## Scope, timestamp and safety

Read-only catalog/function-body review of the connected NPLUS-PLAY Supabase production database on 2026-10-27, refreshed against Security Advisor findings observed at 2026-10-27 14:02:53 UTC. Current repository candidate: `integration/release-candidate-2026-10-27`.

No production DDL, ACLs, rows, wallets, Auth settings, game flags, or scheduler settings were changed during this review. Candidate SQL/tests remain separate from production.

## Current catalog and Advisor snapshot

- 69 public SECURITY DEFINER functions; 69/69 are owned by `postgres` and have an explicit fixed `search_path`.
- 53 functions have authenticated EXECUTE; only one public SECURITY DEFINER function has anon EXECUTE: `public.nplus_recent_demo_activity(integer)`.
- `anon` and `authenticated` have no CREATE privilege on schema `public`.
- 33 public tables currently have RLS enabled. The 20 RLS-enabled/no-policy Advisor findings have no direct browser-role SELECT/INSERT/UPDATE/DELETE privileges. Do not add broad policies just to silence the INFO lint.
- Security Advisor: 20 `rls_enabled_no_policy` INFO findings; one anon SECURITY DEFINER WARN; 53 authenticated SECURITY DEFINER WARN findings; one leaked-password-protection WARN. The last item is plan-limited (see below).

The generic SECURITY DEFINER lints are not proof that each RPC is exploitable; the exposed function contract and body authorization are the security boundary. They must not be addressed through a blanket revoke that would break required application RPCs.

## Function-by-function classification: all 53 authenticated-callable functions

### A. Administrator-only functions — 21

These functions perform explicit Admin checks either by resolving `auth.uid()` to `public.profiles.role = 'admin'`, or by calling `public.nplus_is_admin()`, before returning privileged data or mutating state:

- `nplus_admin_adjust_demo_wallet(uuid,numeric,text)`
- `nplus_admin_clear_wingo_manual(integer,text)`
- `nplus_admin_commission_summary()`
- `nplus_admin_deposit_summary()`
- `nplus_admin_resolve_demo_withdrawal(uuid,text,text)`
- `nplus_admin_save_wingo_manual(integer,text,text,integer,text)`
- `nplus_admin_set_wingo_demo(integer,text,text,integer)`
- `nplus_admin_set_wingo_demo(integer,text,text,integer,text)`
- `nplus_admin_user_directory(text,integer)`
- `nplus_admin_user_transactions(uuid,integer)`
- `nplus_admin_wingo_live_bets(text)`
- `nplus_admin_wingo_round_summary(text)`
- `nplus_approve_deposit(uuid)`
- `nplus_demo_admin_create_gift_code(text,numeric,integer,timestamptz)`
- `nplus_demo_admin_qualify_referral(uuid,numeric)`
- `nplus_demo_admin_referrals(integer)`
- `nplus_demo_admin_support_list(integer)`
- `nplus_demo_admin_support_update(uuid,text,text)`
- `nplus_demo_admin_vip_dashboard()`
- `nplus_reject_deposit(uuid)`
- `nplus_set_game_status(text,boolean)`

Findings:
- Admin wallet adjustment requires a reason, rejects zero/non-finite/out-of-range values, locks the target wallet, prevents a negative result, and writes a ledger entry atomically.
- Deposit approve/reject locks the request and only processes pending requests. Approval updates the virtual wallet and ledger together; rejection changes request state only.
- Withdrawal review locks a pending request and changes review/status metadata only. It explicitly does not change a wallet or pay cash.
- Game-status mutation checks the Admin role, validates the key, checks relevant backend/scheduler prerequisites, and refuses to enable K3, 5D, or TRX while payout rules are unapproved.
- Admin user-directory/transaction APIs cap row limits at 200. Support/referral Admin lists cap their requested limit at 500.
- WINGO manual setters validate duration/mode/color/number/size and check Admin status. The two WINGO overloads had overlapping defaults that made four-argument SQL calls ambiguous; a reviewed candidate migration now removes defaults from the five-argument signature while retaining the four-argument compatibility overload, original owner, fixed search path, and intended EXECUTE grants. The disposable PostgreSQL regression test is now wired to exercise that exact migration. This migration is candidate-only and must pass new-head CI and canonical replay before any release.

Potential scale-only follow-up: `nplus_admin_wingo_live_bets(text)` and `nplus_admin_wingo_round_summary(text)` filter to an explicit period but do not impose a separate result cap. This is not an authorization bypass in the reviewed body; consider a bounded period/result contract if volume warrants it.

### B. User/actor-scoped functions — 30

The following API functions derive the user from `auth.uid()` and use that identity to scope wallet, bet, claim, referral, support, or profile-related state. Functions with mutation paths use row locks, unique/idempotency keys, status transitions, or balance checks according to their contract:

- Aviator: `nplus_aviator_demo_cashout(uuid)`, `nplus_aviator_demo_current_round()`, `nplus_aviator_demo_history(integer)`, `nplus_aviator_demo_my_bets(integer)`, `nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)`
- Requests: `nplus_create_demo_deposit_request(numeric,uuid,text)`, `nplus_create_demo_withdrawal_request(numeric,uuid,text)`
- Attendance/referral/gift: `nplus_demo_attendance_claim()`, `nplus_demo_attendance_dashboard()`, `nplus_demo_claim_referral_bonus(integer)`, `nplus_demo_gift_dashboard()`, `nplus_demo_gift_redeem(text)`, `nplus_demo_referral_apply(text)`, `nplus_demo_referral_bonus_dashboard()`, `nplus_demo_referral_dashboard()`
- Safe/support/VIP: `nplus_demo_safe_dashboard()`, `nplus_demo_safe_transfer(text,numeric)`, `nplus_demo_support_dashboard()`, `nplus_demo_support_submit(text,text,text)`, `nplus_demo_vip_dashboard()`
- MotoRace: `nplus_moto_demo_current_round()`, `nplus_moto_demo_history(integer)`, `nplus_moto_demo_my_bets(integer)`, `nplus_moto_demo_place_bet(jsonb,numeric,uuid)`, `nplus_moto_demo_reveal_round(bigint)`
- Wallet/WINGO: `nplus_wallet_change(numeric,text,text,text)`, `nplus_wingo_demo_current_round(integer)`, `nplus_wingo_demo_history(integer,integer)`, `nplus_wingo_demo_my_bets(integer,integer)`, `nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)`

Reviewed control observations:
- `nplus_wallet_change` rejects NULL/NaN/±Infinity, zero and positive deltas; blocks generic game bet/win changes; only subtracts from the signed-in user's wallet and writes a matching ledger row.
- Bet RPCs bind bets to `auth.uid()`, validate selection/round/stake, use request IDs for retry idempotency, lock the applicable round/wallet, check available virtual balance, then write wallet/ledger and bet together.
- User history/claim/dashboard functions filter using the signed-in actor. Game history limits are clamped; personal bet lists are bounded.
- Referral apply rejects anonymous callers, missing codes, self-referrals and repeated attachments. Tier reward claims check the campaign/tier/qualification counts and use a unique claim row before wallet+ledger updates. Attendance and gift claims similarly rely on unique claim keys and wallet/ledger writes in the same transaction.
- MotoRace only reveals the current period after the betting cutoff. Aviator current-round output exposes the crash point only after the round has crashed; bet/cashout flows coordinate round state and worker health.
- Several dashboard arrays that are naturally per-user (notably referral/gift claims) are not capped. Treat this as a scale/performance follow-up, not a newly observed cross-user access bypass.

### C. Helpers/public aggregate contract — 2

- `nplus_is_admin()`: returns whether the current `auth.uid()` has the Admin profile role; exposes no user data.
- `nplus_recent_demo_activity(integer)`: the one anon-executable SECURITY DEFINER RPC. Its SQL clamps the lookback window to 5–1440 minutes and returns only game keys plus aggregate event counts; it does not return names, IDs, phone/email, bet selections, stake amounts or raw rows. Keep this bounded aggregate-only contract. Security Advisor remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable

## Confirmed live issues and candidate-only mitigations

The live definitions still do **not** include the candidate finite-numeric guard bundle. The live function review reconfirmed two material malformed-input cases:

1. `nplus_demo_safe_transfer(text,numeric)` assigns the input to a `numeric(14,2)` variable before validation and checks only NULL/positivity/rounding. PostgreSQL numeric NaN comparison semantics allow NaN to evade those particular checks; the candidate now validates the original input before narrowing.
2. `nplus_demo_admin_qualify_referral(uuid,numeric)` checks whether the supplied amount is below 500.00. PostgreSQL numeric NaN compares above finite values, so a threshold-only check is not sufficient; the candidate now rejects NULL/NaN/±Infinity explicitly.

Additional defense-in-depth in the candidate guard bundle checks deposit/withdraw request inputs before rounding/narrowing, stored amounts before Admin deposit approval and gift redemption, Admin gift creation, and Aviator/MotoRace/WINGO stake/auto-cashout inputs.

- Candidate migration: `supabase/migrations/20261027150000_guard_finite_numeric_rpc_inputs.sql`.
- Earlier source reference retained: `sql/NPLUS_PLAY_FINITE_NUMERIC_RPC_GUARDS_CANDIDATE_2026-10-27.sql`.
- Static source-order guard and disposable PostgreSQL numeric-semantics regression are wired into Static QA.
- The finite-amount replacements are **not deployed to production**. The relevant production functions therefore remain an open rollout risk until an approved migration plan, hosted testing and release approval permit a reviewed deployment.

## Auth plan limitation

The current Supabase organization is on the Free plan. Supabase's current Password security documentation says leaked-password protection is available on Pro and above: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection. No paid upgrade or Auth setting change was initiated. No-cost mitigation is to review supported minimum password length/complexity and rate limiting; leaked-password protection itself needs either owner-approved plan change or explicit risk acceptance.

## Product and release blockers still requiring owner evidence/approval

1. **Authoritative legacy schema history:** the 2026-10-15 backup lacks `manual_deposits`, `user_bank_details`, and `withdraw_requests`; none of the 40 recorded migration bodies creates those tables. The passing 40/40 local run used a schema-only bootstrap reconstructed from the current catalog. It is not canonical historical replay or proof of original owner/ACL/policy lineage.
2. **Hosted account acceptance:** signup/email OTP delivery, login, password recovery, Admin/non-Admin denial, deposit/withdrawal, wallet ledger, referral claim and hosted-browser tests still need safe synthetic accounts and an accessible test inbox.
3. **Referral rule contract:** earlier product brief described a 200-virtual-point qualifying request with a one-time 20-virtual-point inviter reward; the current deployed function/UI flow is based on a 500-point qualification and tier rules. Product owner must confirm the intended rule before release. Do not silently change rules or auto-credit accounts.
4. **Game rule approval:** K3/5D/TRX payout/return rules are not approved; all six live game flags must remain disabled. WINGO/MotoRace/Aviator hosted settlement journeys also require acceptance on the hosted environment.
5. **Remaining security risk acceptance:** the code-level review covered all 53 authenticated-callable function bodies, but CI and source inspection do not replace owner acceptance of the remaining Advisor warnings, numeric-guard deployment, hosted authorization tests, or the Free-plan leaked-password limitation.
6. **Final release:** PR #22 is still a draft. Merge/deployment and Pages/live-browser verification remain gated on the above evidence and explicit approval.

## Final conclusion

This is an expanded source/catalog review with candidate regression coverage, not a production certification. Production tables, grants, wallets, Auth settings, scheduler configuration and game flags were not changed by this review. Keep all six games disabled and do not treat the reconstructed replay as canonical history.
