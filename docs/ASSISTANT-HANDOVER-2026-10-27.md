# N+ PLAY + N+ ADMIN — Assistant-side handover for next release pass

Checked against GitHub on 2026-10-27.

## Current candidate
- PR #22: https://github.com/nplusplayofficial-cmyk/nplusplay/pull/22
- State at last refresh: OPEN, DRAFT, mergeable=true; base main.
- Branch: integration/release-candidate-2026-10-27
- Last full CI-green head before the action-runtime cleanup: 6507e437937dbc933e558c8442ea31741f65fec4 (44 commits, 91 changed files). The next commit updates GitHub Actions Node runtimes and adds current live schema evidence; new CI must pass on that commit.
- Repository default branch is main. No merge/deploy is authorized or performed.

## Current CI evidence on exact head
- Latest completed Static QA run 40485562957 (#619): success on head 6507e437937dbc933e558c8442ea31741f65fec4. Both static-qa and browser-smoke jobs succeeded; finite-amount guard, isolated PostgreSQL regression and legacy ACL guards passed.
- Latest completed Release Smoke run 40485562854 (#206): success on the same head.
- These workflows are candidate code/static/browser smoke checks; they do not close hosted authenticated journeys or canonical clean replay.
- Combined status API returned no commit status entries, so rely on the explicit workflow-run records and job details, not that empty status endpoint.
- These CI checks do not constitute hosted Supabase Auth/user-flow tests or clean canonical restore/replay acceptance.

## Candidate legacy ACL review
- Candidate migration supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql checks existence, owner=postgres, RLS enabled, and seven authenticated owner policies before revoking PUBLIC/anon direct privileges for manual_deposits, user_bank_details, withdraw_requests.
- It verifies anon has no table privileges, RLS remains enabled, and authenticated SELECT/INSERT/UPDATE grants remain for the listed expected operations.
- qa/test-legacy-table-privilege-hardening.sql covers disposable PostgreSQL; QA passed.
- qa/test-legacy-browser-route-readonly.cjs checks browser code does not query user_bank_details/withdraw_requests, and manual_deposits is SELECT-only in admin-deposits.html with no RPC/credit path; static guard passed.
- Script still is a candidate migration; not deployed. Review authenticated path expectations against real hosted tests before rollout.

## Existing release blockers (must remain blockers)
1. Canonical clean migration replay: 2026-10-15 backup lacks authoritative legacy schema for manual_deposits, withdraw_requests, user_bank_details. Bodies 39/40 only pass after QA-only empty schema fixtures and local ACL overlays. Not a clean replay; source/owner/ACL/policy lineage not fully restored.
2. Full current hosted tests with safe synthetic accounts: signup/email OTP, login, password recovery, Admin vs non-admin, deposit request/admin approve/reject/wallet ledger, withdrawal request/status-only review, and referral qualification + exactly-once tier claim. Current local E2E passes with rollback but does not replace hosted test.
3. Review the 53 authenticated SECURITY DEFINER findings function-by-function. One anonymous aggregate activity RPC may remain intentionally public if contract stays aggregate-only; document decision.
4. Leaked-password protection disabled on current Free plan; no paid upgrade or Auth setting change without approval. Document limitation/compensating controls.
5. K3/5D/TRX rules and server-side settlement not approved; keep disabled. Current candidate has game rules approval guard.
6. Final live browser/site verification only after release gates clear: GitHub Pages deployed commit, login/signup/navigation/Admin/demo wallet flows. Do not claim current live URL reflects candidate.

## Already verified/prepared; do not ask user to repeat
- Backup restore acceptance and 29 historical body fingerprints passed.
- Local 40-body replay only passed suffix 39/40 after three QA-only table overlays and ACL overlays.
- Local wallet/admin/referral E2E passed on disposable replay database using candidate referral-state migration; ended ROLLBACK.
- Final local security/ledger invariants passed; six game settings disabled.
- WINGO overload owner/ACL checked read-only; candidate regression test preserves owner/grants.
- Candidate ACL hardening and browser-route guard pass latest Static QA.

## Safety constraints
- No production wallet/user/game flags/RLS/ACL/scheduler changes without reviewed approval.
- Never run supabase db push to production, auto-merge, or deploy in the background.
- Do not invent historical table DDL or skip/fake migration history. Obtain authoritative newer backup/schema source.
- No paid Supabase branch/project or plan changes without explicit approval.
- Keep all 6 games disabled until each supported server settlement gate is approved.
- Demo/virtual credits only; no real-money betting or payouts.

## Next best assistant-side actions
- Continue read-only code audit focused on security-definer callable functions; pick specific high-risk categories and add candidate-only disposable regression guards where current code provides grounded contract.
- Review release checklist/doc contradictions so the newest head's evidence is consistent.
- No user action is needed for CI reruns unless a later commit changes tested files. User-side steps only become necessary for missing authoritative backup/source and hosted test accounts/inbox, which assistant connector cannot safely synthesize.

## Focused production read-only SECURITY DEFINER review (2026-10-27)

- Reviewed selected live definitions and ACLs for Admin wallet adjustment, game status, deposit approve/reject, status-only demo withdrawal review, referral qualification/claim, MotoRace result reveal, and WINGO Admin overload shape. No production mutation occurred.
- New report: [SECURITY DEFINER focused review](SECURITY-DEFINER-REVIEW-2026-10-27.md).
- Found a numeric validation issue in the live Admin referral qualification RPC: PostgreSQL NaN compares as >=500 and fits numeric(14,2). Candidate-only finite-amount guard is committed; the dedicated static guard and disposable PostgreSQL regression passed in run #618. Not deployed.
- Refreshed metadata scan: 69/69 public SECURITY DEFINER functions have owner postgres and a fixed search_path; 53 have authenticated EXECUTE and one aggregate Recent Activity function has anon EXECUTE. A regex pre-screen found zero authenticated-executable/anon-denied functions without a detectable auth.uid/admin-guard signal; this is only a triage heuristic, not closure of all 53 manual reviews.
- WINGO four/five-argument default overlap remains in live catalog; current admin-reports page invokes the five-argument signature. Keep candidate overload regression and canonical ordering review before any DDL.


## Additional work in current pending-resolution pass

- Read-only production schema inspection confirms the three legacy tables are present with RLS enabled; it also captures the exact current columns, constraints, indexes, seven RLS policies and current ACL metadata in [PRODUCTION-LEGACY-TABLE-SCHEMA-SNAPSHOT-2026-10-27.md](PRODUCTION-LEGACY-TABLE-SCHEMA-SNAPSHOT-2026-10-27.md).
- This snapshot is current live evidence, **not** historical source SQL. It improves reviewability but does not close the missing table-creation history or make the 40-body replay canonical.
- GitHub Actions workflows are being updated from checkout/setup-node v4 (Node 20 runtime warnings seen in the user's screenshots) to v5 (Node 24 runtime), with setup-node package-manager auto-caching disabled because these workflows do not need it.
- Production ACLs on the three legacy relations still give anon and authenticated broad table privileges even though RLS is enabled; the candidate ACL migration that revokes only PUBLIC/anon is not deployed. Do not apply it outside a reviewed rollout.


## Additional finite-amount defect (candidate-only; found 2026-10-27)

- Live read-only semantics confirmed an additional virtual-wallet integrity issue in `nplus_demo_safe_transfer(text,numeric)`: PostgreSQL NaN bypassed the previous positivity/precision checks. The function is authenticated-callable and anon-denied.
- Candidate-only replacement, static guard and dedicated disposable PostgreSQL test are now added. The fix validates the original numeric input before narrowing to `numeric(14,2)`; it preserves the user identity, wallet/Safe row locks, and ledger/transfer records.
- The new candidate has not passed CI until the workflow run on its exact HEAD completes, and no production function or grant was modified.


## Production migration history evidence update — 2026-10-27

- The previously missing/ambiguous **migration-body source mapping is now closed** for recorded bodies: 29 distinct SQL bodies were compared character-for-character against the archived files in the candidate branch; all matched. The other 11 of the 40 migration history rows repeat an earlier body exactly.
- Evidence: [PRODUCTION-MIGRATION-BODY-VERIFICATION-2026-10-27.md](./PRODUCTION-MIGRATION-BODY-VERIFICATION-2026-10-27.md). This was read-only inspection of stored migration statement text, not a production migration.
- The canonical replay blocker remains: none of the 40 recorded body rows creates `manual_deposits`, `user_bank_details`, or `withdraw_requests`; the later RLS/index migration references them only. The 2026-10-15 backup-derived baseline lacks those tables and current schema cannot prove their historical provenance.
- Latest code head: `d139925f8ef95764dceadb82974bd3901a12d2a0`. Release Smoke #208 succeeded; Static QA #621's static-qa job and both finite-amount regression tests succeeded. Its desktop/mobile browser-smoke job was still in progress during Chromium installation on last refresh. Refresh the run before treating all workflow jobs as completed.
- Production is unchanged. Do not merge/deploy until the clean replay/baseline, hosted journeys, security/release gates, and explicit approval are complete.


## Legacy table grants — narrowed candidate contract

- Read-only production catalog confirms broad authenticated direct table grants on all three legacy tables, including DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN.
- The candidate migration/test now retain authenticated SELECT on `manual_deposits` only (needed for the existing Admin read-only reconciliation page) and no direct browser-role grants on `user_bank_details` or `withdraw_requests`. Policy definitions/RLS remain unchanged in the candidate.
- This is a proposed candidate migration only. Production grants remain unchanged. Await Static QA on the latest commit and keep the canonical replay/hosted route gates open.


## Latest CI failure triage — 2026-10-27

Static QA run #622 exposed one stale assertion in the combined `qa/test-release-index-policy-migration.sql`: it still expected the previous authenticated INSERT/UPDATE grants after the candidate ACL contract was narrowed. The failure occurred in the fixture's post-migration assertion (not in SQL syntax or the browser smoke). The test is now being updated to assert the revised contract—authenticated SELECT-only on `manual_deposits`, no direct browser grants on `user_bank_details` / `withdraw_requests`, and all RLS/policies intact. The new run must pass before treating the ACL candidate as verified. Production ACLs remain unchanged.


## Legacy-table ACL regression follow-up — 2026-10-27

- The combined CI fixture had a stale assertion from the older authenticated grants-preserved contract; Static QA run #622 failed on that assertion. The assertion and standalone legacy ACL regression now match the candidate least-privilege plan.
- Candidate now keeps authenticated SELECT on `manual_deposits` only; authenticated direct table grants to `user_bank_details` and `withdraw_requests` are removed. No table rows, owner, RLS flags or policies are changed by this SQL.
- Production grants were not changed. Fresh Static QA on the latest commit is required; keep deployment blocked until it passes.


## CI syntax correction — 2026-10-27

- Static QA #624 identified a missing semicolon in the revised `qa/test-release-index-policy-migration.sql` final RAISE NOTICE statement. This was test-fixture SQL syntax, not a production migration failure.
- The semicolon has been fixed on the candidate branch; fresh Static QA and Release Smoke must pass on the correction commit before any release gate is marked green.
- Candidate ACL migration remains un-deployed; production is unchanged.


## Legacy ACL test SQL terminator — 2026-10-27

- On Static QA #626, the combined RLS/index-policy SQL test and finite Admin referral regression passed, but the separate legacy-table privilege test exposed a missing semicolon on its final RAISE NOTICE.
- That test-only terminator is corrected in this candidate commit. Production schema/grants remain unchanged. Fresh CI must verify the strict ACL assertions end-to-end.


## Latest candidate status — 2026-10-27 10:44 UTC (supersedes earlier run-pending notes)

- Current branch head before this status-only documentation refresh: `961b4e90fceaca339ab3b481411358ab7e7aea3b`; PR #22 is OPEN, DRAFT, and mergeable.
- Static QA run #627: `40490546126` completed SUCCESS. The static-qa and browser-smoke jobs both passed. Specifically, the combined RLS/index migration test, finite Admin referral guard and isolated PostgreSQL regression, standalone legacy-table privilege test, and desktop/mobile browser smoke all passed.
- Release Smoke run #214: `40490546120` completed SUCCESS on the same head.
- The legacy-table candidate ACL test now verifies that authenticated has only direct SELECT on `manual_deposits`, no direct table privileges on `user_bank_details`/`withdraw_requests`, no anon/PUBLIC privileges, and RLS + named policies stay intact.
- Production read-only status remains: six game settings, zero enabled; both production finite-number guards are still absent because candidate SQL was not deployed; historical source verification is read-only; no production schema/ACL/wallet/Auth/scheduler change was made.
- The all-40 migration history body source mapping is closed at 29 unique exact bodies plus 11 exact repeats; the clean canonical replay is still blocked by missing trusted pre-history creation source for the three legacy relations.
- Latest production Pages deployment observed is still Oct 23 main commit `680238f2428416faf44df0dced6f907d4cea7f08`. Do not claim the candidate is live or the site fully verified.


## Expanded finite-numeric RPC hardening — 2026-10-27 (candidate-only)

- Read-only review identified eight authenticated numeric inputs that need explicit finite-value checks: demo deposit request, demo withdrawal request, Admin gift-code creation, Aviator stake/auto-cashout, MotoRace stake, WINGO stake, Safe transfer, and Admin referral qualification.
- Added candidate bundle `sql/NPLUS_PLAY_FINITE_NUMERIC_RPC_GUARDS_CANDIDATE_2026-10-27.sql` with full current function definitions and finite guards; deposit/withdraw input is checked before rounding/narrowing.
- Added static source-order guard and dedicated disposable PostgreSQL semantic test into Static QA. The exact-head CI result is required before marking the change verified. Production functions, ACLs, wallets and game settings remain unchanged.


## Stored-amount defense-in-depth — 2026-10-27

- Added two further candidate checks to the 10-function bundle: Admin deposit approval rejects malformed persisted request amounts before wallet credit/ledger writes; gift redemption rejects malformed stored gift amounts before claim-count/wallet updates.
- Read-only ACL review confirms authenticated has SELECT-only access to `deposit_requests`/`withdrawal_requests` and no direct grants on gift-code/game-bet tables.
- Aggregate read-only checks across 21 numeric amount/balance/stake/payout columns reported zero current NaN/Infinity/-Infinity rows.
- Candidate bundle is not deployed. New Static QA / Release Smoke must pass on the next head; production remains unchanged.


## Function group audit and data integrity snapshot — 2026-10-27

- Read-only review extended to Admin read-only reports, WINGO Admin mutation overloads, deposit approve/reject, status-only withdrawal review, game status allow-list/settlement prerequisites, Aviator cashout, MotoRace current/reveal timing, attendance/gift/referral reward claims, user history/my-bet read APIs, and support/VIP dashboards. See the SECURITY DEFINER review report for specific observations.
- All 69 public SECURITY DEFINER functions remain postgres-owned with fixed search_path; 53 are authenticated-executable; only aggregate-only Recent Activity is anon-executable. anon/authenticated/PUBLIC have no CREATE privilege on public schema.
- A read-only scan over 21 current numeric amount/balance/stake/payout fields found zero NaN/±Infinity rows.
- Targeted review is improved, but do not mark every one of the 53 Advisor findings closed without per-finding review evidence; remaining Advisor triage is still a release checklist item.


- Deposit approval candidate now enforces exactly the same 100–50,000 virtual-point range as the request-creation RPC, plus finite-value validation. This is defense-in-depth before wallet/ledger writes; production remains unchanged.


## Latest assistant-side completion checkpoint — 2026-10-27

### Completed on the integration candidate
- Exact body-source mapping for the 40 stored migration-history rows: 29 distinct SQL bodies match archived SQL character-for-character; 11 rows are exact repeats.
- GitHub repository-wide code search over the available 24 branches found no authoritative `CREATE TABLE` DDL for the three legacy relations `manual_deposits`, `user_bank_details`, or `withdraw_requests`. Current live catalog snapshot is documented but is not a substitute for historical origin.
- Latest code candidate before this documentation refresh: `3ba6c56e591cd522f07e2d7cc6ff1be2f6787ced`; Static QA #632 and Release Smoke #220 passed on that exact head.
- Finite numeric guard candidate bundle covers ten authenticated SECURITY DEFINER functions: Safe transfer, referral qualification, deposit/withdraw request, Admin gift code creation, Aviator bet stake/auto-cashout, MotoRace stake, WINGO stake, Admin deposit approval, and gift redemption. Existing amount bounds and business logic remain; approval matches request bounds of 100–50,000 virtual points.
- Candidate legacy ACL migration/test retains authenticated SELECT on `manual_deposits` only, no browser-role direct grants to `user_bank_details`/`withdraw_requests`, removes PUBLIC/anon table grants, and asserts RLS/policies remain.
- Read-only scan of 21 monetary fields found zero stored non-finite values.
- Full catalog triage: 69/69 SECURITY DEFINER functions are postgres-owned with fixed search paths; 53 authenticated-executable; only aggregate Recent Activity is anon-executable; no authenticated write-pattern function lacked a detected actor/Admin guard signal in the inventory.

### Still blocking final release
1. Trusted original pre-history DDL/deployment provenance for the three legacy tables, needed for clean canonical replay from the supplied backup.
2. Hosted signup/OTP/login/password recovery and safe synthetic-account Admin/wallet/deposit/withdrawal/referral/game journeys.
3. Formal per-finding risk acceptance for the remaining Advisor warnings and explicit review/approval of the candidate SQL bundle before any production rollout.
4. K3/5D/TRX server settlement rules remain unapproved; all six game settings remain disabled pending a supported launch matrix.
5. Final Pages/browser verification must be performed after the release decision; current live Pages deployment remains the older main build, not this candidate.

No production schema/ACL/wallet/game/Auth/scheduler state was modified in this work. PR #22 remains OPEN and DRAFT.


## Latest live Advisor and table-access recheck — 2026-10-27

- Supabase Security Advisor currently reports: 20 RLS-enabled/no-policy tables (INFO), one anon SECURITY DEFINER (WARN), 53 authenticated SECURITY DEFINER functions (WARN), and leaked-password protection disabled (WARN). Performance Advisor reports 20 unused indexes (INFO).
- Verified every one of the 20 no-policy tables has RLS enabled and no direct SELECT/INSERT/UPDATE/DELETE privileges for either `anon` or `authenticated`. These are not grounds to add broad policies.
- The one anonymous RPC is the intentional aggregate-only bounded `nplus_recent_demo_activity(integer)`. Authenticated SECURITY DEFINER warnings are generic lints; retain function-specific authorization, not blind global revocation.
- Remaining actionable account configuration is **Prevent use of leaked passwords** under Supabase Authentication → Sign In / Providers → Email, where available on current plan. Supabase docs: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection. Connected tools do not expose an Auth config update action; no unsupported SQL or hidden config manipulation was attempted.
- Do not drop the 20 unused-index candidates without workload evidence.
