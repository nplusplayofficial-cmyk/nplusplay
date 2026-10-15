#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');

const root = path.resolve(__dirname, '..');
let errors = 0;
let warnings = 0;
const htmls = fs.readdirSync(root).filter(f => f.toLowerCase().endsWith('.html'));

function fail(message) { errors++; console.error('FAIL ' + message); }
function warn(message) { warnings++; console.warn('WARN ' + message); }
function exists(relative) { return fs.existsSync(path.resolve(root, relative)); }
function cleanLocalRef(raw) {
  let ref = String(raw || '').trim();
  if (!ref || ref.startsWith('#') || /^(?:https?:|data:|javascript:|mailto:|tel:|\/\/|blob:)/i.test(ref)) return null;
  ref = ref.split(/[?#]/, 1)[0];
  if (!ref) return null;
  try { ref = decodeURIComponent(ref); } catch {}
  return ref.replace(/^\.?\//, '');
}

for (const file of htmls) {
  const full = path.join(root, file);
  const html = fs.readFileSync(full, 'utf8');
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)];
  let scriptIndex = 0;
  for (const match of scripts) {
    const body = match[1];
    if (!body.trim()) { scriptIndex++; continue; }
    const temp = path.join(os.tmpdir(), 'nplus-' + process.pid + '-' + scriptIndex + '.js');
    try {
      fs.writeFileSync(temp, body);
      const result = cp.spawnSync(process.execPath, ['--check', temp], { encoding: 'utf8' });
      if (result.status !== 0) fail('JS syntax ' + file + ' script ' + scriptIndex + ': ' + (result.stderr || result.stdout || '').trim());
    } finally {
      try { fs.unlinkSync(temp); } catch {}
    }
    scriptIndex++;
  }

  const markup = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '')
                     .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, '');
  const ids = [...markup.matchAll(/\bid=["']([^"']+)["']/gi)].map(m => m[1]);
  const duplicates = [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))];
  if (duplicates.length) warn('duplicate IDs in ' + file + ': ' + duplicates.join(', '));

  const refs = [...markup.matchAll(/\b(?:href|src)\s*=\s*["']([^"']+)["']/gi)];
  for (const m of refs) {
    const ref = cleanLocalRef(m[1]);
    if (ref && !exists(ref)) fail('missing local reference ' + file + ' -> ' + m[1]);
  }

  // Catch static script-driven navigation such as forgotten links in onclick handlers.
  const navs = [...html.matchAll(/(?:window\.)?location\.(?:href|replace)\s*(?:=|\()\s*['"]([^'"]+)['"]/gi)];
  for (const m of navs) {
    const ref = cleanLocalRef(m[1]);
    if (ref && !exists(ref)) fail('missing navigation target ' + file + ' -> ' + m[1]);
  }
}

for (const required of [
  'manifest.webmanifest', 'sw.js', 'offline.html', 'assets/nplus-icon.svg',
  'core/nplus-config.js', 'core/nplus-auth.js', 'core/nplus-wallet-bridge.js',
  'admin-users.html', 'deposit-demo.html',
  'sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql', 'sql/NPLUS_PLAY_PROFILE_DEPOSIT_GUARDS.sql'
]) {
  if (!exists(required)) fail('required file missing: ' + required);
}

try {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.webmanifest'), 'utf8'));
  for (const icon of manifest.icons || []) {
    const ref = cleanLocalRef(icon.src);
    if (ref && !exists(ref)) fail('manifest icon missing: ' + icon.src);
  }
} catch (e) { fail('manifest JSON invalid: ' + e.message); }

try {
  const sw = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
  const match = sw.match(/const\s+SHELL\s*=\s*\[([\s\S]*?)\]/);
  if (!match) fail('service worker SHELL array not found');
  else {
    for (const item of match[1].matchAll(/["']([^"']+)["']/g)) {
      const ref = cleanLocalRef(item[1]);
      if (ref && !exists(ref)) fail('service worker shell asset missing: ' + item[1]);
    }
  }
  const r = cp.spawnSync(process.execPath, ['--check', path.join(root, 'sw.js')], { encoding: 'utf8' });
  if (r.status !== 0) fail('service worker syntax: ' + (r.stderr || r.stdout || '').trim());
} catch (e) { fail('service worker check failed: ' + e.message); }

console.log('HTML pages checked: ' + htmls.length);
console.log('Warnings: ' + warnings);
console.log('Errors: ' + errors);
console.log('Note: this static check does not test live Supabase auth, RLS, RPCs, or real game settlement.');
process.exit(errors ? 1 : 0);
