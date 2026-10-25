# Replay the 40 captured production migration bodies on a fresh LOCAL copy
# of the 2026-10-15 backup, then check critical invariants.
# Never connects to production. Never drops/replaces an existing database.
# Stops on the first failure and leaves the disposable replay DB for inspection.

[CmdletBinding()]
param(
  [string]$ContainerName = "supabase_db_nplusplay-restore-lab-v2",
  [string]$VerifiedRestoreDatabase = "nplus_restore_acceptance_20261024",
  [string]$ReplayDatabase = "nplus_migration_replay_20261024"
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
if ($targetExists -eq "1") {
  throw "Replay target '$ReplayDatabase' already exists. Nothing was dropped or overwritten; choose a new date suffix."
}

Write-Host "Step 2/5: re-run read-only backup acceptance against the restored baseline."
& docker cp $RestoreAcceptanceSql "${ContainerName}:$ContainerRestoreSql"
if ($LASTEXITCODE -ne 0) { throw "Could not copy the baseline acceptance SQL into the local container." }
& docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $VerifiedRestoreDatabase -f $ContainerRestoreSql
if ($LASTEXITCODE -ne 0) {
  throw "The restored base no longer passes its read-only acceptance checks. Do not start replay and do not change production."
}

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

Write-Host "Step 4/5: replay the 40 applied SQL bodies in the recorded live-history order."
$index = 0
foreach ($row in $rows) {
  $index++
  $migrationFile = Join-Path $SourceRoot ([string]$row.file)
  if (-not (Test-Path -LiteralPath $migrationFile -PathType Leaf)) {
    throw "Missing recovered SQL source for migration $($row.version): $migrationFile. Replay stopped; target DB was kept."
  }
  # Windows checkout may convert LF to CRLF. Normalize line endings before
  # comparing the source body with the read-only production fingerprint.
  $normalizedSql = [regex]::Replace([System.IO.File]::ReadAllText($migrationFile), "\r\n?", "`n")
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $normalizedBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedSql)
    $actualHash = ([BitConverter]::ToString($md5.ComputeHash($normalizedBytes))).Replace("-", "").ToLowerInvariant()
  }
  finally {
    $md5.Dispose()
  }
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

Write-Host "Step 5/5: run read-only replay invariants and object-count snapshot."
& docker cp $FinalStateSql "${ContainerName}:$ContainerFinalSql"
if ($LASTEXITCODE -ne 0) { throw "Could not copy the final state assertions into the local container." }
& docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $ReplayDatabase -f $ContainerFinalSql
if ($LASTEXITCODE -ne 0) {
  throw "A replay invariant failed. Keep the isolated replay DB for diagnosis; do not patch production or skip a failing assertion."
}

Write-Host ""
Write-Host "MIGRATION REPLAY CHECK PASSED for local database '$ReplayDatabase'."
Write-Host "Compare the printed object counts with the read-only production snapshot and inspect any differences before approving a canonical chain."
Write-Host "This test does not modify Supabase production and does not alter its migration-history table."
