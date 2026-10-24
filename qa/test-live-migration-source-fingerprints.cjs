#!/usr/bin/env node
'use strict';

// Verifies recovered SQL evidence files against MD5 fingerprints calculated
// read-only from public.supabase_migrations.schema_migrations on 2026-10-24.
// This is a source-integrity check only, not a migration replay test.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const sourceDir = path.join(root, 'docs/recovered-live-migration-sql-2026-10-23');

const expected = {
  '20261020135823_block_generic_wallet_credits_before_game_rpc_deployment.sql': '2850de2e52763443e12cf336e5bda002',
  '20261020162640_temporarily_pause_games_until_authoritative_backend_rollout.sql': '370856a6454d23c768ad1cb871ce1a3d',
  '20261020162811_null_safe_admin_rpc_authorization_guard.sql': '9f8b84431d2717292fbe528cab6a2e4a',
  '20261021155813_admin_game_status_fail_closed_guard.sql': 'c9b30fb18008b9b8b3d61fe3bdbb0c25',
  '20261021160439_account_preferences_release_support.sql': '670231ad75fadaf0d55a6791ec4c70a4',
  '20261021160443_demo_wallet_requests_release_support.sql': '0683f8ea730b1861ac71ff63c1181609',
  '20261021160446_admin_deposit_actions_release_support.sql': '425287208f2add7902d084748980f7e8',
  '20261021160503_demo_referrals_base_release_support.sql': 'dac41d2de70765aaa230e5fec8d172e1',
  '20261021160917_nplus_vip_referral_demo.sql': 'e09b3db6a2adce61c3d587a7f0856941',
  '20261021160935_nplus_server_settlement_foundation.sql': '0f401164b791555350fe667adf579821',
  '20261021161052_nplus_motorace_schema.sql': '4757f2cab064399bd17135c5cba3bd1f',
  '20261021161109_nplus_motorace_rpc.sql': '62ddf12081dde7f41ed2c330536ba4fe',
  '20261021161129_nplus_aviator_schema.sql': '35729c3cbfc089da87d9dab49a0bef30',
  '20261021161143_nplus_aviator_rpc.sql': 'e7f9ea285515cbfc7d9722219795569e',
  '20261021161152_nplus_aviator_worker_recovery.sql': 'f9eb22c6ab349c747f221c3edb544397',
  '20261021161206_nplus_aviator_persistent_scheduler.sql': 'aafd879eb774f25765595c1b13369210',
  '20261021161217_nplus_admin_user_tools.sql': 'f071a5385b87239b255b91a28e700c60',
  '20261021161233_nplus_admin_game_status.sql': 'd98bd9344d6591971ca3212007cf3967',
  '20261021161242_nplus_admin_null_profile_guard.sql': 'baf2caaf9cd8ec227319ae43ecc08eb0',
  '20261021161251_nplus_recent_demo_activity.sql': '4ac4a9427f9f47145197da5e1068ba0d',
  '20261021162503_post_rollout_revoke_phone_enumeration.sql': '71e8ad4581449eb4aea6c321315bfc46',
  '20261021162645_enable_server_backed_virtual_demo_games.sql': '4354d93ff2b85cc37c047afc263e35c5',
  '20261022062741_enable_supported_virtual_demo_games_preview.sql': '3832fd6a90faed6f292ab4650a2f29c2',
  '20261022064315_pause_unverified_games_and_lockdown_settlement_rpcs_20261022.sql': '4265e6ddcf88987f1f0ea85a4d4ea516',
  '20261023081657_fix_profiles_rls_admin_login_recursion_20261023.sql': 'a685847a88eec5470fa7e9c4295986fb',
  '20261023081758_secure_admin_demo_wallet_adjustment_rpc_20261023.sql': '4ffc0b1a970bcc33698300f66a6c3cb5',
  '20261023081916_align_admin_wallet_adjust_rpc_signature_20261023.sql': '14cb2a06f11f7f94712d1a49faa9a0ec',
  '20261023092858_optimize_rls_policies_and_foreign_key_indexes_20261023.sql': '26f384c480ba6353c749f5cd8adb6da9',
  '20261023093056_drop_duplicate_referral_unique_indexes_20261023.sql': '5660665b15239a33df937e709ee86fd3'
};

let failures = 0;
for (const [name, digest] of Object.entries(expected)) {
  const file = path.join(sourceDir, name);
  if (!fs.existsSync(file)) {
    console.error('FAIL missing recovered source: ' + name);
    failures++;
    continue;
  }
  const actual = crypto.createHash('md5').update(fs.readFileSync(file)).digest('hex');
  if (actual !== digest) {
    console.error('FAIL body fingerprint mismatch: ' + name + ' expected=' + digest + ' actual=' + actual);
    failures++;
  } else {
    console.log('PASS applied-body fingerprint: ' + name);
  }
}
const sqlFiles = fs.readdirSync(sourceDir).filter(name => name.endsWith('.sql'));
if (sqlFiles.length !== Object.keys(expected).length) {
  console.error('FAIL expected 29 distinct SQL evidence files; found ' + sqlFiles.length);
  failures++;
}
const duplicatePairs = [
  ['20261021160935', '20261022055326'],
  ['20261021161052', '20261022055330'],
  ['20261021161109', '20261022055334'],
  ['20261021161129', '20261022055340'],
  ['20261021161143', '20261022055345'],
  ['20261021161152', '20261022055350'],
  ['20261021161206', '20261022055354'],
  ['20261021161217', '20261022055400'],
  ['20261021161233', '20261022055404'],
  ['20261021161242', '20261022055410'],
  ['20261021161251', '20261022055424']
];
const evidenceReadme = fs.readFileSync(
  path.join(sourceDir, 'README.md'), 'utf8'
);
for (const pair of duplicatePairs) {
  if (!evidenceReadme.includes(pair[0]) || !evidenceReadme.includes(pair[1])) {
    console.error('FAIL duplicate body pair missing from replay-safety inventory: ' + pair.join(' / '));
    failures++;
  }
}
if (duplicatePairs.length !== 11) {
  console.error('FAIL expected 11 exact duplicate-body pairs in replay-safety inventory.');
  failures++;
}

const orderPath = path.join(root, 'qa/migration-replay-order-2026-10-24.json');
if (!fs.existsSync(orderPath)) {
  console.error('FAIL missing exact 40-row live migration replay order inventory');
  failures++;
} else {
  let rows;
  try {
    rows = JSON.parse(fs.readFileSync(orderPath, 'utf8'));
  } catch (error) {
    console.error('FAIL replay-order JSON is invalid: ' + error.message);
    failures++;
    rows = [];
  }
  const expectedVersions = [
    '20261020135823','20261020162640','20261020162811','20261021155813',
    '20261021160439','20261021160443','20261021160446','20261021160503',
    '20261021160917','20261021160935','20261021161052','20261021161109',
    '20261021161129','20261021161143','20261021161152','20261021161206',
    '20261021161217','20261021161233','20261021161242','20261021161251',
    '20261021162503','20261021162645','20261022055326','20261022055330',
    '20261022055334','20261022055340','20261022055345','20261022055350',
    '20261022055354','20261022055400','20261022055404','20261022055410',
    '20261022055424','20261022062741','20261022064315','20261023081657',
    '20261023081758','20261023081916','20261023092858','20261023093056'
  ];
  if (rows.length !== 40 ||
      rows.map(row => String(row.version)).join('|') !== expectedVersions.join('|')) {
    console.error('FAIL replay-order inventory must list the exact 40 applied versions in order.');
    failures++;
  }
  if (new Set(rows.map(row => String(row.version))).size !== 40) {
    console.error('FAIL replay-order inventory contains duplicate version IDs.');
    failures++;
  }
  const referencedSources = new Set();
  for (const row of rows) {
    referencedSources.add(String(row.file));
    if (!expected[row.file] || expected[row.file] !== String(row.md5)) {
      console.error('FAIL replay-order row hash/source does not match fingerprint manifest: ' + row.version);
      failures++;
    }
    if (!row.name || !String(row.version).match(/^\d{14}$/)) {
      console.error('FAIL malformed replay-order row metadata: ' + JSON.stringify(row));
      failures++;
    }
  }
  if (referencedSources.size !== 29) {
    console.error('FAIL the 40-row order must map to exactly 29 distinct SQL bodies; found ' + referencedSources.size);
    failures++;
  } else {
    console.log('PASS exact 40-row replay order maps to 29 fingerprinted SQL bodies.');
  }
}
const replayRunnerPath = path.join(root, 'qa/replay-live-migration-sequence.ps1');
const replayChecksPath = path.join(root, 'qa/verify-replayed-migration-state.sql');
if (!fs.existsSync(replayRunnerPath) || !fs.existsSync(replayChecksPath)) {
  console.error('FAIL missing isolated replay runner or invariant SQL.');
  failures++;
} else {
  const runner = fs.readFileSync(replayRunnerPath, 'utf8');
  const replayChecks = fs.readFileSync(replayChecksPath, 'utf8');
  if (!runner.includes('nplus_restore_acceptance_') ||
      !runner.includes('nplus_migration_replay_') ||
      !runner.includes('pg_dump -Fc') ||
      !runner.includes('pg_restore --exit-on-error --single-transaction') ||
      !runner.includes('ON_ERROR_STOP=1') ||
      !runner.includes('test-live-migration-source-fingerprints.cjs')) {
    console.error('FAIL replay runner is missing required local-clone/fingerprint/stop-on-error safeguards.');
    failures++;
  }
  if (/^\s*&\s*docker exec[^\n]*\bdropdb\b/im.test(runner) ||
      /^\s*&\s*docker exec[^\n]*pg_restore[^\n]*--no-owner/im.test(runner) ||
      /^\s*&\s*docker exec[^\n]*pg_restore[^\n]*--no-acl/im.test(runner)) {
    console.error('FAIL replay runner must never drop databases or suppress owner/ACL restore errors.');
    failures++;
  }
  for (const invariant of [
    'all six games remain disabled',
    'generic wallet positive/game-credit guard exists',
    'server-only',
    'ledger arithmetic remains consistent'
  ]) {
    if (!replayChecks.toLowerCase().includes(invariant.toLowerCase())) {
      console.error('FAIL replay-state SQL is missing required invariant: ' + invariant);
      failures++;
    }
  }
}
if (failures) {
  console.error('Recovered migration source fingerprint audit failed: ' + failures + ' issue(s).');
  process.exitCode = 1;
} else {
  console.log('PASS all 29 recovered SQL bodies match the captured applied-body fingerprints.');
  console.log('This verifies source text only. It does not prove clean replay, idempotence, restore parity, or production readiness.');
}
