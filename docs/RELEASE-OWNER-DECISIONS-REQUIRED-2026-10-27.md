# N+ PLAY + N+ ADMIN — Release owner decisions required (2026-10-27)

This is a decision register, not permission to change production. The app remains demo/virtual-credit only. All six game flags must remain disabled until their respective requirements are approved. Preserve existing users, wallet balances and ledger rows.

## Decision 1 — referral qualification and reward

**Conflict:** the earlier request was a referred account qualifying at 200 demo credits and awarding the inviter 20 demo points once. The current production/candidate qualification flow uses 500 virtual points and a multi-tier bonus claim model; the Admin qualification RPC records qualification but sets the referral reward amount to zero.

Choose one contract explicitly:

- [ ] **Legacy 200/20:** at least 200 approved virtual demo credits for one referred account triggers a single 20-point virtual reward for the inviter. Requires reviewed migration/function/QA work before activation; no back-crediting automatically.
- [ ] **Current 500/tier:** keep 500-point qualification and tier claims; specify/accept the displayed tier reward table and that qualification alone does not award 20 points.
- [ ] **Neither:** provide an approved replacement rule table.

Until this decision is recorded, do not award credits or silently change qualification/reward behavior.

## Decision 2 — K3, 5D and TRX WINGO

**Current safe state:** all six games are disabled. K3/5D/TRX result generation and settlement do not have an approved server-owned payout contract.

- [ ] Approve written rules for each game: valid picks, round duration/cutoff, server result derivation, win conditions, payout formula/rounding, ties, cancellation/refund, idempotency and restart recovery.
- [ ] Keep K3/5D/TRX disabled and launch only the UI/approved server-backed demo flows that are already covered by the current release.

No flag will be enabled based on a placeholder rule.

## Decision 3 — legacy schema provenance

The supplied backup and recovered migration bodies do not establish the original historical table creation, policy and ACL lineage for `manual_deposits`, `user_bank_details`, and `withdraw_requests`. Current live schema/grants were inspected and candidate/reconstructed replay tests exist, but that is not historical proof.

- [ ] Provide an authoritative pre-history backup/schema source.
- [ ] Or explicitly accept in writing that original historical provenance cannot be proven from available evidence and approve release based on the documented reconstructed-baseline limitations.

Do not fabricate DDL or alter production to make replay pass.

## Decision 4 — leaked-password protection on the current Free plan

Security Advisor reports leaked-password protection disabled. The current Free plan does not expose this feature per the recorded plan review.

- [ ] Accept this limitation for a demo-only release with compensating controls and documented risk.
- [ ] Or authorize a plan decision after reviewing its actual cost. No upgrade has been initiated.

No hidden Auth configuration change or unsupported SQL workaround is permitted.

## Decision 5 — hosted Auth/browser acceptance

This requires a controlled email inbox and synthetic accounts that can receive OTP/recovery emails. Do not test by altering existing user accounts.

- [ ] Provide a controlled test inbox or run the hosted signup/email OTP/login/password recovery and mobile-return checklist yourself, then attach results to PR #22.

Until actual email delivery and browser journeys are observed, this gate stays open.

## Decision 6 — exact local split-migration replay

**PASS — completed by the user on 2026-10-28.**

- Candidate code HEAD at time of replay: `bb3e2c708d630ba629ea3d99ac4a229961b58f57`.
- Existing local container: `supabase_db_nplusplay-restore-lab-v2`.
- Restore source: `nplus_restore_acceptance_20261027`.
- Disposable replay target: `nplus_migration_replay_20261031`.
- All 40 captured production-history bodies replayed; all 29 distinct body fingerprints matched.
- The three candidate protection migrations and the exact current three split finite-number guard migrations applied on the disposable reconstructed clone; QA-only ACL overlays and final invariants passed.
- Synthetic wallet/Admin/referral/withdrawal E2E passed and rolled back. The six game flags remained disabled.
- Local `cron.database_name` was restored and verified as `nplus_migration_replay_20261026`.
- See [release readiness report](RELEASE-READINESS-STATUS-2026-10-27.md) for full evidence.

**Limitation:** this was a reconstructed-baseline replay with schema-only bootstrap and QA-only ACL overlays. It does not establish original historic DDL/policy/ACL provenance for the three legacy tables, and does not replace hosted Auth/browser acceptance.

## Release decision

PR #22 stays OPEN/DRAFT until the above decisions and evidence are closed. After a fresh exact-head CI pass and approval, the release path is: review exact commit → merge → verify Pages deployment → test live N+ PLAY and N+ ADMIN signup/login/navigation and approved flows. The previously deployed Pages build is older main; the candidate is not yet declared live.

No user, wallet or ledger data, Auth setting, paid plan, scheduler setting or game flag is to be changed merely to clear this register.
