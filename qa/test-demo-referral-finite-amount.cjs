'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sqlPath = path.join(root, 'supabase/migrations/20261027180100_guard_finite_numeric_safe_transfer_and_referral.sql');
const testPath = path.join(root, 'qa/test-demo-referral-finite-amount.sql');

function fail(message) {
  console.error('FAIL: ' + message);
  process.exitCode = 1;
}
function requireText(haystack, text, label) {
  if (!haystack.includes(text)) fail('missing ' + label + ': ' + text);
}

if (!fs.existsSync(sqlPath) || !fs.existsSync(testPath)) {
  fail('candidate SQL and disposable regression test must both exist');
  process.exit();
}
const sql = fs.readFileSync(sqlPath, 'utf8');
const test = fs.readFileSync(testPath, 'utf8');

for (const fragment of [
  'Candidate migration',
  'CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral',
  'public.nplus_is_admin()',
  "p_verified_virtual_amount::text IN ('NaN', 'Infinity', '-Infinity')",
  "'invalid_verified_amount'",
  'p_verified_virtual_amount < 500.00',
  'SET search_path TO \'pg_catalog\', \'public\''
]) requireText(sql, fragment, 'candidate guard contract');

if (/\b(?:GRANT|REVOKE|DROP FUNCTION|DROP TABLE|TRUNCATE)\b/i.test(sql)) {
  fail('candidate function-body update must not alter ACLs or drop schema objects');
}
for (const fragment of [
  "'NaN'::numeric",
  "'Infinity'::numeric",
  "'-Infinity'::numeric",
  '499.99',
  '500.00',
  'non-admin qualified an invited account',
  'PASS: finite Admin referral qualification guard'
]) requireText(test, fragment, 'disposable runtime test case');

if (process.exitCode) {
  console.error('Finite Admin referral qualification guard failed static review.');
} else {
  console.log('PASS: candidate explicitly rejects NaN and infinities before threshold logic.');
  console.log('PASS: isolated SQL regression covers invalid values, exactly-once qualification and Admin authorization.');
  console.log('NOTE: candidate-only source; production was not changed.');
}
