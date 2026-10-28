'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const files = [
  'k3.html',
  '5d.html',
  'trx-wingo.html',
  'referral.html',
  'vip.html',
  'admin-vip.html',
  'admin-games.html'
];
let checked = 0;
let failures = 0;

for (const relative of files) {
  const full = path.join(root, relative);
  if (!fs.existsSync(full)) {
    console.error('FAIL missing HTML file: ' + relative);
    failures++;
    continue;
  }
  const html = fs.readFileSync(full, 'utf8');
  const scripts = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
  let match;
  let inlineIndex = 0;
  while ((match = scripts.exec(html)) !== null) {
    const attrs = match[1] || '';
    const source = match[2] || '';
    if (/\bsrc\s*=/i.test(attrs) || !source.trim()) continue;
    inlineIndex++;
    checked++;
    try {
      new vm.Script(source, { filename: relative + ' inline script #' + inlineIndex });
      console.log('PASS inline JS syntax: ' + relative + ' #' + inlineIndex);
    } catch (error) {
      failures++;
      console.error('FAIL inline JS syntax: ' + relative + ' #' + inlineIndex + ': ' + error.message);
    }
  }
}

if (failures) {
  console.error('Inline JavaScript syntax gate failed: ' + failures + ' error(s), ' + checked + ' scripts checked.');
  process.exitCode = 1;
} else {
  console.log('PASS inline JavaScript syntax gate: ' + checked + ' script blocks compiled.');
}
