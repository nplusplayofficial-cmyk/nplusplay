# N+ PLAY backup restore acceptance runner.
# Safe scope: creates a NEW database inside the LOCAL Docker restore-lab container.
# It never connects to Supabase production and never uses --no-owner or --no-acl.
# If the environment cannot restore original owners/ACLs, it stops and reports the error.

[CmdletBinding()]
param(
  [string]$ContainerName = "supabase_db_nplusplay-restore-lab-v2",
  [string]$TargetDatabase = "nplus_restore_acceptance_20261024"
)

$ErrorActionPreference = "Stop"
$BackupPath = Join-Path $HOME "NPLUS-PLAY-DB-BACKUP\nplus-play-full-2026-10-15.dump"
$ContainerBackupPath = "/tmp/nplus-play-backup-acceptance.dump"
$ContainerSqlPath = "/tmp/nplus-play-restore-acceptance.sql"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker CLI not found. Start the existing local restore lab first."
}
if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
  throw "Private backup not found at the expected local path: $BackupPath"
}
if ($TargetDatabase -notmatch '^nplus_restore_acceptance_[0-9]{8}$') {
  throw "Refusing unexpected database name. Use nplus_restore_acceptance_YYYYMMDD."
}

$containerState = (& docker inspect --format '{{.State.Running}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $containerState -ne "true") {
  throw "Expected LOCAL Docker container '$ContainerName' must already be running. No database action was taken."
}

$image = (& docker inspect --format '{{.Config.Image}}' $ContainerName 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $image -notmatch 'supabase') {
  throw "Container image does not look like the expected local Supabase PostgreSQL image ('$image'). No database action was taken."
}

Write-Host "Local container verified: $ContainerName ($image)"
Write-Host "Backup stays on this computer; it will only be copied into the local container."

try {
  & docker cp $BackupPath "${ContainerName}:$ContainerBackupPath"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy the private backup into the local container." }
  
  $archiveLines = & docker exec $ContainerName pg_restore --list $ContainerBackupPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "pg_restore --list failed. Do not attempt a restore until the archive error is reviewed."
  }
  $archiveText = $archiveLines -join "`n"
  if ($archiveText -notmatch 'TOC Entries:\s*661') {
    throw "The archive TOC count did not match the previously recorded 661 entries. Stop and inspect the archive output."
  }
  Write-Host "Archive listing verified (661 TOC entries)."
  
  $existingDb = (& docker exec $ContainerName psql -X -U supabase_admin -d postgres -A -t -c "SELECT 1 FROM pg_database WHERE datname = '$TargetDatabase';" 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the local container's database catalog using supabase_admin."
  }
  if ($existingDb -eq "1") {
    throw "Target database '$TargetDatabase' already exists. Nothing was dropped or overwritten; choose a new date suffix."
  }
  
  & docker exec $ContainerName createdb -U supabase_admin -T template0 $TargetDatabase
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create the new isolated restore database. Review local role/permission errors."
  }
  Write-Host "Created new isolated database: $TargetDatabase"
  
  # Intentionally preserve ownership and ACLs. Do NOT add --no-owner or --no-acl.
  & docker exec $ContainerName pg_restore --exit-on-error --single-transaction -U supabase_admin -d $TargetDatabase $ContainerBackupPath
  if ($LASTEXITCODE -ne 0) {
    throw "Full restore failed. No ownership/ACL bypass was used. Keep the isolated target for inspection; do not retry with --no-owner/--no-acl and do not touch production."
  }
  Write-Host "Full pg_restore completed without suppressing owner or ACL restoration."
  
  $SqlPath = Join-Path $PSScriptRoot "restore-backup-acceptance.sql"
  if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Validation SQL not found beside this script: $SqlPath"
  }
  & docker cp $SqlPath "${ContainerName}:$ContainerSqlPath"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy the local validation SQL." }
  
  & docker exec $ContainerName psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d $TargetDatabase -f $ContainerSqlPath
  if ($LASTEXITCODE -ne 0) {
    throw "Restored database did not pass integrity/security-object acceptance checks. Keep output private; never share rows, auth data or secrets."
  }
  
  Write-Host ""
  Write-Host "RESTORE ACCEPTANCE PASS for local database '$TargetDatabase'."
  Write-Host "This verifies this backup restore in the local lab only; it does not approve migration replay or change Supabase production."
}
finally {
  # The archive contains private account/wallet data. Remove only the temporary copy
  # and validation SQL from this local container on success or failure.
  $cleanupState = (& docker inspect --format '{{.State.Running}}' $ContainerName 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -eq 0 -and $cleanupState -eq "true") {
    & docker exec $ContainerName rm -f $ContainerBackupPath $ContainerSqlPath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Could not remove temporary private-backup files from the local container; inspect and clean them manually."
    } else {
      Write-Host "Temporary private backup copy and validation SQL removed from the local container."
    }
  } else {
    Write-Warning "Could not confirm local-container cleanup; if the container is stopped, check its /tmp directory before reusing it."
  }
}

