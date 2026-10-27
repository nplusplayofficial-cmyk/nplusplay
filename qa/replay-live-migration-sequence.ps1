# Replay the 40 captured production migration bodies on a fresh LOCAL copy
# of the 2026-10-15 backup, then check critical invariants.
# Supports guarded resumes at the pg_cron checkpoint and a documented schema-overlay suffix check.
# The manual_deposits overlay is QA-only and does NOT constitute a clean replay of the original backup.
# Never connects to production. Never drops/replaces an existing database.
# Stops on the first failure and leaves the disposable replay DB for inspection.

[CmdletBinding()]
param(
  [string]$ContainerName = "supabase_db_nplusplay-restore-lab-v2",
  [string]$VerifiedRestoreDatabase = "nplus_restore_acceptance_20261024",
  [string]$ReplayDatabase = "nplus_migration_replay_20261024",
  [string]$ResumeFromVersion = "",
  [switch]$UseReconstructedLegacyBaseline
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OrderPath = Join-Path $PSScriptRoot "migration-replay-order-2026-10-24.json"
$RestoreAcceptanceSql = Join-Path $PSScriptRoot "restore-backup-acceptance.sql"
$FinalStateSql = Join-Path $PSScriptRoot "verify-replayed-migration-state.sql"
$SourceRoot = Join-Path $RepoRoot "docs\recovered-live-migration-sql-2026-10-23"
$ContainerDumpPath = "/tmp/nplus-play-replay-base-20261024.dump"
$ContainerRestoreSql = "/tmp/nplus-play-replay-restore-check.sql"
$ContainerFinalSql = "/tmp/nplus-play-replay-final-check.sql"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker CLI not found. Start the existing local restore lab first."
}

$ExpectedContainerName = "supabase_db_nplusplay-restore-lab-v2"
if ($ContainerName -ne $ExpectedContainerName) {
  throw "Refusing non-project Docker container '$ContainerName'. Use the existing local restore-lab container '$ExpectedContainerName'."
}

# Fail closed if Docker is pointing at a remote host/context rather than a local socket.
$dockerContext = (& docker context show 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dockerContext)) {
  throw "Could not identify the active Docker context. No database action was taken."
}
$dockerEndpoint = (& docker context inspect $dockerContext --format '{{.Endpoints.docker.Host}}' 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $dockerEndpoint -notmatch '^(npipe://|unix://)') {
  throw "Refusing non-local Docker endpoint '$dockerEndpoint'. Select the local Docker Desktop/Unix socket context. No database action was taken."
}
if ($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe://|unix://)') {
  throw "DOCKER_HOST points to a non-local endpoint. No database action was taken."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Node.js is required for the applied-body fingerprint check."
}
if (-not (Test-Path -LiteralPath $OrderPath -PathType Leaf)) {
  throw "Replay-order JSON is missing. No database action was taken."
}
if (-not (Test-Path -LiteralPath $RestoreAcceptanceSql -PathType Leaf) -or
    -not (Test-Path -LiteralPath $FinalStateSql -PathType Leaf)) {
  throw "Required acceptance SQL file is missing. No database action was taken."
}
if ($VerifiedRestoreDatabase -notmatch '^nplus_restore_acceptance_[0-9]{8}$') {
  throw "Restore source must use the dedicated nplus_restore_acceptance_YYYYMMDD name."
}
if ($ReplayDatabase -notmatch '^nplus_migration_replay_[0-9]{8}$') {
  throw "Replay target must use the dedicated nplus_migration_replay_YYYYMMDD name."
}
if ($VerifiedRestoreDatabase -eq $ReplayDatabase) {
  throw "Restore source and replay target must be different databases."
}

$containerState = (& docker inspect --format '{{.State.Running}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $containerState -ne "true") {
  throw "Expected LOCAL Docker container '$ContainerName' must already be running. No database action was taken."
}
$image = (& docker inspect --format '{{.Config.Image}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $image -notmatch 'supabase') {
  throw "Container image does not look like the expected local Supabase PostgreSQL image ('$image'). No database action was taken."
}

$rows = @(Get-Content -LiteralPath $OrderPath -Raw | ConvertFrom-Json | Write-Output)
if ($rows.Count -ne 40) {
  throw "Expected exactly 40 ordered historical migration records; found $($rows.Count). No database action was taken."
}
$versions = @($rows | ForEach-Object { [string]$_.version })
if (($versions | Select-Object -Unique).Count -ne 40) {
  throw "Replay order contains duplicate version IDs. No database action was taken."
}

$resumeIndex = 1
if ($UseReconstructedLegacyBaseline -and -not [string]::IsNullOrWhiteSpace($ResumeFromVersion)) {
  throw "UseReconstructedLegacyBaseline requires a fresh restored-backup clone and cannot be combined with ResumeFromVersion."
}

if (-not [string]::IsNullOrWhiteSpace($ResumeFromVersion)) {
  if ($ResumeFromVersion -notin @("20261021161206", "20261023092858")) {
    throw "Guarded resume is allowed only at the observed pg_cron checkpoint or the documented manual_deposits schema-overlay suffix checkpoint."
  }
  $resumeIndex = [Array]::IndexOf($versions, $ResumeFromVersion) + 1
  if ($resumeIndex -lt 2) {
    throw "The requested resume version is not present in the captured migration order."
  }
  if ($ResumeFromVersion -eq "20261021161206" -and $versions[$resumeIndex - 2] -ne "20261021161152") {
    throw "The expected preceding Aviator worker recovery checkpoint is not present."
  }
  if ($ResumeFromVersion -eq "20261023092858" -and $versions[$resumeIndex - 2] -ne "20261023081916") {
    throw "The expected preceding Admin wallet signature checkpoint is not present."
  }
}

Write-Host "Verified local container: $ContainerName ($image)"
Write-Host "Step 1/5: verify captured SQL source fingerprints."
Push-Location $RepoRoot
try {
  & node "qa/test-live-migration-source-fingerprints.cjs"
  if ($LASTEXITCODE -ne 0) { throw "Applied-body fingerprint QA failed. No database action was taken." }
}
finally {
  Pop-Location
}

# Confirm the restored baseline exists before creating any replay target.
$baseExists = (& docker exec $ContainerName psql -X -U supabase_admin -d postgres -A -t -c "SELECT 1 FROM pg_database WHERE datname = '$VerifiedRestoreDatabase';" 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $baseExists -ne "1") {
  throw "Verified restore database '$VerifiedRestoreDatabase' is not present in the local container. Run restore-backup-acceptance.ps1 first."
}
$targetExists = (& docker exec $ContainerName psql -X -U supabase_admin -d postgres -A -t -c "SELECT 1 FROM pg_database WHERE datname = '$ReplayDatabase';" 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
  throw "Could not inspect the local database catalog."
}
if ([string]::IsNullOrWhiteSpace($ResumeFromVersion) -and $targetExists -eq "1") {
  throw "Replay target '$ReplayDatabase' already exists. Nothing was dropped or overwritten; choose a new date suffix."
}
if (-not [string]::IsNullOrWhiteSpace($ResumeFromVersion)) {
  if ($targetExists -ne "1") {
    throw "Resume requested but partial replay target '$ReplayDatabase' does not exist."
  }
  if ($ReplayDatabase -ne "nplus_migration_replay_20261026") {
    throw "Guarded resume is only approved for the observed local replay target nplus_migration_replay_20261026."
  }

  if ($ResumeFromVersion -eq "20261021161206") {
    $resumeQuery = "SELECT current_database() = '$ReplayDatabase', current_setting('cron.database_name') = '$ReplayDatabase', to_regclass('public.nplus_aviator_worker_health') IS NOT NULL, to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NOT NULL, NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'), to_regclass('cron.job') IS NULL;"
    $expectedResumeChecks = 6
  } else {
    # This is intentionally a SUFFIX CHECK after a QA-only schema overlay.
    # The restored 2026-10-15 baseline lacks manual_deposits and withdraw_requests, and no captured history row creates either table.
    $resumeQuery = "SELECT current_database() = '$ReplayDatabase', current_setting('cron.database_name') = '$ReplayDatabase', EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'), to_regclass('cron.job') IS NOT NULL, to_regclass('public.nplus_aviator_worker_health') IS NOT NULL, to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NOT NULL, to_regclass('public.manual_deposits') IS NOT NULL, COALESCE((SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.manual_deposits')), false), COALESCE((SELECT pg_get_userbyid(relowner) = 'postgres' FROM pg_class WHERE oid = to_regclass('public.manual_deposits')), false), (SELECT count(*) FROM pg_attribute WHERE attrelid = to_regclass('public.manual_deposits') AND attnum > 0 AND NOT attisdropped AND attname IN ('id','user_id','amount','utr','status','created_at')) = 6, EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.manual_deposits') AND conname = 'manual_deposits_pkey' AND contype = 'p'), EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.manual_deposits') AND conname = 'manual_deposits_user_id_fkey' AND contype = 'f'), to_regprocedure('extensions.uuid_generate_v4()') IS NOT NULL, to_regclass('public.idx_manual_deposits_user_id_fk') IS NULL, NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = to_regclass('public.manual_deposits') AND polname = 'manual_deposits_owner_admin_read'), to_regclass('public.withdraw_requests') IS NOT NULL, COALESCE((SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.withdraw_requests')), false), COALESCE((SELECT pg_get_userbyid(relowner) = 'postgres' FROM pg_class WHERE oid = to_regclass('public.withdraw_requests')), false), (SELECT count(*) FROM pg_attribute WHERE attrelid = to_regclass('public.withdraw_requests') AND attnum > 0 AND NOT attisdropped AND attname IN ('id','user_id','amount','status','created_at')) = 5, EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.withdraw_requests') AND conname = 'withdraw_requests_pkey' AND contype = 'p'), EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.withdraw_requests') AND conname = 'withdraw_requests_user_id_fkey' AND contype = 'f'), to_regclass('public.idx_withdraw_requests_user_id_fk') IS NULL, NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = to_regclass('public.withdraw_requests') AND polname = 'Users can insert own withdraw'), NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = to_regclass('public.withdraw_requests') AND polname = 'Users can view own withdraw'), to_regclass('public.user_bank_details') IS NOT NULL, COALESCE((SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.user_bank_details')), false), COALESCE((SELECT pg_get_userbyid(relowner) = 'postgres' FROM pg_class WHERE oid = to_regclass('public.user_bank_details')), false), (SELECT count(*) FROM pg_attribute WHERE attrelid = to_regclass('public.user_bank_details') AND attnum > 0 AND NOT attisdropped) = 8, EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.user_bank_details') AND conname = 'user_bank_details_pkey' AND contype = 'p'), EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.user_bank_details') AND conname = 'user_bank_details_user_id_fkey' AND contype = 'f'), EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.user_bank_details') AND conname = 'user_bank_details_user_id_key' AND contype = 'u'), NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = to_regclass('public.user_bank_details') AND polname IN ('Users can insert own bank','Users can view own bank','Users can update own bank')), (SELECT count(*) FROM public.user_bank_details) = 0, to_regclass('nplus_replay_audit.manual_deposits_overlay_marker') IS NOT NULL, EXISTS (SELECT 1 FROM nplus_replay_audit.manual_deposits_overlay_marker WHERE marker = 'manual_deposits_schema_overlay'), (SELECT count(*) FROM public.manual_deposits) = 0, (SELECT count(*) FROM public.withdraw_requests) = 0;"
    $expectedResumeChecks = 37
  }

  $resumeState = (& docker exec $ContainerName psql -X -U supabase_admin -d $ReplayDatabase -A -t -F '|' -c $resumeQuery 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the partial replay checkpoint. No migration was applied."
  }
  $resumeChecks = @($resumeState -split '\|')
  if ($resumeChecks.Count -ne $expectedResumeChecks -or @($resumeChecks | Where-Object { $_.Trim() -ne "t" }).Count -ne 0) {
    throw "Partial replay checkpoint does not match the expected state for version $ResumeFromVersion. No migration was applied. Observed: $resumeState"
  }
  if ($ResumeFromVersion -eq "20261023092858") {
    Write-Host "PASS: local-only manual_deposits + withdraw_requests overlay checkpoint verified. This is a suffix check, not a clean 40-row replay from the backup."
  } else {
    Write-Host "PASS: guarded resume checkpoint verified for $ReplayDatabase before migration $ResumeFromVersion."
  }
}

Write-Host "Step 2/5: re-run read-only backup acceptance against the restored baseline."
& docker cp $RestoreAcceptanceSql "${ContainerName}:$ContainerRestoreSql"
if ($LASTEXITCODE -ne 0) { throw "Could not copy the baseline acceptance SQL into the local container." }
& docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $VerifiedRestoreDatabase -f $ContainerRestoreSql
if ($LASTEXITCODE -ne 0) {
  throw "The restored base no longer passes its read-only acceptance checks. Do not start replay and do not change production."
}

if ([string]::IsNullOrWhiteSpace($ResumeFromVersion)) {
  Write-Host "Step 3/5: create a separate clone of the verified restored baseline."
  & docker exec $ContainerName pg_dump -Fc -U supabase_admin -d $VerifiedRestoreDatabase -f $ContainerDumpPath
  if ($LASTEXITCODE -ne 0) { throw "Could not dump the verified baseline to a temporary file inside the local container." }

  try {
    & docker exec $ContainerName createdb -U supabase_admin -T template0 $ReplayDatabase
    if ($LASTEXITCODE -ne 0) { throw "Could not create fresh replay database '$ReplayDatabase'." }

    # Preserve object owners and ACLs. Never add --no-owner or --no-acl.
    & docker exec $ContainerName pg_restore --exit-on-error --single-transaction -U supabase_admin -d $ReplayDatabase $ContainerDumpPath
    if ($LASTEXITCODE -ne 0) {
      throw "Baseline clone restore failed with owner/ACL checks enabled. Keep the isolated target for inspection; do not bypass the error."
    }
  }
  finally {
    # Remove only the temporary clone archive made by this script. The original
    # private backup and both databases are never deleted by this script.
    & docker exec $ContainerName rm -f $ContainerDumpPath 2>$null | Out-Null
  }
} else {
  Write-Host "Step 3/5: keeping the verified partial replay target; skipping already-passed versions 1 through $($resumeIndex - 1)."
}

if ($UseReconstructedLegacyBaseline) {
  $BootstrapPath = Join-Path $PSScriptRoot "fixtures\replay-baseline\reconstructed-live-legacy-schema-bootstrap.sql"
  $ContainerBootstrap = "/tmp/nplus-play-reconstructed-legacy-baseline.sql"
  if (-not (Test-Path -LiteralPath $BootstrapPath -PathType Leaf)) {
    throw "Reconstructed legacy baseline fixture is missing. No historical migration body will be applied."
  }
  Write-Host "Apply empty schema-only reconstruction from the verified live snapshot; this is not original historical DDL."
  & docker cp $BootstrapPath "${ContainerName}:$ContainerBootstrap"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy the reconstructed legacy baseline to the local replay database." }
  & docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $ContainerBootstrap
  if ($LASTEXITCODE -ne 0) { throw "Reconstructed legacy baseline failed verification. Replay stopped; production untouched." }
}

Write-Host "Step 4/5: replay the 40 applied SQL bodies in the recorded live-history order."
$index = 0
foreach ($row in $rows) {
  $index++
  if ($index -lt $resumeIndex) { continue }
  $migrationFile = Join-Path $SourceRoot ([string]$row.file)
  if (-not (Test-Path -LiteralPath $migrationFile -PathType Leaf)) {
    throw "Missing recovered SQL source for migration $($row.version): $migrationFile. Replay stopped; target DB was kept."
  }
  # Hash the exact recovered SQL evidence bytes; .gitattributes marks these
  # archived SQL snapshots -text to preserve mixed line endings on Windows.
  $actualHash = (Get-FileHash -LiteralPath $migrationFile -Algorithm MD5).Hash.ToLowerInvariant()
  if ($actualHash -ne ([string]$row.md5).ToLowerInvariant()) {
    throw "Source fingerprint mismatch at migration $($row.version). Replay stopped before applying this body; target DB was kept."
  }

  $containerSql = "/tmp/nplus-live-migration-$([string]$row.version).sql"
  & docker cp $migrationFile "${ContainerName}:$containerSql"
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy migration $($row.version) into the local container. Replay stopped; target DB was kept."
  }

  & docker exec $ContainerName psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $containerSql
  if ($LASTEXITCODE -ne 0) {
    throw "Replay failed at version $($row.version) ($($row.name)). Target DB '$ReplayDatabase' is a disposable partial replay for investigation. Do not skip the migration or apply it to production."
  }
  Write-Host ("PASS {0}/40 {1} {2}" -f $index, $row.version, $row.name)
}

if ($UseReconstructedLegacyBaseline) {
  # These candidate migrations and ACL snapshots are applied only after all 40 byte-
  # fingerprinted production-history bodies, in the disposable replay clone.
  $PostReplayFiles = @(
    "supabase/migrations/20261027120000_allow_qualified_demo_referral_state.sql",
    "supabase/migrations/20261027130000_harden_legacy_table_anon_privileges.sql",
    "supabase/migrations/20261027140000_fix_wingo_admin_overload_defaults.sql",
    "supabase/migrations/20261027150000_guard_finite_numeric_rpc_inputs.sql",
    "qa/fixtures/replay-baseline/wallet-ledger-browser-acl-overlay.sql",
    "qa/fixtures/replay-baseline/request-table-browser-acl-overlay.sql"
  )
  foreach ($relativePath in $PostReplayFiles) {
    $localPath = Join-Path $RepoRoot ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
      throw "Missing post-replay candidate/reconciliation file '$relativePath'. Final invariants will not be declared."
    }
    $containerPath = "/tmp/nplus-play-post-replay-$([IO.Path]::GetFileName($relativePath))"
    Write-Host "Apply disposable-clone candidate/reconciliation: $relativePath"
    & docker cp $localPath "${ContainerName}:$containerPath"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy local-only post-replay file '$relativePath'." }
    & docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $containerPath
    if ($LASTEXITCODE -ne 0) { throw "Post-replay candidate/reconciliation failed at '$relativePath'. Database kept for inspection; production untouched." }
  }
}

Write-Host "Step 5/5: run read-only replay invariants and object-count snapshot."
& docker cp $FinalStateSql "${ContainerName}:$ContainerFinalSql"
if ($LASTEXITCODE -ne 0) { throw "Could not copy the final state assertions into the local container." }
& docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $ContainerFinalSql
if ($LASTEXITCODE -ne 0) {
  throw "A replay invariant failed. Keep the isolated replay DB for diagnosis; do not patch production or skip a failing assertion."
}

if ($UseReconstructedLegacyBaseline) {
  $E2EPath = Join-Path $RepoRoot "qa\test-wallet-admin-referral-e2e.sql"
  $ContainerE2E = "/tmp/nplus-play-wallet-admin-referral-e2e.sql"
  if (-not (Test-Path -LiteralPath $E2EPath -PathType Leaf)) {
    throw "Synthetic wallet/Admin/referral E2E test is missing. Replay validation cannot be declared complete."
  }
  Write-Host "Run synthetic wallet/Admin/referral database E2E (test transaction rolls back synthetic rows)."
  & docker cp $E2EPath "${ContainerName}:$ContainerE2E"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy synthetic database E2E SQL to the replay clone." }
  & docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $ContainerE2E
  if ($LASTEXITCODE -ne 0) { throw "Synthetic wallet/Admin/referral E2E failed on the replay clone; production untouched." }
}

Write-Host ""
if ($ResumeFromVersion -eq "20261023092858") {
  Write-Host "MIGRATION SUFFIX CHECK PASSED for local database '$ReplayDatabase' after the QA-only legacy-schema overlay."
  Write-Host "IMPORTANT: this suffix check is not proof of original historical DDL or full backup replay."
} elseif ($UseReconstructedLegacyBaseline) {
  Write-Host "RECONSTRUCTED-BASELINE FULL REPLAY CHECK PASSED for local database '$ReplayDatabase'."
  Write-Host "All 40 captured production-history bodies were replayed after a separate schema-only bootstrap derived from the 2026-10-27 live catalog."
  Write-Host "Local candidate migrations, finite-numeric candidate migration, ACL reconciliation overlays, and final invariants were exercised on this clone."
  Write-Host "IMPORTANT: this does not prove the bootstrap is the original historical DDL or original policy/ACL history."
} else {
  Write-Host "MIGRATION REPLAY CHECK PASSED for local database '$ReplayDatabase'."
  Write-Host "Compare the printed object counts with the read-only production snapshot and inspect any differences before approving a canonical chain."
}
Write-Host "This test does not modify Supabase production and does not alter its migration-history table."
