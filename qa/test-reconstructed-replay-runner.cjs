'use strict';
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const runnerPath=path.join(root,'qa/replay-live-migration-sequence.ps1');
const bootstrapPath=path.join(root,'qa/fixtures/replay-baseline/reconstructed-live-legacy-schema-bootstrap.sql');
const invariantPath=path.join(root,'qa/verify-replayed-migration-state.sql');
const e2ePath=path.join(root,'qa/test-wallet-admin-referral-e2e.sql');
let errors=0;
function fail(s){errors++;console.error('FAIL '+s);}
for(const [p,label] of [[runnerPath,'replay runner'],[bootstrapPath,'legacy bootstrap'],[invariantPath,'final invariant SQL'],[e2ePath,'synthetic database E2E']]){
 if(!fs.existsSync(p))fail(label+' file is missing');
}
if(errors){process.exitCode=1;process.exit();}
const runner=fs.readFileSync(runnerPath,'utf8');
const bootstrap=fs.readFileSync(bootstrapPath,'utf8');
const invariant=fs.readFileSync(invariantPath,'utf8');
const checks=[
 ['explicit opt-in switch',runner.includes('[switch]$UseReconstructedLegacyBaseline')],
 ['resume + reconstructed mode conflict rejected',runner.includes('cannot be combined with ResumeFromVersion')],
 ['bootstrap applied before historical replay',runner.indexOf('$BootstrapPath')<runner.indexOf('foreach ($row in $rows)')],
 ['replay still checks exact 40-record sequence',runner.includes('$rows.Count -ne 40')],
 ['exact per-body source fingerprint remains enforced',runner.includes('Source fingerprint mismatch at migration')],
 ['candidate referral lifecycle migration included',runner.includes('20261027120000_allow_qualified_demo_referral_state.sql')],
 ['legacy ACL hardening candidate included',runner.includes('20261027130000_harden_legacy_table_anon_privileges.sql')],
 ['finite numeric candidate migration included',runner.includes('20261027150000_guard_finite_numeric_rpc_inputs.sql')],
 ['WINGO overload migration included',runner.includes('20261027140000_fix_wingo_admin_overload_defaults.sql')],
 ['wallet ACL reconciliation before request ACL reconciliation',runner.indexOf('wallet-ledger-browser-acl-overlay.sql')<runner.indexOf('request-table-browser-acl-overlay.sql')],
 ['synthetic database E2E actually invoked',runner.includes('test-wallet-admin-referral-e2e.sql')&&runner.includes('Synthetic wallet/Admin/referral E2E failed')],
 ['final invariant step runs before synthetic E2E',runner.indexOf('$FinalStateSql')<runner.indexOf('$E2EPath')],
 ['bootstrap documents non-historical provenance',bootstrap.includes('NOT original historical DDL')],
 ['bootstrap only runs on a date-suffixed replay DB',bootstrap.includes("current_database() !~ '^nplus_migration_replay_[0-9]{8}$'")],
 ['bootstrap refuses if any legacy table already exists',bootstrap.includes('already exists; nothing was changed')],
 ['final invariant validates legacy ACL contract',invariant.includes('legacy table browser ACLs differ from the reviewed least-privilege contract')]
];
for(const [label,ok] of checks){if(ok)console.log('PASS '+label);else fail(label);}
if(errors)process.exitCode=1;
else console.log('PASS: reconstructed replay runner contract; QA-only and provenance limits retained.');
