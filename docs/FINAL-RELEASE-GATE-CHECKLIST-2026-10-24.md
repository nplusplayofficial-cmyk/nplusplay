# N+ PLAY + N+ ADMIN — Consolidated release gate checklist (2026-10-24)

## Release decision

**Not release-ready yet.** Source/static/disposable QA is green for the current wallet-route, game-gate, activity/Aviator, and migration-evidence branches, but the outstanding local backup restore, clean migration replay, authenticated hosted-browser tests, and approved K3/5D/TRX rules are release blockers.

No production migrations, schema DDL, wallet/ledger data, user records, game settings, ACLs, or cron jobs were changed as part of these latest audit updates.

## Workstream status

| # | Workstream | What is now verified / prepared | Remaining to close |
|---:|---|---|---|
| 1 | Migration source reconciliation + backup acceptance | Live history read-only snapshot has 40 rows, one stored SQL statement each, 29 unique body fingerprints, 11 exact duplicate-body pairs. Recovered-body evidence archive contains 29 SQL files; CI verifies every file against the recorded applied-body MD5. | Review replay-safety of repeated/overlapping operations; produce an approved canonical migration order from a known baseline; replay it on a clean disposable Supabase-compatible database. Separately restore the private 2026-10-15 dump with owners/ACLs preserved and pass the acceptance SQL. This restore is not yet executed with owner/ACL preservation. |
| 2 | Production database security audit | Current Advisor snapshot and read-only function/privilege/RLS review recorded in [PR #21 security report](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/21). All 20 RLS-without-policy tables in the Advisor set have no anon/authenticated direct table privileges. A body-marker scan found all 54 browser-callable SECURITY DEFINER functions have fixed search paths; only the intentional aggregate activity RPC lacks auth.uid()/nplus_is_admin markers. Generic positive wallet credits are blocked; phone lookup EXECUTE is revoked for browser roles; all six games are off. [PR #20](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/20) has candidate-only legacy anonymous grant hardening, not applied to production. | Re-test Admin RPCs using signed-in non-admin identities; review 4-argument WINGO RPC overload dependency before removing it; after legacy route replacement, review manual_deposits / user_bank_details grants. Resolve leaked-password protection notice if supported with no unapproved cost. |
| 3 | Login / signup / OTP / password reset | Static checks and existing auth-repair candidate code/docs are available; main static QA runs. | Test actual email OTP delivery/verification, signup/profile/wallet initialization, password recovery, expired/invalid codes and mobile return navigation using a controlled test account/inbox on a safe test deployment. No real-user account changes. |
| 4 | Wallet / Admin / referral | PR #16 current code head has green static QA + browser smoke and disposable PostgreSQL suites for wallet request/referral/admin/privilege behavior. Read-only production wallet/ledger snapshot showed no negative wallet, ledger arithmetic or wallet/latest-ledger mismatch. | Run the isolated wallet/Admin/referral transaction/rollback test and real authenticated browser flow with synthetic test accounts; verify request replay and non-admin rejection. Preserve legacy manual deposit rows; no auto-approval or auto-credit. |
| 5 | Games / payout rules | PR #17 safety gates are green in static and release-smoke CI. All six production game flags are currently disabled. | K3/5D/TRX payout/return formulas need explicit product approval. Server-owned settlement for all offered games must pass review/integration tests before any flags are enabled. Do not invent or infer payout rules and do not enable games early. |
| 6 | Recent activity + Aviator recovery | PR #18 latest CI has passed source/SQL/browser smoke. Read-only production checks verified active pg_cron job nplus-aviator-worker every second, 84,957 successful worker runs in the observed 24-hour window, recent successful worker-health heartbeat and zero consecutive failures at the checked time. | Homepage feed code is not merged/deployed or verified in the hosted site. Complete authenticated hosted activity/history test and recovery edge-case acceptance after migration/backup gates. Scheduler SQL in the evidence folder is not a canonical migration and must not be rerun. |
| 7 | Final release / live URL | Current main Pages deployment stays untouched; source branches remain drafts. | After all prior gates pass, merge only the reviewed PRs in a planned order, run CI on the exact merge commit, verify GitHub Pages build/deployment, then test login/account/Admin/navigation on the actual hosted URL. Publish the final link only after runtime verification. |

## Latest CI evidence (candidate branches, not production release proof)

- Wallet/Admin/referral PR #16: [Static QA + browser smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070078059), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070078070).
- Game rules gate PR #17: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386753), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386758).
- Activity/Aviator PR #18 latest: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070698260), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070698322).
- Migration source archive PR #19 latest: [Static QA including 29 source fingerprints](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071116483), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071116482).
- Production security snapshot PR #21: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071317905), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071317893).
- Legacy anonymous table-grant candidate PR #20: [Static QA + disposable SQL suite](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135909), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135893).

These CI runs use isolated disposable PostgreSQL and/or local static/browser smoke. They are not proof of a full authenticated production browser test or disaster-recovery acceptance.

## Exact user-PC tasks after assistant-side preparation

1. Start the existing local restore-lab Docker container and run qa/restore-backup-acceptance.ps1 from PR #19's branch. It creates a new local database and restores without --no-owner/--no-acl; if restoration fails, capture the error without changing flags or connecting to production.
2. After the restore passes, run the reviewed canonical migration replay in a fresh separate disposable Supabase-compatible local stack. Do not use the restored backup database as the replay target, do not use production, and do not use supabase db push against the live project.
3. Supply a controlled test account/inbox for signup/OTP/password recovery and authenticated demo wallet/Admin/referral E2E tests. Do not share passwords, service-role keys, JWTs, database connection strings, or the private backup.
4. Decide the K3/5D/TRX demo payout formulas before server settlement changes can be approved.
5. Review and approve the proposed final merge order once all gates above pass.

## Safety prohibitions

- Do not upload or commit the private dump archive.
- Do not edit supabase_migrations.schema_migrations to make source counts match.
- Do not run recovered files under docs/recovered-live-migration-sql-2026-10-23/; they are evidence, not deployable canonical migrations.
- Do not reset balances, delete user records, or enable games as a shortcut.
- Do not merge draft PRs #2, #6, #16–#21 blindly. Some are candidate fixes/audit evidence, not releases.
