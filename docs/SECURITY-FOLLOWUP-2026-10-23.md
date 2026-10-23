# N+ PLAY database security follow-up — 2026-10-23

## Status

**Remediation is prepared on this security branch but is not deployed. Do not mark Work #2 complete until staging regression and reviewed deployment pass.** Live production was inspected through read-only catalog queries only; no production rows, schema, policies, grants, bucket settings, migration history, or wallets were modified.

## Fresh findings

1. **High risk — payment-settings write authorization is not admin-only.** The live `payment_settings` table has table-level UPDATE permission granted to `anon` and `authenticated`. Its policy named `Allow admin update` applies to `PUBLIC`, has `USING (true)`, and has no explicit `WITH CHECK`. Because the public policy applies to API roles and anonymous UPDATE privilege exists, the database does not enforce the intended Admin-only write boundary. The page's frontend check is not a backend security boundary. The table is intentionally publicly readable by the customer Deposit page, so the candidate preserves SELECT while restricting UPDATE to `public.nplus_is_admin()`.

2. **High risk — QR storage upload is too broad.** The `payment_qr` bucket is public and has no file-size or MIME-type limits. The `Admin Upload` policy applies to `PUBLIC` and checks only `auth.role() = 'authenticated'`, so any signed-in user meets the policy condition. The candidate requires `public.nplus_is_admin()`, retains public reads for display, and constrains uploads to PNG/JPEG/WebP with a 5 MiB maximum.

3. **Defense-in-depth — old tables retain anonymous direct grants.** `manual_deposits`, `user_bank_details`, and `withdraw_requests` have broad `anon` table ACLs but no anon-scoped policies. Existing RLS is currently the denial layer. The candidate revokes anonymous/public table privileges while preserving signed-in functionality and existing authenticated RLS rules.

4. **Known functional security cleanup — ambiguous WINGO overload.** Live catalog contains both `nplus_admin_set_wingo_demo(integer,text,text,integer)` and `nplus_admin_set_wingo_demo(integer,text,text,integer,text)`; trailing defaults overlap, and the 4-argument direct call previously returned PostgreSQL 42725 ambiguity. Both function bodies require a matching admin role; the 5-argument Admin-page call denied a non-admin during the prior audit. The candidate removes only the old 4-argument overload, without CASCADE, after asserting the 5-argument function exists.

## Checks that passed in the fresh read-only review

- 69 public SECURITY DEFINER functions; 53 executable by `authenticated`; 1 executable by `anon`.
- All 69 SECURITY DEFINER functions have an explicit function-level `search_path`.
- The one anon-callable SECURITY DEFINER exception remains `nplus_recent_demo_activity(integer)`; prior review confirmed it returns aggregate activity counts only.
- `anon` has no EXECUTE on `nplus_wallet_change(numeric,text,text,text)`; `authenticated` does, and the previous positive generic wallet credit probe was blocked with SQLSTATE 42501.
- `anon` and `authenticated` cannot CREATE objects in `public`.
- The profile role-update trigger `nplus_guard_profile_role_update` is installed and checks the actor before changing `profiles.role`; the audit did not identify a direct role-escalation path from the profile UPDATE policy.
- Internal-only server/game tables retain RLS and no direct API-client privileges in the previously reviewed set.
- All six game settings remain `enabled = false`.

## Staged files on this branch

- `security/candidates/20261023_payment_settings_qr_upload_lockdown.sql`
- `security/candidates/20261023_remove_ambiguous_wingo_admin_overload.sql`
- `qa/test-security-followup-catalog.sql`

These files are **review candidates**, intentionally outside `supabase/migrations/`. They must not be merged to `main` or executed on production before Work #1 migration-source reconciliation and backup/replay gates are resolved.

## Required acceptance before Work #2 can be closed

1. Restore/replay in an isolated staging database only; apply the two candidate files there.
2. Run `qa/test-security-followup-catalog.sql`.
3. With real non-admin test credentials, verify REST UPDATE on `payment_settings` fails and Storage upload to `payment_qr` fails.
4. With Admin test credentials, verify updating the payment row and uploading a PNG/JPEG/WebP QR under 5 MiB succeed.
5. Verify the Deposit page still reads and renders the public payment details / QR.
6. Verify the current Admin Reports page's 5-argument WINGO call works for Admin and is denied for non-admin. Ensure no 42725 ambiguity remains.
7. Verify all six games remain disabled and wallet/ledger rows remain unchanged.

## Deployment constraint

Do not run ad-hoc SQL against production or edit the live schema migration history as a shortcut. Once Work #1 is reconciled and the staging gates pass, merge an approved version into the canonical migration chain and deploy through the reviewed process. Until then, production remains unchanged and these findings remain open.
