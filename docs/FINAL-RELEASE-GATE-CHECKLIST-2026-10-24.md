# N+ PLAY + N+ ADMIN — Consolidated release gate checklist (2026-10-24)

## Release decision

**Not release-ready yet.** The local 2026-10-15 backup restore and all 29 captured SQL source fingerprints are verified, but a clean 40-body replay is blocked at body 39 because the restored baseline lacks `public.manual_deposits`. Current production has that table, while no body in the captured 40-row history creates it. This baseline/history gap, authenticated hosted-browser tests, cross-PR integration, and approved K3/5D/TRX rules remain release blockers.

No production migrations, schema DDL, wallet/ledger data, user records, game settings, ACLs, or cron jobs were changed as part of these latest audit updates.

## Workstream status

| # | Workstream | What is now verified / prepared | Remaining to close |
|---:|---|---|---|
| 1 | Migration source reconciliation + backup acceptance | Read-only live history has 40 rows, one stored SQL statement each, 29 unique body fingerprints, and 11 duplicate-body pairs. Exact source fingerprints pass 29/29. The private 2026-10-15 dump was restored locally with owner/ACL checks enabled; wallet/ledger and security-object acceptance passed. Local replay passed bodies 1–38; body 39 (`20261023092858`) fails because `public.manual_deposits` is absent from the dump-derived baseline. Read-only production catalog shows the table exists, and the 40 captured history bodies contain no CREATE TABLE for it. [Detailed baseline-drift report](REPLAY-BASELINE-DRIFT-2026-10-27.md). | Resolve the baseline/history gap using an authoritative newer backup or a reviewed canonical pre-history schema source for `manual_deposits`. The QA-only schema-overlay suffix check, if run, must not be represented as a clean 40-body replay. Preserve owner/ACL review and compare final state against production. Do not skip body 39 or alter production to make replay pass. |
| 2 | Production database security audit | Current Advisor snapshot and read-only function/privilege/RLS review recorded in [PR #21 security report](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/21). All 20 RLS-without-policy tables in the Advisor set have no anon/authenticated direct table privileges. A body-marker scan found all 54 browser-callable SECURITY DEFINER functions have fixed search paths; only the intentional aggregate activity RPC lacks auth.uid()/nplus_is_admin markers. Generic positive wallet credits are blocked; phone lookup EXECUTE is revoked for browser roles; all six games are off. [PR #20](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/20) has candidate-only legacy anonymous grant hardening, not applied to production. | Re-test Admin RPCs using signed-in non-admin identities. **Live catalog review confirmed that both 4-arg and 5-arg `nplus_admin_set_wingo_demo` overloads have overlapping defaults, making 4-arg calls ambiguous.** Candidate-only patch `sql/NPLUS_PLAY_WINGO_OVERLOAD_DISAMBIGUATION_2026-10-24.sql` drops/recreates only the five-argument overload without CASCADE, because CREATE OR REPLACE cannot remove existing defaults. `qa/test-wingo-overload-disambiguation.sql` reproduces the overlapping-default ambiguity before applying the candidate, then verifies four-/five-argument resolution, intended grants, fixed search_path, SECURITY DEFINER and non-admin rejection in disposable PostgreSQL. The latest candidate CI passed; production application remains blocked on source/order, dependencies, owner/ACL and private backup/replay review. The candidate is not applied to production; canonical migration source/order and the private backup/replay gates remain required. After legacy route replacement, review `manual_deposits` / `user_bank_details` grants. Resolve leaked-password protection notice if supported with no unapproved cost. |
| 3 | Login / signup / OTP / password reset | Static checks and existing auth-repair candidate code/docs are available; main static QA runs. | Test actual email OTP delivery/verification, signup/profile/wallet initialization, password recovery, expired/invalid codes and mobile return navigation using a controlled test account/inbox on a safe test deployment. No real-user account changes. |
| 4 | Wallet / Admin / referral | PR #16 current code head has green static QA + browser smoke and disposable PostgreSQL suites for wallet request/referral/admin/privilege behavior. Read-only production wallet/ledger snapshot showed no negative wallet, ledger arithmetic or wallet/latest-ledger mismatch. | Run the isolated wallet/Admin/referral transaction/rollback test and real authenticated browser flow with synthetic test accounts; verify request replay and non-admin rejection. Preserve legacy manual deposit rows; no auto-approval or auto-credit. |
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
- Local replay bodies **1–38 PASS**. Body **39/40** stops at `CREATE INDEX ... ON public.manual_deposits` because the relation does not exist in the restored 2026-10-15 baseline.
- Read-only production catalog confirms `public.manual_deposits` exists, is owned by `postgres`, and has RLS enabled. The read-only search of all stored migration bodies found only version `20261023092858` mentioning this relation; that body references but does not create it.
- Conclusion: the restored baseline and captured migration sequence omit a prerequisite/out-of-band schema event. The strict clean replay remains blocked. A QA-only schema overlay may rehearse bodies 39–40 but does not establish a clean full replay or full data parity. See [baseline-drift report](REPLAY-BASELINE-DRIFT-2026-10-27.md).
- No production database mutation was performed. The legacy table's broad `anon` and `authenticated` ACLs remain a separate review item for PR #20; do not silently change them in production.

## Cross-PR integration gate (reviewed 2026-10-25)

The draft branches are independent branches from `main`, not a pre-integrated release branch. Before merging, reconcile shared files and run CI on the combined candidate:
- PRs #17, #18 and #19 all edit `.github/workflows/nplus-play-qa.yml` around the same QA step area. Merge their workflow additions together deliberately; preserve all game-rule, activity/Aviator, migration-fingerprint, WINGO-overload, and privacy tests, and ensure disposable database names are unique.
- PRs #16 and #19 both edit `qa/test-demo-referrals.sql`. Keep the legacy 200/20 test clearly labeled as legacy and ensure the current Admin-verified 500-point qualification/tier-claim contract is tested by PR #16's separate `qa/test-wallet-admin-referral-e2e.sql`; do not mistake the legacy test passing for current referral acceptance.
- Candidate WINGO overload patch now captures and restores the pre-existing function owner around DROP/CREATE and has a disposable regression assertion for owner preservation. It still requires the local restored-database replay, dependency check, and confirmation of the actual deployed owner/ACL before any rollout; it is not a canonical migration and must not be applied to production directly.
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
