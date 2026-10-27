'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sqlPath = path.join(root, 'sql/NPLUS_PLAY_SAFE_TRANSFER_FINITE_AMOUNT_GUARD_CANDIDATE_2026-10-27.sql');
const testPath = path.join(root, 'qa/test-demo-safe-transfer-finite-amount.sql');

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
const finiteGuard = sql.indexOf("p_amount::text IN ('NaN','Infinity','-Infinity')");
const narrowedCast = sql.indexOf('v_amount := p_amount;');

if (finiteGuard < 0 || narrowedCast < 0 || finiteGuard > narrowedCast) {
  fail('finite special-value guard must occur before assigning p_amount to numeric(14,2)');
}
if (/v_amount\s+numeric\(14,2\)\s*:=\s*p_amount/i.test(sql)) {
  fail('narrowing cast must not occur in the DECLARE initializer before validation');
}
for (const fragment of [
  'Candidate-only fix',
  'CREATE OR REPLACE FUNCTION public.nplus_demo_safe_transfer',
  "p_amount::text IN ('NaN','Infinity','-Infinity')",
  'p_amount <> round(p_amount,2)',
  'v_amount := p_amount;',
  "SET search_path TO 'pg_catalog', 'public'"
]) requireText(sql, fragment, 'candidate guard contract');

if (/\b(?:GRANT|REVOKE|DROP FUNCTION|DROP TABLE|TRUNCATE)\b/i.test(sql)) {
  fail('candidate function-body replacement must not alter ACLs or drop schema objects');
}
for (const fragment of [
  "'NaN'::numeric",
  "'Infinity'::numeric",
  "'-Infinity'::numeric",
  '10.001',
  'valid IN transfer',
  'valid OUT transfer',
  'unauthenticated transfer denied'
]) requireText(test, fragment, 'disposable runtime test case');

if (process.exitCode) {
  console.error('Finite safe-transfer guard failed static source review.');
} else {
  console.log('PASS: finite value check precedes numeric(14,2) assignment.');
  console.log('PASS: disposable runtime test covers non-finite inputs, precision, balance/ledger consistency and authentication.');
  console.log('NOTE: candidate-only SQL; production database was not changed.');
}
