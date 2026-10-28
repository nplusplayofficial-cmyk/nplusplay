#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(root, 'supabase/migrations/20261027172625_20261027120000_allow_qualified_demo_referral_state.sql');
const e2ePath = path.join(root, 'qa/test-wallet-admin-referral-e2e.sql');

function fail(message) {
  console.error('FAIL: ' + message);
  process.exitCode = 1;
}

if (!fs.existsSync(migrationPath)) {
  fail('missing qualified referral-state follow-up migration');
  process.exit();
}
if (!fs.existsSync(e2ePath)) {
  fail('missing wallet/Admin/referral E2E regression test');
  process.exit();
}

const migration = fs.readFileSync(migrationPath, 'utf8');
const e2e = fs.readFileSync(e2ePath, 'utf8');

const requiredMigrationFragments = [
  'BEGIN;',
  "to_regclass('public.nplus_demo_referrals') IS NULL",
  "column_name='rewarded_at'",
  'DROP CONSTRAINT IF EXISTS nplus_demo_referrals_status_check',
  'DROP CONSTRAINT IF EXISTS nplus_demo_referrals_reward_state_check',
  "CHECK (status IN ('pending','qualified','rewarded'))",
  "status='pending'",
  "status='qualified'",
  "status='rewarded'",
  'qualifying_request_id IS NULL',
  'qualified_at IS NOT NULL',
  'rewarded_at IS NULL',
  'reward_amount = 0.00',
  'COMMIT;'
];

for (const fragment of requiredMigrationFragments) {
  if (!migration.includes(fragment)) {
    fail('qualified-state migration is missing required guard/state fragment: ' + fragment);
  }
}

if (!migration.includes('Candidate migration only') ||
    /\b(?:GRANT|REVOKE)\b/i.test(migration) ||
    /\b(?:DROP TABLE|TRUNCATE|DELETE FROM)\b/i.test(migration)) {
  fail('migration must remain candidate-only and must not alter table privileges or delete data');
}

const requiredE2eFragments = [
  "nplus_demo_admin_qualify_referral(v_invited,500)",
  "v_result->>'reason'<>'approval_driven'",
  "nplus_demo_claim_referral_bonus(1)",
  "v_result->>'reason'<>'tier_claims_disabled'",
  "v_referral_status IS DISTINCT FROM 'rewarded'",
  'v_referral_reward IS DISTINCT FROM 20.00',
  'v_referral_request IS DISTINCT FROM v_deposit_id',
  'v_referral_qualified_at IS NULL',
  'v_referral_rewarded_at IS NULL',
  "coalesce((v_result->>'total_rewards')::numeric,-1)<>20",
  'ROLLBACK;'
];
for (const fragment of requiredE2eFragments) {
  if (!e2e.includes(fragment)) {
    fail('wallet/Admin/referral E2E test is missing regression fragment: ' + fragment);
  }
}

if (process.exitCode) {
  console.error('Qualified demo referral-state regression contract failed.');
} else {
  console.log('PASS qualified referral lifecycle migration guard and state contract.');
  console.log('PASS E2E enforces the approved 200/20 trigger, disables old tier/manual paths, and rolls back synthetic data.');
  console.log('NOTE static contract only; run the isolated database E2E for runtime validation.');
}
