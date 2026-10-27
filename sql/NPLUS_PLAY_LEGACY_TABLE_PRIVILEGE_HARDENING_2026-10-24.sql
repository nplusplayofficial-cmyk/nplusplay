-- Candidate entry point kept for existing disposable PostgreSQL test harnesses.
-- Single source of truth is the timestamped migration below; not applied to production.
\set ON_ERROR_STOP on
\ir ../supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql
