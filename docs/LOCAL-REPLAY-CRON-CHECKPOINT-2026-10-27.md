# Local replay retry after pg_cron target mismatch — 2026-10-27

## What happened

The user pulled candidate HEAD `0e05528d26ec58fa92d9dee332907695fa6d3959` and ran the full local replay into `nplus_migration_replay_20261029`. The run passed the source-fingerprint check, read-only restore acceptance, and historical replay records 1–14. It stopped at record 15, migration `20261021161206_nplus_aviator_persistent_scheduler`, because local PostgreSQL still reported:

- `cron.database_name = nplus_migration_replay_20261026`
- attempted replay target = `nplus_migration_replay_20261029`

This is a local Docker configuration mismatch, not evidence of a candidate SQL defect. The migration must not be skipped.

The partially replayed `nplus_migration_replay_20261029` database is evidence and must not be overwritten or deleted by the runner. Use a new target, `nplus_migration_replay_20261030`, only if it does not already exist.

## Updated runner protection

The replay runner now reads `current_setting('cron.database_name', true)` before source fingerprint/replay work and fails closed if it does not exactly match `-ReplayDatabase`. The QA runner-contract test asserts this check is executed before the migration sequence.

## Safe PowerShell sequence

Run from the local worktree:

```powershell
Set-Location "C:\Users\Natarajan K\Projects\nplusplay-release-2026-10-27"
git fetch origin
git pull --ff-only origin integration/release-candidate-2026-10-27
git rev-parse HEAD
```

Confirm `nplus_restore_acceptance_20261027` exists and the fresh replay target does not:

```powershell
docker exec supabase_db_nplusplay-restore-lab-v2 psql -X -U supabase_admin -d postgres -A -t -c "SELECT datname FROM pg_database WHERE datname IN ('nplus_restore_acceptance_20261027','nplus_migration_replay_20261030') ORDER BY datname;"
```

Expected: `nplus_restore_acceptance_20261027` only. If the 20261030 replay DB already exists, choose another unused eight-digit suffix and replace it consistently in the following commands.

Temporarily set the local restore-lab's pg_cron target to the new disposable replay database, restart the local container, and verify the configuration:

```powershell
docker exec supabase_db_nplusplay-restore-lab-v2 psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM SET cron.database_name = 'nplus_migration_replay_20261030';"
docker restart supabase_db_nplusplay-restore-lab-v2
Start-Sleep -Seconds 10
docker exec supabase_db_nplusplay-restore-lab-v2 pg_isready -U supabase_admin -d postgres
docker exec supabase_db_nplusplay-restore-lab-v2 psql -X -U supabase_admin -d postgres -A -t -c "SELECT current_setting('cron.database_name', true);"
```

Do not start replay unless PostgreSQL accepts connections and the final line is exactly `nplus_migration_replay_20261030`.

Then run the current candidate sequence:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\qa\replay-live-migration-sequence.ps1" -VerifiedRestoreDatabase nplus_restore_acceptance_20261027 -ReplayDatabase nplus_migration_replay_20261030 -UseReconstructedLegacyBaseline
```

If this run fails, keep that target for diagnosis and choose a new unused target for any retry. Never skip a migration to make the replay appear successful.

## Restore the local lab setting

After the run (success or failure), restore the previous local cron target and verify it:

```powershell
docker exec supabase_db_nplusplay-restore-lab-v2 psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM SET cron.database_name = 'nplus_migration_replay_20261026';"
docker restart supabase_db_nplusplay-restore-lab-v2
Start-Sleep -Seconds 10
docker exec supabase_db_nplusplay-restore-lab-v2 pg_isready -U supabase_admin -d postgres
docker exec supabase_db_nplusplay-restore-lab-v2 psql -X -U supabase_admin -d postgres -A -t -c "SELECT current_setting('cron.database_name', true);"
```

Final setting must be `nplus_migration_replay_20261026`. Preserve the prior successful `nplus_migration_replay_20261028` and the partial `20261029` database as evidence.

## Limitations

The reconstructed-baseline path creates the three missing legacy table shapes from a read-only snapshot of the current live catalog, then replays the 40 captured history bodies and candidate changes. It does not establish original historical DDL, original policy/ACL lineage, or production-readiness. It does not modify production Supabase; keep all six games disabled.
