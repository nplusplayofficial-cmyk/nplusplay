-- Entry point for the disposable PostgreSQL ACL hardening regression test.
-- Canonical migration filename is aligned to the server-assigned live migration version.
\set ON_ERROR_STOP on
\ir ../supabase/migrations/20261027172637_20261027130000_harden_legacy_table_anon_privileges.sql
