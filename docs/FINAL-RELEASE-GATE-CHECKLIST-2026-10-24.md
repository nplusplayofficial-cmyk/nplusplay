# N+ PLAY + N+ ADMIN — Consolidated release gate checklist (2026-10-24)

## Release decision

**Not release-ready yet.** Source/static/disposable QA is green for the current wallet-route, game-gate, activity/Aviator, and migration-evidence branches, but the outstanding local backup restore, clean migration replay, authenticated hosted-browser tests, and approved K3/5D/TRX rules are release blockers.

No production migrations, schema DDL, wallet/ledger data, user records, game settings, ACLs, or cron jobs were changed as part of these latest audit updates.

## Workstream status

| # | Workstream | What is now verified / prepared | Remaining to close |
|---:|---|---|---|
| 1 | Migration source reconciliation + backup acceptance | Live history read-only snapshot has 40 rows, one stored SQL statement each, 29 unique body fingerprints, 11 exact duplicate-body pairs. Recovered-body evidence archive contains 29 SQL files; CI verifies every file against the recorded applied-body MD5. | Review replay-safety of repeated/overlapping operations; produce an approved canonical migration order from a known baseline; replay it on a clean disposable Supabase-compatible database. Separately restore the private 2026-10-15 dump with owners/ACLs preserved and pass the acceptance SQL. This restore is not yet executed with owner/ACL preservation. |
| 2 | Production database security audit | Current Advisor snapshot and read-only function/privilege/RLS review recorded in [PR #21 security report](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/21). All 20 RLS-without-policy tables in the Advisor set have no anon/authenticated direct table privileges. A body-marker scan found all 54 browser-callable SECURITY DEFINER functions have fixed search paths; only the intentional aggregate activity RPC lacks auth.uid()/nplus_is_admin markers. Generic positive wallet credits are blocked; phone lookup EXECUTE is revoked for browser roles; all six games are off. [PR #20](https://github.com/nplusplayofficial-cmyk/nplusplay/pull/20) has candidate-only legacy anonymous grant hardening, not applied to production. | Re-test Admin RPCs using signed-in non-admin identities. **Live catalog review confirmed that both 4-arg and 5-arg `nplus_admin_set_wingo_demo` overloads have overlapping defaults, making 4-arg calls ambiguous.** Candidate-only patch `sql/NPLUS_PLAY_WINGO_OVERLOAD_DISAMBIGUATION_2026-10-24.sql` removes defaults from the five-argument overload; `qa/test-wingo-overload-disambiguation.sql` proves four-/five-argument resolution and non-admin rejection in a fresh disposable PostgreSQL database. Both tests passed in CI on this branch. The candidate is not applied to production; canonical migration source/order and the private backup/replay gates remain required. After legacy route replacement, review `manual_deposits` / `user_bank_details` grants. Resolve leaked-password protection notice if supported with no unapproved cost. |
| 3 | Login / signup / OTP / password reset | Static checks and existing auth-repair candidate code/docs are available; main static QA runs. | Test actual email OTP delivery/verification, signup/profile/wallet initialization, password recovery, expired/invalid codes and mobile return navigation using a controlled test account/inbox on a safe test deployment. No real-user account changes. |
| 4 | Wallet / Admin / referral | PR #16 current code head has green static QA + browser smoke and disposable PostgreSQL suites for wallet request/referral/admin/privilege behavior. Read-only production wallet/ledger snapshot showed no negative wallet, ledger arithmetic or wallet/latest-ledger mismatch. | Run the isolated wallet/Admin/referral transaction/rollback test and real authenticated browser flow with synthetic test accounts; verify request replay and non-admin rejection. Preserve legacy manual deposit rows; no auto-approval or auto-credit. |
| 5 | Games / payout rules | PR #17 safety gates are green in static and release-smoke CI. All six production game flags are currently disabled. | K3/5D/TRX payout/return formulas need explicit product approval. Server-owned settlement for all offered games must pass review/integration tests before any flags are enabled. Do not invent or infer payout rules and do not enable games early. |
| 6 | Recent activity + Aviator recovery | PR #18 latest CI has passed source/SQL/browser smoke. Read-only production checks verified active pg_cron job nplus-aviator-worker every second, 84,957 successful worker runs in the observed 24-hour window, recent successful worker-health heartbeat and zero consecutive failures at the checked time. | Homepage feed code is not merged/deployed or verified in the hosted site. Complete authenticated hosted activity/history test and recovery edge-case acceptance after migration/backup gates. Scheduler SQL in the evidence folder is not a canonical migration and must not be rerun. |
| 7 | Final release / live URL | Current main Pages deployment stays untouched; source branches remain drafts. | After all prior gates pass, merge only the reviewed PRs in a planned order, run CI on the exact merge commit, verify GitHub Pages build/deployment, then test login/account/Admin/navigation on the actual hosted URL. Publish the final link only after runtime verification. |

## Latest CI evidence (candidate branches, not production release proof)

- Wallet/Admin/referral PR #16: [Static QA + browser smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070098542), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40070098435).
- Game rules gate PR #17: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386753), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40068386758).
- Activity/Aviator PR #18 latest: [Static QA + browser smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079438773), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079438766).
- Migration source archive PR #19 latest: [Static QA + disposable WINGO overload and Recent Activity privacy tests](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079556579), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40079556588).
- Production security snapshot PR #21: [Static QA](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40073282012), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40073282009).
- Legacy anonymous table-grant candidate PR #20: [Static QA + disposable SQL suite](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135909), [Release Smoke](https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/40071135893).

These CI runs use isolated disposable PostgreSQL and/or local static/browser smoke. They are not proof of a full authenticated production browser test or disaster-recovery acceptance.

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
