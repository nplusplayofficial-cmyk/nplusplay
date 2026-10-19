# N+ PLAY + N+ ADMIN — Release readiness (2026-10-17)

## Done
- Created local custom-format Supabase database backup and verified its archive list (not restore-tested).
- Live DB: added a role-change guard trigger; rollback-only test confirmed non-admin role escalation is blocked.
- Live DB: removed anonymous EXECUTE from the wallet/admin RPC set, removed direct wallet/ledger browser writes, preserved own-row reads plus admin-role reads required by admin pages, and verified authenticated RPC access.
- Live DB: consolidated duplicate deposit policies, optimized RLS policy expressions, applied least-privilege table grants, retained admin-only reads needed by admin screens, and added FK/ledger indexes.
- Live DB: created `profiles_phone_digits_unique_idx`; current profile values were checked and no duplicate digit-normalized phone groups existed. Aligned the future wallet default to ₹108 (no existing wallet balance changed).
- Branch: fixed missing admin-users page, PWA icon path, missing demo deposit route, legacy REAL_MONEY flag and forgot-password links.
- Branch: restored email OTP signup UI and added static QA checks/CI. Latest full disposable-Postgres CI is green (run linked below).


## Security-branch progress (not deployed)

- Added a server-owned WINGO backend: private rounds/bets tables, server-side outcomes, atomic wallet debit, idempotent requests, one-time settlement, history and reload recovery.
- Migrated `wingo.html` to server-side placement/settlement; its browser no longer issues generic `GAME_WIN` credits.
- Added a MotoRace backend: server-owned round outcomes, validated selections, server-computed 1.5% demo fee, server-side 2x winner return, one-time settlement and own-bet/history recovery.
- Migrated `motorace.html` away from browser-generated results and generic wallet credit/debit calls.
- Added `sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql` plus a disposable PostgreSQL test. After matching frontend/server RPC rollout only, this migration rejects caller-supplied positive credits and legacy generic `GAME_BET` debits; negative non-game adjustments remain permitted. It has not been run against production.
- Added an Aviator backend: server-owned crash points/timing, atomic server-side stake debit, server-time-based manual cash-out, server-handled auto cash-out and post-crash loss settlement. The client no longer decides crash points or credits its own cash-out amount.
- Migrated `aviator.html` to those RPCs and removed its local-balance fallback.
- Added an isolated PostgreSQL 17 QA workflow. Latest recorded successful run: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39010096765. Static checks and disposable database tests passed for WINGO, MotoRace, Aviator, the generic positive-credit guard, and N+ ADMIN user tools.
- Added a draft SQL migration for N+ ADMIN user directory/search, per-user transaction ledger and audited virtual-credit adjustment. Each RPC checks the current signed-in profile role on the server. The isolated PostgreSQL test covers admin success and unauthorized denial.
- Added `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql` and a disposable PostgreSQL test for authenticated-admin-only game status changes, invalid/null values, persistence and anon/user denial.
- Connected `admin-games.html` global on/off controls to `game_settings` and the role-guarded `nplus_set_game_status` RPC. It no longer treats localStorage as the global game-enabled switch.
- `sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql` now sets K3/5D/TRX to disabled during the reviewed rollout and the server RPC refuses to re-enable them without approved payout rules. Admin cards show those games as paused and lock their UI toggle.
- WINGO and MotoRace periodically refresh the authenticated-readable `game_settings` status and fail closed if it cannot be read. Aviator receives the status from its server-round RPC. All three bet RPCs independently reject new bets when their corresponding server setting is disabled.
- Admin commission cards are labelled estimated, with a note explaining that the flat 2% report is not an exact ledger until game-specific commission accounting is implemented.
- Latest recorded successful full CI run: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39014567618 (commit `4f1ae293de53d8d7edd108003f0a7cb1c9da7806`). All jobs passed: static checks; WINGO settlement; Admin game-status migration/lock; MotoRace settlement; Aviator settlement; generic wallet credit/debit guard; Admin user tools; Admin deposits. Tests use a disposable PostgreSQL 17 database only, not live Supabase or a real browser.
- Fixed the security branch's admin-users filename/link mismatch. Live main still has the legacy misspelled admin-users.htlm, so the corrected page has not yet been deployed.
- Paused K3, 5D and TRX WINGO wagers in the security branch until payout rules are approved; disabled withdrawal submission and collection of bank/UPI details in virtual-credit demo mode.
- These are branch/CI tests only. No new settlement SQL has been run against the live Supabase project, and no code PR has been merged to `main`.

## Latest verification update — 2026-10-17

- Candidate commit `cc10da4e4e2d78436e3dd49f147ce36408413935` passed both the pull-request CI run and candidate-branch push CI run:
  - PR run: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39017665739
  - Push run: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39017662316
- Each run passed static HTML/JavaScript/local-link checks and eight disposable PostgreSQL suites: WINGO settlement, Admin game status, MotoRace settlement, Aviator settlement, generic wallet guard, phone-enumeration revocation, Admin user tools and Admin deposit actions.
- A fresh read-only production catalog/privilege inspection confirmed the release is still blocked: none of the six new server-settlement tables exist; all six existing game settings are currently enabled; anon can still execute `nplus_phone_is_registered(text)`; authenticated users can still execute legacy `nplus_wallet_change(...)`. The live database has 5 profiles, 5 wallets and 145 ledger rows at the time of this inspection. These counts are operational facts, not a request to modify or reset data.
- Security advisor continues to flag the anonymous phone-registration lookup and disabled leaked-password protection. Authenticated SECURITY DEFINER functions must be reviewed by their internal authorization checks; an advisor warning alone is not proof of a bypass.
- No production writes were made during this verification. No paid Supabase branch was created. Existing balances were not changed.

## Remaining release blockers

1. **K3, 5D and TRX WINGO wagering is temporarily paused in the security branch.** Their payout/return rules were not found in the inspected source. Approve those rules before building server settlement and re-enabling these games.
2. **Production still has the legacy game status and wallet paths.** A live read-only check on 2026-10-17 found `game_settings.enabled=true` for WINGO, K3, 5D, TRX, AVIATOR and MOTO. The security-branch migration that defaults K3/5D/TRX off is not deployed, and current `main` does not enforce game status in its wager path. During rollout, prevent new wagers on legacy pages until the new schemas/RPCs and matching frontend are deployed and verified.
3. **N+ ADMIN enhancements are not deployed to live.** The new user-directory/ledger/adjustment migration and Admin game-status migration are only in the security branch; the current live site also has the admin-users.htlm filename mismatch. The existing live `nplus_set_game_status` RPC and `game_settings` table exist, but the current main frontend still stores the global control locally. Deploy the matching reviewed SQL and frontend together.
4. The live generic `nplus_wallet_change` RPC still accepts authenticated positive deltas and can be called by signed-in clients. The tested blocker is post-rollout only: safely transition the frontend first, verify every active game uses server settlement, then block generic positive credits and generic `GAME_BET` debits.
5. WINGO, MotoRace and Aviator require their matching new schema/RPC migrations. Never deploy their new HTML before the matching SQL functions and tables are installed.
6. Legacy bets stored only in browser localStorage have no server-issued settlement proof. Migrated pages will not award credits for those records. Provide a user-facing transition/reconciliation plan; never reset existing wallet balances.
7. The live anonymous `nplus_phone_is_registered(text)` RPC still reveals whether a phone is registered (confirmed by the Supabase security advisor on 2026-10-17). After the new signup code is deployed and duplicate-mobile signup is tested, revoke client EXECUTE as a post-rollout action.
8. **Email OTP requires Confirm email ON.** The branch signup code deliberately rejects an immediate session, which happens when Confirm email is OFF. The dashboard setting is currently OFF; the signup template already contains {{ .Token }}. Deploy the matching frontend, enable confirmation, then verify delivery, six-digit OTP, profile creation and ₹108 wallet initialization.
9. N+ ADMIN commission reports currently estimate a uniform 2% on every negative GAME_BET transaction. The new MotoRace flow charges 1.5% inside the total debit; Aviator has no separate entry fee and WINGO's 2% is currently applied to winning returns. Approve one accounting model and update reporting so commission figures are accurate.
10. Leaked-password protection is disabled on the current Free plan according to the Supabase dashboard. Keep this documented unless a plan change is separately approved.
11. The database backup archive can be listed but has not been restored into a separate test database. Test restore only in an isolated environment.
12. Live browser testing is still pending for Supabase Auth, admin login, deposit approve/reject, game control, reports, user search/ledger/adjustment, every active game, reload and mobile layouts. The separate nplus-play-final repository is only a localStorage prototype with username-only login and incomplete game routes; it has no N+ ADMIN and must not be treated as the Supabase-backed production app.

## Safe rollout order

1. Restore-test the existing backup in a separate database; never use production as the restore-test target.
2. Schedule a controlled rollout/maintenance window and stop new wagers through the currently deployed UI/routes first; do not rely on the new Admin toggle to control legacy HTML pages.
3. Apply reviewed, matching additive SQL: set K3/5D/TRX disabled with the Admin game-status migration, then install WINGO settlement, MotoRace schema/RPCs, Aviator schema/RPCs, and Admin user tools. Do not rerun the recorded live hardening migration.
4. Deploy the matching security-branch frontend to the actual configured N+ PLAY host in the same window. Verify that Admin game pause blocks server wagers for WINGO/MotoRace/Aviator and leave K3/5D/TRX off. Keep cash withdrawals disabled until separately approved.
5. Enable Supabase Confirm email only after the matching signup UI is deployed; then test a fresh account end-to-end.
6. Test admin login, non-admin rejection, pending deposit approval/rejection, game control, reports, user search/ledger/adjustment, and all active games on desktop and mobile.
7. Verify no active frontend still uses generic positive wallet credits or generic GAME_BET debits. Only then apply the post-rollout generic-wallet guard and phone-enumeration revocation scripts.
8. Approve payout rates and commission accounting; review all diffs and repeat CI before merging or deploying.

## Merge gates

- Approve K3/5D/TRX demo payout rules and the N+ ADMIN commission accounting model.
- Pass automated tests for all enabled games: duplicate/replayed settlement, insufficient balance, invalid selections/stakes, reload, parallel requests, and wallet/ledger consistency.
- Validate Auth, RLS/RPC permissions, deposits/admin workflows and real browser behavior against an isolated Supabase test project.
- Review the final diff and workflow evidence before any production deployment. Keep PR #2 and the security branch unmerged until these gates pass.
Production DB hardening was applied through Supabase and is recorded in `sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql`. No code PR is merged to main.


## Password recovery update — 2026-10-19
- Replaced the fixed mobile OTP / localStorage password-reset prototype with a Supabase Auth email-recovery flow.
- The request screen returns a generic message that does not confirm whether an email address is registered.
- A valid recovery callback must establish a Supabase session before the page shows the password form; the password update uses Supabase Auth `updateUser({ password })`.
- No fixed OTP, phone-number lookup, or browser-local-only password change is used.
- Before deployment, configure the matching N+ PLAY recovery URL in Supabase Auth's redirect allowlist and test email delivery, link expiry, password update, logout and a fresh login. This has not been live-tested and no production settings were changed.


## Account module updates — 2026-10-19
- Activity now loads supported-game history from authenticated WINGO, MotoRace and Aviator history RPCs and displays it separately from the wallet transaction ledger. It reports unavailable history explicitly if matching settlement RPCs are absent.
- Bonus Center now reads balance and transaction history through the authenticated wallet bridge. Only explicitly typed reward transactions are counted. The browser-local balance fallback, sample weekly streak and fake reward-code success flow were removed.
- Promotion page now reads account balance and promotion/referral ledger entries through Supabase. The shared `NPLUSPLAY` code and sample “active campaign” cards were removed. Campaign claiming and referral tracking remain unavailable until a server-side campaign/referral backend and Admin rules exist.
- Static QA now guards the Activity, Bonus, Promotion, Account and password-recovery flows against the specific local/mock behaviors removed in this candidate.
- These frontend changes are still an unmerged candidate. CI and local browser QA must pass at the latest candidate head. No production deployment or DB/settings changes were made for these page updates.


## Demo referral system — 2026-10-19
- Added unique stable referral codes for existing and newly created profiles, plus authenticated signup attribution after email OTP verification.
- Promotion Center displays the signed-in account's code, an `auth.html?ref=CODE` invite link, and server-recorded invite/pending/rewarded counts. The signup page accepts the optional code and pre-fills it from shared links.
- **Demo rule only:** when N+ ADMIN approves a referred account's `DEMO_CREDIT` request of 200 or more virtual credits, the referrer receives 20 virtual credits once. The database trigger updates the referral status, wallet and ledger in a single transaction and rejects self-referrals, invalid codes, attribution changes and duplicate rewards.
- The migration revokes direct table access and exposes only authenticated security-definer RPCs. The reward has no cash value; no payment, real deposit or cash payout is performed.
- Added `qa/test-demo-referrals.sql` and a tenth disposable PostgreSQL CI suite. It checks per-user unique codes, OTP-side attribution contract, invalid/self-referral behavior, immutable attribution, the 199-credit non-qualifying boundary, the 200-credit qualifying boundary, one-time reward and wallet/ledger consistency.
- Candidate only: apply the matching local Supabase migration in isolated local staging, then test a second account and admin-approved virtual-credit request. No production SQL, settings or deployment changes were made.


## Latest verification refresh — 2026-10-19

- Candidate head `ccedda7608421107271a11a8e784baf03a24c390` passed CI run https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39248321488. The job passed static HTML/JavaScript/local-link QA and 11 disposable PostgreSQL suites, including the new profile-role escalation regression (self-promotion, cross-account promotion, unauthenticated/anonymous changes, allowed admin change, and browser-role EXECUTE revocation).
- Fresh read-only Supabase catalog recheck on 2026-10-19 confirms the WINGO, MotoRace and Aviator settlement tables are still absent. `game_settings.enabled` is still true for all six keys: WINGO, K3, 5D, TRX, AVIATOR and MOTO.
- Fresh privilege check confirms anonymous EXECUTE remains available for `public.nplus_phone_is_registered(text)`, and authenticated EXECUTE remains available for legacy `public.nplus_wallet_change(numeric,text,text,text)`. The `nplus_guard_profile_role_update` trigger is present on `public.profiles`.
- Supabase Security Advisor again flags the public phone lookup and disabled leaked-password protection. It also lists authenticated EXECUTE on 14 SECURITY DEFINER functions (including Admin and wallet RPCs); this is an audit queue, not automatic proof that each function is exploitable. Inspect each function's internal role/ownership checks and remove grants that are not required.
- No development branches currently exist in the Supabase project, and no paid branch was created. Do not create a billed development branch until the exact organization/cost quote is reviewed and explicitly approved.
- This remains a release blocker. Do not merge/deploy the candidate or run either `POST_ROLLOUT_*` script yet. Required next gates are isolated backup restore, approved staging environment, real desktop/mobile Auth and Admin/game browser tests, payout/commission decisions, then coordinated SQL + matching frontend release.
- No production SQL, auth settings, game toggles, or wallet balances were changed by this recheck.


## Admin null-profile authorization guard — 2026-10-19

- A targeted read-only catalog/body audit found nine Admin/game RPC signatures (including both `nplus_admin_set_wingo_demo` overloads) using `IF v_role <> 'admin'` after selecting a profile role. If an authenticated user has no matching `profiles` row, `v_role` is NULL and that comparison alone is not fail-closed.
- Current catalog counts showed 5 Auth users, 5 profiles, zero missing-profile Auth users, zero orphan profiles, zero NULL roles and one admin. This means no missing-profile account was observed in this snapshot; the authorization logic is still hardened defensively for future account/profile edge cases.
- Added candidate-only migration `sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql`. It replaces the nine affected function definitions with NULL-safe `coalesce(v_role, '') <> 'admin'` checks and reapplies least-privilege EXECUTE grants (`authenticated` plus `service_role`; no `PUBLIC`/`anon` access). It does not edit wallet balances.
- Added `qa/test-admin-null-profile-guard.sql` and wired it into CI. It creates an isolated Auth user without a profile row and checks that the relevant Admin RPCs fail closed, and verifies grants/guards on all nine signatures. The disposable PostgreSQL run at https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39249711367 completed all 12 suites successfully.
- This migration has **not** been applied to live Supabase. It must be reviewed and tested on an isolated Supabase staging branch/database before a controlled production rollout. Continue to keep PR #3 draft/unmerged until the backup restore, staging/Auth tests, browser regressions, and coordinated release prerequisites pass.


### Additional invariants checked

- The null-profile regression now also checks that a valid Admin can still read the commission summary after the patch.
- It snapshots `demo_wallets.balance` and per-user wallet-ledger row counts before the candidate migration and confirms they are unchanged afterward.
- Latest full CI: https://github.com/nplusplayofficial-cmyk/nplusplay/actions/runs/39250331072 — **all 12 disposable PostgreSQL suites passed** on commit `bbaa31554473bd4752076d602537a1e3eb01afc9`.
