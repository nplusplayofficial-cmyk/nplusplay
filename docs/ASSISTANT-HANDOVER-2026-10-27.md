# N+ PLAY + N+ ADMIN — Assistant-side handover for next release pass

Checked against GitHub on 2026-10-27.

## Current candidate
- PR #22: https://github.com/nplusplayofficial-cmyk/nplusplay/pull/22
- State at last refresh: OPEN, DRAFT, mergeable=true; base main.
- Branch: integration/release-candidate-2026-10-27
- Last pre-guard head: 2fdedd6db4e7242d3ade48f3a108fffa4c0b29d2 (42 commits, 87 changed files, +12,180/-1,016).
- The next candidate commit adds a finite-number guard for Admin referral qualification plus a dedicated disposable SQL regression; fresh CI is required on that new head.
- Repository default branch is main. No merge/deploy is authorized or performed.

## Current CI evidence on exact head
- Latest completed pre-guard Static QA run 40484241118 (#617): success on head 2fdedd6db4e7242d3ade48f3a108fffa4c0b29d2; both static-qa and browser-smoke jobs succeeded, including the disposable legacy privilege SQL test and legacy-browser-route-readonly guard.
- Latest completed pre-guard Release Smoke run 40484241123 (#204): success on the same head.
- Candidate-only finite-amount guard tests were added after those runs; do not count the new head as passing until its new Actions runs complete.
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
- Found a numeric validation issue in the live Admin referral qualification RPC: PostgreSQL NaN compares as >=500 and fits numeric(14,2). Candidate-only finite-amount guard and disposable regression tests are being added to the integration branch. Not deployed.
- WINGO four/five-argument default overlap remains in live catalog; current admin-reports page invokes the five-argument signature. Keep candidate overload regression and canonical ordering review before any DDL.
