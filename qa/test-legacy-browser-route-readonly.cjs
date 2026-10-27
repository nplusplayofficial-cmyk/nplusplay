#!/usr/bin/env node
'use strict';

// Static UI contract: legacy payment/bank tables must not be directly written
// from browser code. The legacy Admin deposit section is reconciliation-only.
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const excluded = new Set(['.git', 'node_modules', 'qa', 'docs', 'sql', 'supabase', '.github']);
const extensions = new Set(['.html', '.js', '.mjs', '.cjs', '.ts', '.tsx']);
const failures = [];
const tableReferences = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!excluded.has(entry.name)) walk(path.join(dir, entry.name));
      continue;
    }
    if (!extensions.has(path.extname(entry.name).toLowerCase())) continue;
    const file = path.join(dir, entry.name);
    const relative = path.relative(root, file).replace(/\\/g, '/');
    const source = fs.readFileSync(file, 'utf8');
    const rx = /\.from\s*\(\s*(['"`])(manual_deposits|user_bank_details|withdraw_requests)\1\s*\)/g;
    let m;
    while ((m = rx.exec(source))) {
      tableReferences.push({ file: relative, table: m[2], offset: m.index, source });
    }
  }
}

walk(root);

for (const item of tableReferences) {
  if (item.table === 'user_bank_details' || item.table === 'withdraw_requests') {
    failures.push(item.file + ' directly queries legacy table ' + item.table);
    continue;
  }
  if (item.file !== 'admin-deposits.html') {
    failures.push(item.file + ' references manual_deposits outside the Admin reconciliation screen');
    continue;
  }
  const context = item.source.slice(item.offset, item.offset + 220);
  if (!/^\.from\s*\(\s*(['"`])manual_deposits\1\s*\)\s*\.select\s*\(/.test(context)) {
    failures.push('admin-deposits.html must SELECT legacy manual_deposits only');
  }
}

const adminPath = path.join(root, 'admin-deposits.html');
const admin = fs.existsSync(adminPath) ? fs.readFileSync(adminPath, 'utf8') : '';
const legacyStart = admin.indexOf('async function loadLegacy()');
const legacyEnd = admin.indexOf('async function loadAll()', legacyStart);
if (legacyStart < 0 || legacyEnd <= legacyStart) {
  failures.push('admin-deposits.html legacy read-only section could not be identified');
} else {
  const legacyBlock = admin.slice(legacyStart, legacyEnd);
  if (!/\.from\s*\(\s*(['"`])manual_deposits\1\s*\)\s*\.select\s*\(/.test(legacyBlock)) {
    failures.push('legacy Admin section must load manual_deposits with SELECT');
  }
  if (/\.from\s*\(\s*(['"`])manual_deposits\1\s*\)\s*\.\s*(?:insert|update|upsert|delete)\s*\(/i.test(legacyBlock)) {
    failures.push('legacy Admin section must not mutate manual_deposits');
  }
  if (/\.rpc\s*\(/i.test(legacyBlock)) {
    failures.push('legacy Admin section must not send legacy rows to an approval RPC');
  }
  if (!/READ-ONLY/i.test(admin) || !/will not approve them, change their status, or credit a wallet/i.test(admin)) {
    failures.push('legacy reconciliation UI must display its read-only/no-credit contract');
  }
}

if (failures.length) {
  for (const failure of failures) console.error('FAIL: ' + failure);
  console.error('Legacy browser-route read-only contract failed.');
  process.exit(1);
}
console.log('PASS: no browser code directly queries user_bank_details or withdraw_requests.');
console.log('PASS: manual_deposits is queried only by admin-deposits.html.');
console.log('PASS: legacy Admin rows are SELECT-only and never sent to an approval RPC.');
