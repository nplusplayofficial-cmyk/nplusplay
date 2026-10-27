# Run the exact split-migration replay against the EXISTING LOCAL restore lab.
# This wrapper never connects to production, never drops databases, and restores the prior
# local pg_cron target in finally, even when the replay throws.
[CmdletBinding()]
param(
  [string]$ContainerName = "supabase_db_nplusplay-restore-lab-v2",
  [string]$VerifiedRestoreDatabase = "nplus_restore_acceptance_20261027",
  [string]$ReplayDatabase = "nplus_migration_replay_20261031",
  [string]$ExpectedOriginalCronDatabase = "nplus_migration_replay_20261026"
)

$ErrorActionPreference = "Stop"
$ExpectedContainerName = "supabase_db_nplusplay-restore-lab-v2"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ReplayRunner = Join-Path $PSScriptRoot "replay-live-migration-sequence.ps1"
$cronChanged = $false
$replayFailure = $null
$restoreFailure = $null
$originalCronDatabase = $null

function Invoke-LocalPsql([string]$Database, [string]$Sql) {
  $output = & docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $Database -A -t -c $Sql 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Local psql query failed for database '$Database': $($output | Out-String)"
  }
  return ($output | Out-String).Trim()
}

function Restart-And-WaitForLocalPostgres {
  & docker restart $ContainerName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not restart the expected local restore-lab container." }
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & docker exec $ContainerName pg_isready -U supabase_admin -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 2
  }
  throw "Local PostgreSQL did not become ready within 60 seconds."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker CLI not found. No database action was taken."
}
if ($ContainerName -ne $ExpectedContainerName) {
  throw "Refusing container '$ContainerName'. Only '$ExpectedContainerName' is allowed."
}
if ($VerifiedRestoreDatabase -notmatch '^nplus_restore_acceptance_[0-9]{8}$') {
  throw "Restore source must be named nplus_restore_acceptance_YYYYMMDD."
}
if ($ReplayDatabase -notmatch '^nplus_migration_replay_[0-9]{8}$') {
  throw "Replay target must be named nplus_migration_replay_YYYYMMDD."
}
if ($VerifiedRestoreDatabase -eq $ReplayDatabase) {
  throw "Restore source and replay target must be different databases."
}
if ($ExpectedOriginalCronDatabase -ne "nplus_migration_replay_20261026") {
  throw "This wrapper only restores the documented prior cron target nplus_migration_replay_20261026."
}
if (-not (Test-Path -LiteralPath $ReplayRunner -PathType Leaf)) {
  throw "Replay runner not found: $ReplayRunner"
}
$dockerContext = (& docker context show 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dockerContext)) {
  throw "Could not identify Docker context. No database action was taken."
}
$dockerEndpoint = (& docker context inspect $dockerContext --format '{{.Endpoints.docker.Host}}' 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $dockerEndpoint -notmatch '^(npipe://|unix://)') {
  throw "Refusing non-local Docker endpoint '$dockerEndpoint'. No database action was taken."
}
if ($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe://|unix://)') {
  throw "DOCKER_HOST is non-local. No database action was taken."
}
$running = (& docker inspect --format '{{.State.Running}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $running -ne "true") {
  throw "Expected existing local restore-lab must already be running."
}
$image = (& docker inspect --format '{{.Config.Image}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $image -notmatch 'supabase') {
  throw "Container image '$image' is not the expected local Supabase PostgreSQL image."
}

$originalCronDatabase = Invoke-LocalPsql "postgres" "SELECT current_setting('cron.database_name', true);"
if ($originalCronDatabase -ne $ExpectedOriginalCronDatabase) {
  throw "Refusing unexpected prior cron.database_name '$originalCronDatabase'. Expected '$ExpectedOriginalCronDatabase'; review local lab settings before retrying."
}
$databaseRows = Invoke-LocalPsql "postgres" "SELECT datname FROM pg_database WHERE datname IN ('$VerifiedRestoreDatabase','$ReplayDatabase') ORDER BY datname;"
$existingDatabases = @($databaseRows -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($VerifiedRestoreDatabase -notin $existingDatabases) {
  throw "Verified restore source '$VerifiedRestoreDatabase' does not exist. No change was made."
}
if ($ReplayDatabase -in $existingDatabases) {
  throw "Refusing to reuse existing replay target '$ReplayDatabase'. Choose a new unused date-suffixed target; no database is dropped or overwritten."
}

Write-Host "Local container verified: $ContainerName ($image)"
Write-Host "Verified restore source exists; fresh replay target is unused."
Write-Host "The wrapper will temporarily change only local cron.database_name, run the reconstructed-baseline replay, and restore the prior value in finally."

try {
  [void](Invoke-LocalPsql "postgres" "ALTER SYSTEM SET cron.database_name = '$ReplayDatabase';")
  $cronChanged = $true
  Restart-And-WaitForLocalPostgres
  $activeCronDatabase = Invoke-LocalPsql "postgres" "SELECT current_setting('cron.database_name', true);"
  if ($activeCronDatabase -ne $ReplayDatabase) {
    throw "Local cron.database_name is '$activeCronDatabase', expected '$ReplayDatabase'. Replay was not started."
  }

  Push-Location $RepoRoot
  try {
    & $ReplayRunner -ContainerName $ContainerName -VerifiedRestoreDatabase $VerifiedRestoreDatabase -ReplayDatabase $ReplayDatabase -UseReconstructedLegacyBaseline
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
      throw "Replay runner returned exit code $LASTEXITCODE."
    }
  }
  finally {
    Pop-Location
  }
}
catch {
  $replayFailure = $_.Exception.Message
}
finally {
  if ($cronChanged) {
    try {
      [void](Invoke-LocalPsql "postgres" "ALTER SYSTEM SET cron.database_name = '$ExpectedOriginalCronDatabase';")
      Restart-And-WaitForLocalPostgres
      $restoredCronDatabase = Invoke-LocalPsql "postgres" "SELECT current_setting('cron.database_name', true);"
      if ($restoredCronDatabase -ne $ExpectedOriginalCronDatabase) {
        throw "Verification returned '$restoredCronDatabase' instead of '$ExpectedOriginalCronDatabase'."
      }
      Write-Host "PASS: restored local cron.database_name to $ExpectedOriginalCronDatabase."
    }
    catch {
      $restoreFailure = $_.Exception.Message
    }
  }
}

if ($restoreFailure) {
  throw "CRITICAL: unable to verify restoration of the local cron setting. Restore it manually before using the lab. Details: $restoreFailure"
}
if ($replayFailure) {
  throw "Local replay did not pass. The previous cron setting was restored. Preserve '$ReplayDatabase' for diagnosis; do not delete or overwrite it. Details: $replayFailure"
}
Write-Host "PASS: reconstructed-baseline split-migration replay sequence completed; local cron setting restored."
Write-Host "Scope reminder: this proves only reconstructed-baseline local replay, not original historical DDL/ACL provenance or hosted Auth acceptance."
