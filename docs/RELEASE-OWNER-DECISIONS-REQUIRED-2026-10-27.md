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

The previous full replay used the pre-split monolithic guard source. Static QA now tests the split migrations in disposable PostgreSQL, and production catalog postconditions are verified, but an exact-head full reconstructed-baseline replay still needs the user's existing Windows restore lab.

After pulling the latest branch, run once from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\qa\run-final-split-replay.ps1"
```

The wrapper only allows the existing local Supabase restore-lab container, refuses non-local Docker endpoints and reused replay targets, and restores the documented prior local cron setting in `finally`. Default new target: `nplus_migration_replay_20261031`. If that target already exists, do not delete it; choose a new unused `nplus_migration_replay_YYYYMMDD` value and pass it with `-ReplayDatabase`. Preserve failing databases as evidence.

The reconstructed replay does not resolve historical DDL provenance by itself.

## Release decision

PR #22 stays OPEN/DRAFT until the above decisions and evidence are closed. After a fresh exact-head CI pass and approval, the release path is: review exact commit → merge → verify Pages deployment → test live N+ PLAY and N+ ADMIN signup/login/navigation and approved flows. The previously deployed Pages build is older main; the candidate is not yet declared live.

No user, wallet or ledger data, Auth setting, paid plan, scheduler setting or game flag is to be changed merely to clear this register.
