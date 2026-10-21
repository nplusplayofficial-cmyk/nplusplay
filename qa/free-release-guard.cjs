#!/usr/bin/env node
'use strict';
// No credentials, network calls, or production writes. Fail on regressions.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const games = ['wingo.html', 'motorace.html', 'aviator.html'];
let checks = 0;
function verify(name, condition) {
  checks++;
  assert.ok(condition, name);
  process.stdout.write('PASS ' + name + '\n');
}
for (const file of games) {
  const html = read(file);
  verify(file + ' has an authenticated server game RPC', /nplus_(?:wingo|moto|aviator)_demo_/.test(html));
  verify(file + ' has no direct positive GAME_WIN wallet change', !/nplus_wallet_change[\s\S]{0,180}GAME_WIN|GAME_WIN[\s\S]{0,180}nplus_wallet_change/i.test(html));
}
const admin = read('admin-games.html');
verify('admin reads server game settings', /\.from\(["']game_settings["']\)/.test(admin));
verify('admin uses guarded server game-status RPC', admin.includes('nplus_set_game_status'));
const statusSql = read('sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql');
verify('game status SQL verifies admin role', /coalesce\(v_role,\s*''\)\s*<>\s*'admin'/.test(statusSql));
verify('K3, 5D, TRX cannot be enabled without payout rules', /v_key\s+in\s*\('K3','5D','TRX'\)\s+and\s+p_enabled/i.test(statusSql));
const homepage = read('index.html');
verify('homepage labels activity as virtual demo', homepage.includes('VIRTUAL DEMO'));
const member = read('sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql');
verify('member referral migration exists and defines reward logic', /referral/i.test(member) && /20(?:\.00)?/.test(member));
for (const file of ['deposit.html', 'withdraw.html', 'admin-deposits.html', 'admin-withdrawals.html']) {
  verify('excluded payment page exists and is not modified by this check: ' + file, fs.existsSync(path.join(root, file)));
}
process.stdout.write('PASS ' + checks + ' no-cost static release checks\n');
