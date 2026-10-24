#!/usr/bin/env node
'use strict';

// Static safety gate: K3, 5D and TRX WINGO remain presentation-only until
// their payout rules and server-authoritative settlement RPCs are approved.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
let failures = 0;
function check(ok, message) {
  if (ok) console.log('PASS ' + message);
  else { failures++; console.error('FAIL ' + message); }
}
function read(relative) {
  const file = path.join(root, relative);
  if (!fs.existsSync(file)) {
    check(false, 'required file exists: ' + relative);
    return '';
  }
  return fs.readFileSync(file, 'utf8');
}

const pausedPages = [
  {
    file: 'k3.html',
    notice: /K3 BETTING PAUSED[\s\S]{0,120}payout rules are approved/i,
    pauseAction: /K3 betting is temporarily paused while server payout rules are reviewed/i
  },
  {
    file: '5d.html',
    notice: /5D BETTING PAUSED[\s\S]{0,120}PAYOUT RULES UNDER REVIEW/i,
    pauseAction: /5D betting is temporarily paused while server payout rules are reviewed/i
  },
  {
    file: 'trx-wingo.html',
    notice: /TRX WINGO BETTING PAUSED[\s\S]{0,120}PAYOUT RULES UNDER REVIEW/i,
    pauseAction: /TRX WINGO betting is temporarily paused while server payout rules are reviewed/i
  }
];

for (const item of pausedPages) {
  const html = read(item.file);
  check(item.notice.test(html), item.file + ' visibly says betting is paused');
  check(item.pauseAction.test(html), item.file + ' blocks the bet action with a pause message');
  check(!/\.rpc\s*\(|NPlusWalletBridge|nplus_wallet_change|GAME_BET|GAME_WIN/.test(html),
    item.file + ' has no client-side wallet/settlement write path');
}

const admin = read('admin-games.html');
check(/HARD_PAUSED_GAMES\s*=\s*new Set\(\["K3",\s*"5D",\s*"TRX"\]\)/.test(admin),
  'N+ ADMIN hard-pauses all three games');
check(/nplus_set_game_status/.test(admin), 'N+ ADMIN uses the server game-status RPC');

const migration = read('sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql');
check(/where game_key in \('K3','5D','TRX'\)/.test(migration),
  'game-status migration disables all three games');
check(/v_key in \('K3','5D','TRX'\) and p_enabled/.test(migration),
  'server RPC refuses to re-enable any unapproved game');

const sqlTests = read('qa/test-admin-game-status.sql');
for (const key of ['K3', '5D', 'TRX']) {
  check(sqlTests.includes("'" + key + "'"), 'disposable SQL test references ' + key);
}

const settlementFiles = [
  'sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql',
  'sql/NPLUS_PLAY_MOTORACE_RPC.sql',
  'sql/NPLUS_PLAY_AVIATOR_RPC.sql'
];
const available = settlementFiles.map(f => fs.existsSync(path.join(root, f)) ? f : null).filter(Boolean);
for (const key of ['K3', '5D', 'TRX']) {
  const rpcPattern = new RegExp('nplus_' + key.toLowerCase() + '.*(place_bet|settle_round|payout)', 'i');
  const hasServerSettlement = available.some(f => rpcPattern.test(fs.readFileSync(path.join(root, f), 'utf8')));
  check(!hasServerSettlement, key + ' has no approved server-settlement RPC in the reviewed settlement SQL files');
}

if (failures) {
  console.error('\nGame-rules approval gate failed: ' + failures + ' check(s).');
  process.exitCode = 1;
} else {
  console.log('\nGame-rules approval gate passed. This verifies pause guards only; it does NOT approve payout rules.');
}
