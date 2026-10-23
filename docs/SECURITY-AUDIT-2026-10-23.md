# N+ PLAY — Live security audit (2026-10-23)

## Scope and result

Read-only catalog inspection was run against Supabase project `pcrxlqduygvzchzxsmdv`. Authorization probes ran inside an explicit transaction and were rolled back. No user rows or wallet balances were changed, and no production grants or policies were modified.

| Check | Live result | Assessment |
|---|---:|---|
| Public-schema `SECURITY DEFINER` functions | 69 | Reviewed catalog metadata and exposed-call set |
| `SECURITY DEFINER` functions callable by `authenticated` | 53 | Intentional RPC/guard surface; function bodies must enforce caller scope |
| Exposed `SECURITY DEFINER` functions with neither `auth.uid()` nor `nplus_is_admin()` in the body | 1 | `nplus_recent_demo_activity(integer)`, public aggregate exception below |
| `SECURITY DEFINER` functions without an explicit function `search_path` setting | 0 | No missing setting found |
| RLS-enabled public tables with no policies | 20 | All had zero direct `anon` or `authenticated` SELECT/INSERT/UPDATE/DELETE privileges |
| `anon`/ `authenticated` can create objects in `public` schema | No / No | No public-schema CREATE privilege found |
| Admin-sensitive RPC denial probes | 20/20 denied non-admin | All test calls ran in a transaction and were rolled back |
| Generic positive wallet credit probe | Blocked | `nplus_wallet_change(+1, 'GAME_WIN', ...)` raised SQLSTATE 42501 |
| Security Advisor warnings | Still present | Expected linter warnings remain; see below |

## Why the 20 RLS-without-policy tables are not opened up

The current tables below are internal storage for server-authoritative game rounds/bets, worker health, referrals, virtual gift claims, attendance, VIP state, safe transfers, and support requests. In the live catalog, each table had RLS enabled and **no direct privileges** for either API client role. The table ACLs listed `postgres` and `service_role` only.

- `nplus_aviator_demo_bets`
- `nplus_aviator_demo_rounds`
- `nplus_aviator_worker_health`
- `nplus_demo_attendance_claims`
- `nplus_demo_gift_claims`
- `nplus_demo_gift_codes`
- `nplus_demo_referral_bonus_claims`
- `nplus_demo_referral_campaign`
- `nplus_demo_referral_codes`
- `nplus_demo_referral_qualifications`
- `nplus_demo_referral_tier_rules`
- `nplus_demo_referrals`
- `nplus_demo_safe_balances`
- `nplus_demo_safe_transfers`
- `nplus_demo_support_requests`
- `nplus_demo_vip_state`
- `nplus_moto_demo_bets`
- `nplus_moto_demo_rounds`
- `nplus_wingo_demo_bets`
- `nplus_wingo_demo_rounds`

**Decision:** preserve the internal-only ACL/RLS posture. Do not add broad policies just to silence the INFO-level linter. User-visible access is through guarded RPCs.

## SECURITY DEFINER function controls

The live catalog showed 69 public `SECURITY DEFINER` functions, each with an explicit function-level `search_path`. Of functions executable by an API client role, only `nplus_recent_demo_activity(integer)` lacked a textual `auth.uid()` or `nplus_is_admin()` call in its body.

That exception is intentional for the homepage's recent-activity summary. Its body returns only `game_key` and `activity_count` for recent WINGO, MotoRace, and Aviator bets; it does not return user identifiers, bet selections, individual amounts, or wallet balances. The anonymous EXECUTE privilege remains intentional for this read-only aggregate.

The remaining authenticated-callable SECURITY DEFINER RPCs include user-scoped wallet, game, referral, attendance, gift, support, and admin operations. Their EXECUTE privilege is not itself proof of a vulnerability: each callable privileged function must check the current actor and constrain any returned or changed rows. No blanket revoke was applied, because many of these RPCs are used by the app and depend on their privileged execution context.

## Authorization probes

The following admin-sensitive RPC calls were executed using a real non-admin profile as the transaction-scoped JWT subject. Every call raised an admin/administrator authorization error before an operation could complete; the transaction was rolled back.

- `nplus_admin_adjust_demo_wallet`
- `nplus_admin_clear_wingo_manual`
- `nplus_admin_commission_summary`
- `nplus_admin_deposit_summary`
- `nplus_admin_resolve_demo_withdrawal`
- `nplus_admin_save_wingo_manual`
- `nplus_admin_set_wingo_demo` (5-argument overload used by the current page)
- `nplus_admin_user_directory`
- `nplus_admin_user_transactions`
- `nplus_admin_wingo_live_bets`
- `nplus_admin_wingo_round_summary`
- `nplus_approve_deposit`
- `nplus_reject_deposit`
- `nplus_demo_admin_create_gift_code`
- `nplus_demo_admin_qualify_referral`
- `nplus_demo_admin_referrals`
- `nplus_demo_admin_support_list`
- `nplus_demo_admin_support_update`
- `nplus_demo_admin_vip_dashboard`
- `nplus_set_game_status`

A separate live probe verified that a caller-supplied positive generic `GAME_WIN` credit is blocked by `nplus_wallet_change` with SQLSTATE `42501`.

## Follow-up finding: ambiguous WINGO admin overload

The catalog contains both four-argument and five-argument overloads of `nplus_admin_set_wingo_demo`, and the four-argument overload has defaults that overlap the five-argument signature. A four-argument direct call failed with PostgreSQL error `42725: function ... is not unique` before the authorization guard could run. This is an RPC/signature ambiguity, **not evidence of a privilege bypass**. The current `admin-reports.html` source supplies `p_size` and calls the five-argument overload; the five-argument version correctly denied the non-admin test subject.

Keep this cleanup separate from the audit. Reconcile the migration history first (see `docs/SUPABASE-MIGRATION-SOURCE-MAP-2026-10-23.md`), then remove or normalize the redundant overload in a reviewed migration and add a regression test. Do not change the live schema ad hoc while migration history is still unreconciled.

## Security Advisor warnings that remain

- `RLS Enabled No Policy` — INFO, 20 tables. Catalog ACL checks above confirm no direct API client grants; these are intentionally internal-only.
- `Public Can Execute SECURITY DEFINER Function` — WARN, one function: `nplus_recent_demo_activity(integer)`. Kept public because it provides aggregate-only homepage activity as described above.
- `Signed-In Users Can Execute SECURITY DEFINER Function` — WARN, 53 functions. The linter does not establish a flaw just from EXECUTE rights; per-function caller checks remain required and should be regression-tested as the RPC surface changes.
- `Leaked Password Protection Disabled` — WARN, one Auth setting. This is separate from SQL function/table authorization and remains a product-plan/configuration decision; do not upgrade the project automatically.

## Limitations / release gates

This is a live catalog and authorization spot audit, not a complete exploit assessment of every argument combination or a live browser test. Continue to keep all six games disabled until the server settlement/browser end-to-end tests pass. The WINGO overload ambiguity, unresolved migration source/replay work, and leaked-password setting remain follow-up items. No production schema or permissions were changed during this audit.
