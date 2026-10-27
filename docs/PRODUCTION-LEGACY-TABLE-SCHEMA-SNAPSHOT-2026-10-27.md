# Current production schema snapshot: legacy tables — 2026-10-27

## Scope and safety

Read-only catalog inspection of the connected NPLUS-PLAY Supabase project `pcrxlqduygvzchzxsmdv` on 2026-10-27. Queries read table definitions, constraints, indexes, RLS policies, owners and ACL metadata only; no row contents were queried or changed.

**This is authoritative evidence for the current live table shape at the time of inspection. It is not the original migration SQL and does not establish when or by which deployment the tables were created.** Do not treat this file as a replacement for missing historical SQL or as proof of a clean canonical replay.

## Current table definitions

### `public.manual_deposits`

- Owner: `postgres`; RLS enabled; FORCE ROW LEVEL SECURITY is off.
- Columns, in order:
  - `id uuid NOT NULL DEFAULT uuid_generate_v4()`
  - `user_id uuid NOT NULL`
  - `amount numeric NOT NULL`
  - `utr text NOT NULL`
  - `status text DEFAULT 'pending'::text` (nullable)
  - `created_at timestamp with time zone DEFAULT now()` (nullable)
- Constraints: `manual_deposits_pkey PRIMARY KEY (id)`; `manual_deposits_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)`.
- Indexes: `manual_deposits_pkey`; `idx_manual_deposits_user_id_fk` on `user_id`.
- No user-defined triggers observed.

### `public.user_bank_details`

- Owner: `postgres`; RLS enabled; FORCE ROW LEVEL SECURITY is off.
- Columns, in order:
  - `id uuid NOT NULL DEFAULT uuid_generate_v4()`
  - `user_id uuid NOT NULL`
  - `account_holder text`
  - `account_number text`
  - `ifsc_code text`
  - `bank_name text`
  - `upi_id text`
  - `updated_at timestamp with time zone DEFAULT now()` (nullable)
- Constraints: `user_bank_details_pkey PRIMARY KEY (id)`; `user_bank_details_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)`; `user_bank_details_user_id_key UNIQUE (user_id)`.
- Indexes: `user_bank_details_pkey`; `user_bank_details_user_id_key`.
- No user-defined triggers observed.

### `public.withdraw_requests`

- Owner: `postgres`; RLS enabled; FORCE ROW LEVEL SECURITY is off.
- Columns, in order:
  - `id uuid NOT NULL DEFAULT uuid_generate_v4()`
  - `user_id uuid NOT NULL`
  - `amount numeric NOT NULL`
  - `status text DEFAULT 'pending'::text` (nullable)
  - `created_at timestamp with time zone DEFAULT now()` (nullable)
- Constraints: `withdraw_requests_pkey PRIMARY KEY (id)`; `withdraw_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)`.
- Indexes: `withdraw_requests_pkey`; `idx_withdraw_requests_user_id_fk` on `user_id`.
- No user-defined triggers observed.

No check constraints for the legacy request amount/status columns were found in the current catalog snapshot. Do not infer any historical validation rule beyond the constraints above.

## Current RLS policy snapshot

All listed policies are permissive and apply to the `authenticated` database role.

| Table | Policy | Command | Current predicate |
|---|---|---|---|
| `manual_deposits` | `Users can insert own deposit` | INSERT | `WITH CHECK ((SELECT auth.uid()) = user_id)` |
| `manual_deposits` | `manual_deposits_owner_admin_read` | SELECT | `user_id = (SELECT auth.uid()) OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin')` |
| `user_bank_details` | `Users can insert own bank` | INSERT | `WITH CHECK ((SELECT auth.uid()) = user_id)` |
| `user_bank_details` | `Users can update own bank` | UPDATE | `USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id)` |
| `user_bank_details` | `Users can view own bank` | SELECT | `USING ((SELECT auth.uid()) = user_id)` |
| `withdraw_requests` | `Users can insert own withdraw` | INSERT | `WITH CHECK ((SELECT auth.uid()) = user_id)` |
| `withdraw_requests` | `Users can view own withdraw` | SELECT | `USING ((SELECT auth.uid()) = user_id)` |

No RLS policies for the `anon` role were observed in this current snapshot. With RLS enabled, lack of an applicable policy should deny anonymous row access, even when an ACL grant exists. The direct grants below are nevertheless excessive and should be removed under the reviewed candidate ACL-hardening migration.

## Current table ACLs (effective catalog result)

Current `relacl` for each of the three relations is:

```text
{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}
```

Thus `anon` and `authenticated` currently have table-level SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, and TRIGGER privileges on each table; `service_role` and the owner have them as expected. No ACL grant to PostgreSQL `PUBLIC` appears in this snapshot. The RLS policies restrict row access, but broad anonymous table ACLs are unnecessary exposure and should not be considered the target release contract.

Candidate-only remediation is already present and tested in:
`supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql`.
That migration removes PUBLIC/anon direct privileges while preserving reviewed authenticated grants and RLS. It has **not** been deployed to production.

## Replay interpretation

The current live catalog confirms the present columns, constraints, indexes, policies, owner, RLS state and broad ACLs. It does **not** reconstruct the missing historical DDL/policy history at the point where the captured migration body `20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql` first references these relations.

The supplied 2026-10-15 backup-derived replay baseline lacked these three tables. The QA-only overlay in `qa/fixtures/replay-baseline/manual-deposits-schema-overlay.sql` creates empty tables for local suffix testing and intentionally leaves the index/policies created by the captured later migration to the migration under test. The live snapshot lets that QA fixture be checked against today's column/constraint shape; it still **does not** prove a clean 40-body replay or establish the historical origin/order of these tables.

## Required evidence to close the historical gap

- Recover the original table-creation SQL from trusted Supabase SQL Editor history, a deployment artifact/transcript, or a verified older schema backup.
- Compare the historical source with this current snapshot and record any intervening schema/policy/ACL changes.
- Keep the QA overlay and all replay work confined to the disposable database.
- Do not run the candidate ACL migration on production, change migration history, or claim canonical replay success from this snapshot alone.
