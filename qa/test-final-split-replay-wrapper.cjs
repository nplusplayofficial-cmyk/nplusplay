'use strict';
const fs = require('node:fs');
const path = require('node:path');
const wrapperPath = path.join(__dirname, 'run-final-split-replay.ps1');
if (!fs.existsSync(wrapperPath)) {
  console.error('FAIL: final split replay wrapper is missing');
  process.exit(1);
}
const source = fs.readFileSync(wrapperPath, 'utf8');
const checks = [
  ['requires the exact existing local restore-lab container', source.includes('supabase_db_nplusplay-restore-lab-v2') && source.includes('$ContainerName -ne $ExpectedContainerName')],
  ['requires a local Docker endpoint', source.includes("notmatch '^(npipe://|unix://)'")],
  ['rejects unverified restore-source names', source.includes("'^nplus_restore_acceptance_[0-9]{8}$'")],
  ['requires a date-suffixed replay target', source.includes("'^nplus_migration_replay_[0-9]{8}$'")],
  ['rejects replay target reuse instead of deleting/overwriting', source.includes("if ($ReplayDatabase -in $existingDatabases)") && source.includes('Refusing to reuse existing replay target')],
  ['fails closed if original cron setting is not the documented value', source.includes('$originalCronDatabase -ne $ExpectedOriginalCronDatabase')],
  ['changes cron only to the disposable local replay DB', source.includes('ALTER SYSTEM SET cron.database_name = \'$ReplayDatabase\'')],
  ['invokes the guarded reconstructed-baseline replay runner', source.includes('-UseReconstructedLegacyBaseline') && source.includes('replay-live-migration-sequence.ps1')],
  ['restores the original cron target in finally', source.includes('finally {') && source.includes("ALTER SYSTEM SET cron.database_name = '$ExpectedOriginalCronDatabase'")],
  ['verifies restored cron setting after restart', source.includes("SELECT current_setting('cron.database_name', true)") && source.includes('$restoredCronDatabase -ne $ExpectedOriginalCronDatabase')],
  ['does not drop databases or remove Docker containers', !/\bdropdb\b|\bDROP DATABASE\b|docker rm|Remove-Item/i.test(source)],
  ['fails explicitly if cron restoration fails', source.includes('CRITICAL: unable to verify restoration of the local cron setting')]
];
let failures = 0;
for (const [label, ok] of checks) {
  if (ok) console.log('PASS ' + label);
  else { console.error('FAIL ' + label); failures++; }
}
if (failures) process.exitCode = 1;
else console.log('PASS: one-command local replay wrapper contract and fail-closed cleanup guards.');
