#!/usr/bin/env node
'use strict';
// Credential-free static release guards. These checks are not a substitute for runtime/staging review.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const failures = [];
const warnings = [];
const check = (ok, message) => { if (!ok) failures.push(message); };

const admin = read('admin-games.html');
const aviator = read('sql/NPLUS_PLAY_AVIATOR_RPC.sql');
const home = read('index.html');
const statusSql = read('sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql');
const phoneSql = read('sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql');
const walletSql = read('sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql');

check(admin.includes('nplus_set_game_status'), 'Admin game status must call server-side RPC.');
check(admin.includes('HARD_PAUSED_GAMES'), 'Unsupported games must remain hard-paused in Admin UI.');
check(statusSql.includes("('K3','5D','TRX')"), 'K3/5D/TRX rollout pause contract missing.');
check(statusSql.includes('Admin access required.'), 'Server-side Admin authorization contract missing.');
check(aviator.includes('pg_advisory_xact_lock'), 'Aviator transaction-level round lock contract missing.');
check(/for update/i.test(aviator), 'Aviator row-locking contract missing.');
check(aviator.includes('auth.uid()'), 'Aviator user-scoped authentication contract missing.');
check(home.includes('VIRTUAL DEMO'), 'Homepage must disclose virtual demo mode.');
check(home.includes('id="recent-demo-activity"') && home.includes('No verified recent activity yet'), 'Homepage must show an honest empty state until a server-backed activity feed is verified.');
check(admin.includes('Local browser storage is a display cache, not a source of authority.'), 'Admin page must disclose localStorage is not authoritative.');
check(/nplus_phone_is_registered/i.test(phoneSql) && /revoke/i.test(phoneSql), 'Phone enumeration revoke candidate missing.');
check(/nplus_wallet_change/i.test(walletSql) && /revoke/i.test(walletSql), 'Legacy generic wallet mutation revoke candidate missing.');

if (admin.includes('nplus_admin_demo_controls')) warnings.push('Admin localStorage demo controls remain: trace all consumers; privileged/outcome-affecting state must be server-authoritative.');
if (!/nplus_recent_demo_activity/.test(home)) warnings.push('No verified homepage recent-activity RPC contract; do not claim a genuine activity feed.');
if (!/cron\.schedule|pg_cron/i.test(aviator)) warnings.push('Aviator SQL does not declare a persistent scheduler; browser-independent round progression remains unverified.');
for (const warning of warnings) console.warn('REVIEW: ' + warning);
for (const failure of failures) console.error('FAIL: ' + failure);
if (failures.length) process.exit(1);
console.log('PASS: 12 static source-contract checks. ' + warnings.length + ' release blockers remain for human/runtime verification.');
