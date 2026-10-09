# N+ PLAY — Premium Upgrade Pack (virtual-credit demo only)

## Included in this pack
- Updated shared-wallet HTML pages for Home, Account, WINGO, K3, MotoRace, 5D, TRX WINGO and Aviator.
- Premium `activity.html` reading the signed-in user's Supabase wallet transaction ledger.
- `admin-users.html` with admin-only user search, ledger view, and auditable virtual-credit adjustments.
- `sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql` with owner-only admin RPCs, own-wallet read policies and direct table-write revocations.
- PWA manifest, icon, offline page and a service worker that does **not** cache Supabase API/auth responses.
- PWA manifest, icon, offline page and service worker, plus a Node QA script.

## Upload / merge steps (GitHub Pages)
1. Take a ZIP/branch backup of the current repository first.
2. Upload the root HTML files in this pack to the repository root using the same filenames. Keep any existing files not included here (especially any other game pages).
3. **Preserve your current `core/nplus-config.js`, `core/nplus-auth.js`, and `core/nplus-wallet-bridge.js`**. Your current auth flow uses email OTP methods; do not replace it with a generic auth file. The main Home page also references legacy `core/config.js`, `storage.js`, `user.js`, `wallet.js`, `activity.js`, and `games.js`; preserve those existing files.
4. Add `manifest.webmanifest`, `sw.js`, `offline.html`, and `assets/nplus-icon.svg` at their indicated paths.
5. Run `sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql` once in Supabase SQL Editor using project-owner access. It resets policies on `demo_wallets` and `demo_wallet_transactions` to authenticated own-row SELECT only, revokes direct browser writes, and adds admin-only RPCs used by `admin-users.html`. Back up and review current RLS policies before running any migration in a live project.
6. After deployment, hard refresh the site (Ctrl+Shift+R). For PWA/service-worker cache changes, update `VERSION` in `sw.js` when making future releases.
7. Open `admin.html` → User Management card. Verify admin role, user list, ledger, and a small test adjustment on a test account.

## QA
Run `node qa/verify-project.js` from this folder (Node.js 18+ recommended). It checks inline and included external script syntax and PWA/SQL assets. It deliberately does not require the existing core auth/wallet files to be copied into this overlay pack. It cannot connect to your live Supabase project, verify deployed GitHub Pages, or prove database RPCs work; those checks must be run after applying the SQL.

## Important security status — do not skip
This is a **virtual-credit demo** and not a real-money wagering/payments platform. This pack improves private table access and adds admin-only audited tooling, but it does **not yet make every existing game outcome/settlement tamper-proof**. The current legacy `nplus_wallet_change` RPC is used by client game pages and can accept client-supplied positive win credits unless its function body already enforces a stronger rule. A proper next deployment gate is to move each game's bet records, round results and payout calculation to server-authoritative RPC/Edge Functions, then remove arbitrary positive calls from that legacy RPC. Do not describe the system as production-secure until that phase is implemented and tested.

## User flows to verify
- Sign in, refresh, log out, re-login, and check idle timeout.
- Test user A and test user B; each must only read their own wallet/transactions.
- User A: game bet lowers wallet; each supported game's win/settlement should be checked separately; Home/Account/Activity should converge on the same Supabase balance.
- Admin: search users, view ledger, apply a test adjustment with a meaningful note, confirm the ledger entry is written exactly once.
- WINGO: save manual result for the current period, ensure the exact result row exists and the game reads the same duration+period.
- Check mobile and desktop. Network/offline state should never pretend to modify wallet balances without Supabase confirmation.
