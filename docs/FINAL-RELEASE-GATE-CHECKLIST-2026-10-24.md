# N+ PLAY + N+ ADMIN — Consolidated release gate checklist (2026-10-24)

## Release decision

**Not release-ready yet.** The local 2026-10-15 backup restore and all 29 captured SQL source fingerprints are verified. Bodies 39/40 passed only after QA-only empty schema overlays for three missing legacy tables; this is not a clean full replay. Wallet/ledger ACL parity and request-table ACL parity overlays passed. Final local invariants passed after the candidate qualified-referral-state migration; wallet/Admin/referral E2E passed with transaction rollback. Baseline/schema/ACL lineage, authenticated hosted-browser tests, and approved K3/5D/TRX rules remain release blockers. The integrated candidate's Static QA, browser smoke, and Release Smoke all pass on the latest head.

No production migrations, schema DDL, wallet/ledger data, user records, game settings, ACLs, or cron jobs were changed as part of these latest audit updates.

## Workstream status

| # | Workstream | What is now verified / prepared | Remaining to close |
|---:|---|---|---|
| 1 | Migration source reconciliation + backup acceptance | Read-only live history has 40 rows, 29 unique body fingerprints, and 11 duplicate-body pairs. Source fingerprints pass 29/29 and backup restore acceptance passes with owner/ACL restoration. Bodies 1–38 passed against the restored baseline; bodies 39–40 passed after a QA-only three-table empty schema overlay. Both wallet/ledger and request-table browser-role ACL overlays were applied locally after snapshotting the original ACLs/owner drift. Final local invariant SQL passed, including all six games off, no browser direct wallet/ledger/request writes, phone-enumeration revocation, generic wallet-credit guard, server-only Aviator worker/cron, WINGO Admin authorization, aggregate-only Recent Activity, and wallet/ledger arithmetic. [Detailed baseline/ACL drift report](REPLAY-BASELINE-DRIFT-2026-10-27.md). | Obtain an authoritative newer backup or reviewed canonical pre-history schema sources for all three legacy tables and reconcile full schema/ACL lineage. The overlay-based suffix/final-state check must not be represented as a clean 40-body replay. Do not skip assertions or alter production to make replay pass. |
| 2 | Production database security audit | Current Advisor snapshot and read-only function/privilege/RLS review recorded in [PR #21 security report](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/21). All 20 RLS-without-policy tables in the Advisor set have no anon/authenticated direct table privileges. A body-marker scan found all 54 browser-callable SECURITY DEFINER functions have fixed search paths; only the intentional aggregate activity RPC lacks auth.uid()/nplus_is_admin markers. Generic positive wallet credits are blocked; phone lookup EXECUTE is revoked for browser roles; all six games are off. [PR #20](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/20) has candidate-only legacy anonymous grant hardening, not applied to production. | Re-test Admin RPCs using signed-in non-admin identities. **Live catalog review confirmed that both 4-arg and 5-arg `nplus_admin_set_wingo_demo` overloads have overlapping defaults, making 4-arg calls ambiguous.** Candidate-only patch `sql/NPLUS_PLAY_WINGO_OVERLOAD_DISAMBIGUATION_2026-10-24.sql` drops/recreates only the five-argument overload without CASCADE, because CREATE OR REPLACE cannot remove existing defaults. `qa/test-wingo-overload-disambiguation.sql` reproduces the overlapping-default ambiguity before applying the candidate, then verifies four-/five-argument resolution, intended grants, fixed search_path, SECURITY DEFINER and non-admin rejection in disposable PostgreSQL. Read-only production catalog review on 2026-10-27 confirms both overloads are owned by `postgres`, SECURITY DEFINER, fixed `search_path=public`, and grants only to `authenticated` and `service_role`; `anon` has no EXECUTE. The owner-preserving candidate and disposable regression test preserve owner, grants, fixed search_path and Admin guard. This resolves the owner/ACL evidence check, but the candidate still cannot be applied until canonical migration source/order, dependency review and clean backup/replay gates are addressed. After legacy route replacement, review `manual_deposits` / `user_bank_details` grants. Resolve leaked-password protection notice if supported with no unapproved cost. |
| 3 | Login / signup / OTP / password reset | Static checks and existing auth-repair candidate code/docs are available; main static QA runs. | Test actual email OTP delivery/verification, signup/profile/wallet initialization, password recovery, expired/invalid codes and mobile return navigation using a controlled test account/inbox on a safe test deployment. No real-user account changes. |
| 4 | Wallet / Admin / referral | PR #16 current code head has green static QA + browser smoke. On the disposable local replay DB, the candidate-only follow-up migration `20261027120000_allow_qualified_demo_referral_state.sql` resolved both legacy constraint blockers by allowing `pending`, `qualified`, and `rewarded`. The corrected wallet/Admin/referral E2E now passes: deposit idempotency/approval/rejection and Admin authorization; Admin wallet adjustment/ledger and positive-credit protection; referral uniqueness/self-referral/qualification/one-time tier claim; withdrawal idempotency/status-only Admin review. The E2E transaction ended with `ROLLBACK`; final local security/ledger invariants also passed. **Separate read-only production check confirms this fix is not deployed:** the live status constraint still permits only `pending`/`rewarded`, and migration version `20261027120000` has zero history rows. | Hosted authenticated wallet/Admin/referral flows with synthetic test accounts are still required. Preserve legacy manual deposit rows; no auto-approval or auto-credit. Do not deploy the follow-up migration to production before full backup/replay and release review. |
| 5 | Games / payout rules | PR #17 safety gates are green in static and release-smoke CI. All six production game flags are currently disabled. | K3/5D/TRX payout/return formulas need explicit product approval. Server-owned settlement for all offered games must pass review/integration tests before any flags are enabled. Do not invent or infer payout rules and do not enable games early. |
| 6 | Recent activity + Aviator recovery | PR #18 latest CI has passed source/SQL/browser smoke. Read-only production checks verified active pg_cron job nplus-aviator-worker every second, 84,957 successful worker runs in the observed 24-hour window, recent successful worker-health heartbeat and zero consecutive failures at the checked time. | Homepage feed code is not merged/deployed or verified in the hosted site. Complete authenticated hosted activity/history test and recovery edge-case acceptance after migration/backup gates. Scheduler SQL in the evidence folder is not a canonical migration and must not be rerun. |
| 7 | Final release / live URL | Current main Pages deployment stays untouched; source branches remain drafts. | After all prior gates pass, merge only the reviewed PRs in a planned order, run CI on the exact merge commit, verify GitHub Pages build/deployment, then test login/account/Admin/navigation on the actual hosted URL. Publish the final link only after runtime verification. |

## Latest CI evidence (candidate branches, not production release proof)

- Wallet/Admin/referral PR #16: [Static QA + browser smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070098542), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070098435).
- Game rules gate PR #17: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386753), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386758).
- Activity/Aviator PR #18 latest: [Static QA + browser smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079438773), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079438766).
- Migration source archive PR #19 latest verified code head: [Static QA + exact duplicate-pair, WINGO overload, Recent Activity privacy, and restore-script safety checks](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40080182395), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40080182400). A later documentation-only branch refresh will receive its own CI run.
- Production security snapshot PR #21: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40073282012), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40073282009).
- Legacy anonymous table-grant candidate PR #20: [Static QA + disposable SQL suite](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135909), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135893).

These CI runs use isolated disposable PostgreSQL and/or local static/browser smoke. They are not proof of a full authenticated production browser test or disaster-recovery acceptance.

## Replay result and baseline drift (checked 2026-10-27)

- Backup restore acceptance: **PASS** with owners/ACLs preserved.
- Captured SQL source fingerprint audit: **PASS 29/29**; exact ordered history: **PASS 40 rows**.
- Local replay bodies **1–38 PASS**. Body **39/40** first stops at `CREATE INDEX ... ON public.manual_deposits`; guarded fixture attempts then find `public.withdraw_requests` and `public.user_bank_details` missing before creating any fixture objects.
- Read-only production catalog confirms all three legacy tables exist, are owned by `postgres`, and have RLS enabled. Captured history body `20261023092858` references the relations but does not create them.
- A QA-only three-table empty schema overlay was applied to the disposable partial replay DB; each legacy fixture table had zero rows. Bodies 39/40 passed on that reconstructed schema shape.
- Wallet/ledger and request-table ACL overlays each snapshotted pre-overlay owner/grants and aligned the local replay database with the reviewed browser-role privileges; the request overlay also normalized the observed local `withdrawal_requests` owner from `supabase_admin` to `postgres`.
- Final local invariant SQL then passed all listed checks and emitted the summary counts shown in the baseline-drift report.
- This is not a clean canonical 40-body replay from the 2026-10-15 backup. The backup baseline/history does not reconstruct three legacy tables or the observed ACL/owner state. Obtain and review an authoritative newer backup or canonical pre-history schema source before calling backup/replay parity complete.
- No production database mutation was performed. Broad `anon` / `authenticated` ACLs on the legacy `manual_deposits` table remain a separate PR #20 review item. See [baseline-drift report](REPLAY-BASELINE-DRIFT-2026-10-27.md).
- No production database mutation was performed. Broad `anon` / `authenticated` ACLs on the legacy `manual_deposits` table remain a separate PR #20 review item.

## Cross-PR integration gate (reviewed 2026-10-25)

The draft branches are independent branches from `main`, not a pre-integrated release branch. Before merging, reconcile shared files and run CI on the combined candidate:
- PRs #17, #18 and #19 all edited `.github/workflows/nplus-play-qa.yml`. Their overlap is reconciled on integration PR #22; the combined workflow preserves game-rule, activity/Aviator, migration-fingerprint, WINGO-overload, legacy privilege and privacy tests, with distinct disposable database names. Current combined Static QA/browser smoke and Release Smoke both pass.
- PRs #16 and #19 both edit `qa/test-demo-referrals.sql`. Keep the legacy 200/20 test clearly labeled as legacy and ensure the current Admin-verified 500-point qualification/tier-claim contract is tested by PR #16's separate `qa/test-wallet-admin-referral-e2e.sql`; do not mistake the legacy test passing for current referral acceptance.
- Candidate WINGO overload patch captures/restores the pre-existing owner around DROP/CREATE and has a disposable regression assertion for owner preservation. Read-only production review confirmed owner `postgres`, SECURITY DEFINER, `search_path=public`, grants to `authenticated` and `service_role`, and no `anon` EXECUTE; candidate test matches that contract. Canonical migration source/order, dependency check and clean backup/replay remain required before rollout; do not apply this standalone SQL directly to production.
- PR #20's legacy table grant hardening is separate from the route change in PR #16. Review the final merged browser call paths and least-privilege grants together before deciding whether and when to apply it.

Do not merge any draft PR as-is simply because its individual CI is green. A combined candidate must pass the full QA workflow after conflict resolution, and all backup/replay/authenticated-hosted tests remain release blockers.

## Exact user-PC tasks after assistant-side preparation

### A. Backup restore + 40-row migration replay

The assistant-side branch now includes both local scripts. These commands act only inside the existing local Docker restore lab; they do not connect to production.

```powershell
# Start the existing local restore lab if it is not already running
Set-Location "$HOME\Projects\nplusplay-restore-lab-v2"
npx supabase start

# Fetch the reviewed audit scripts (do not upload the private backup)
Set-Location "$HOME\Projects"
git clone --branch audit/migration-body-fingerprints-2026-10-24 https://github.com/nplusplayofficial-cmyk/nplusplay.git nplusplay-restore-acceptance
Set-Location "$HOME\Projects\nplusplay-restore-acceptance"

# First restore with ownership/ACL checks enabled; second replay all 40 bodies
.\qa\restore-backup-acceptance.ps1
.\qa\replay-live-migration-sequence.ps1
```

The first script requires the private backup at $HOME\NPLUS-PLAY-DB-BACKUP\nplus-play-full-2026-10-15.dump. It creates a new local database named nplus_restore_acceptance_20261024. The second checks that restored database, creates a separate local clone named nplus_migration_replay_20261024, then replays the captured 40 migration bodies in original order.

If a command fails, **stop at that point** and record only the failing version plus a redacted error message. Do not add --no-owner/--no-acl, skip a failed migration, drop any database, share the private dump, or run anything against production. A failed replay must be investigated, not bypassed.

### B. Authentication and wallet/Admin runtime tests

- Use a controlled test account and inbox to test signup, email OTP verification, password reset, invalid/expired code, profile/wallet initialization, authenticated wallet request/approval, referral claim replay, Admin/non-admin authorization, desktop and mobile navigation.
- Keep test credentials private. Never share passwords, service-role/secret keys, JWTs, database connection strings or private database rows.
- Do not write test transactions into a real member's wallet; use an isolated environment and synthetic test accounts.

### C. Product decision + release approval

- Decide K3/5D/TRX virtual-demo payout/return formulas before server-settlement changes can be approved.
- Review and approve the final merge order only after backup restore, replay, authenticated E2E, security and game-gate checks pass.

## Safety prohibitions

- Do not upload or commit the private dump archive.
- Do not edit supabase_migrations.schema_migrations to make source counts match.
- Do not run recovered files under docs/recovered-live-migration-sql-2026-10-23/; they are evidence, not deployable canonical migrations.
- Do not reset balances, delete user records, or enable games as a shortcut.
- Do not merge draft PRs #2, #6, #16–#21 blindly. Some are candidate fixes/audit evidence, not releases.
