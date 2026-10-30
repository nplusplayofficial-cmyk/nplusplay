#!/usr/bin/env node
'use strict';

// Static safety gate for the current server-authoritative K3/5D/TRX demo implementation.
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

const pages = [
  { file: 'k3.html', key: 'K3', rule: /Sum 3–18|Exact total|SINGLE NUMBER|ALL DIFFERENT/i },
  { file: '5d.html', key: '5D', rule: /TOTAL SUM|SUM.*BIG.*SMALL/i },
  { file: 'trx-wingo.html', key: 'TRX', rule: /SERVER DEMO|server settlement/i }
];

for (const item of pages) {
  const html = read(item.file);
  check(html.includes('nplus_demo_lottery_snapshot'), item.file + ' refreshes the authoritative round/status from server RPC');
  check(html.includes('nplus_demo_lottery_place_bet'), item.file + ' submits bet only through server RPC');
  check(/betting_enabled/.test(html) && /SERVER/.test(html), item.file + ' fails closed when server status/results are unavailable');
  check(!/NPlusWallet\.changeBalance\s*\(|NPlusWalletBridge|nplus_wallet_change|type\s*:\s*['"]GAME_WIN['"]/.test(html),
    item.file + ' has no direct client-side wallet write path');
  check(item.rule.test(html), item.file + ' labels/blocks unsupported demo selection rules');
}

const migration = read('supabase/migrations/20261028134905_server_authoritative_k3_5d_trx_demo.sql');
const expandedMigration = read('supabase/migrations/20261030101000_expand_k3_5d_demo_selection_rules.sql');
for (const contract of [
  'create table if not exists public.nplus_demo_lottery_rounds',
  'create table if not exists public.nplus_demo_lottery_bets',
  'nplus_demo_lottery_make_outcome',
  'nplus_demo_lottery_payout_multiplier',
  'nplus_demo_lottery_settle_due',
  'nplus_demo_lottery_snapshot',
  'nplus_demo_lottery_place_bet',
  'authentication required.',
  'request id was already used for a different demo bet.',
  'betting is closed for this round.',
  'server-authoritative demo settlement is not installed.',
  'enable row level security',
  'revoke all on table public.nplus_demo_lottery_bets from public, anon, authenticated'
]) {
  check(migration.toLowerCase().includes(contract.toLowerCase()), 'game migration contains guard: ' + contract);
}
check(/p_stake::text\s+IN\s*\('NaN','Infinity','-Infinity'\)/i.test(migration),
  'server rejects non-finite lottery stakes');
check(/v_key='K3'[\s\S]*?return 2/i.test(migration),
  'K3 base Big/Small and Odd/Even remain server-defined at 2x gross');
for (const contract of [
  "v_type='sum'", "v_type='single'", "v_type='double'", "v_type='triple'", "v_type='different'",
  "v_value ~ '^(3|[4-9]|1[0-8])$'", "v_ways := ARRAY[1,3,6,10,15,21,25,27,27,25,21,15,10,6,3,1]"
]) check(expandedMigration.includes(contract), 'K3 expanded migration includes exact-odds rule: ' + contract);
check(expandedMigration.includes("SUM:(BIG|SMALL)") && expandedMigration.includes("SUM:(ODD|EVEN)"),
  '5D aggregate SUM Big/Small/Odd/Even are server payout rules');
check(expandedMigration.includes("v_key='K3'") && expandedMigration.includes("v_key='5D'"),
  'expansion migration replaces payout and place-bet RPCs for both games');
check(/v_key='5D'[\s\S]*?return 10/i.test(migration) && /v_key='5D'[\s\S]*?return 2/i.test(migration),
  '5D per-position digit and size/parity multipliers are server-defined');
check(/v_key='TRX'[\s\S]*?return 2\.5/i.test(migration) && /return 5/i.test(migration),
  'TRX digit/color/size multipliers are server-defined');

const admin = read('admin-games.html');
check(!/HARD_PAUSED_GAMES\s*=\s*new Set\(\[["']K3["'][\s,]*["']5D["'][\s,]*["']TRX["']\]\)/.test(admin),
  'N+ ADMIN does not permanently hard-lock K3/5D/TRX after server settlement is installed');
check(/from\(["']game_settings["']\)/.test(admin) && /nplus_set_game_status/.test(admin) &&
      /toggleServerGameStatus/.test(admin) && /loadServerGameSettings/.test(admin),
  'N+ ADMIN uses persistent server game settings and role-guarded status RPC');

const adminSql = read('sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql');
check(adminSql.includes('Server-authoritative demo settlement is not installed.') &&
      adminSql.includes('nplus_demo_lottery_snapshot(text,integer)') &&
      adminSql.includes('nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid)'),
  'baseline game-status SQL refuses enablement unless server settlement functions exist');
const adminSqlTest = read('qa/test-admin-game-status.sql');
check(adminSqlTest.includes('Server-authoritative demo settlement is not installed') ||
      adminSqlTest.includes('Server-authoritative demo settlement is not installed.'),
  'disposable admin game-status test exercises fail-closed backend prerequisite');

const e2e = read('qa/test-demo-lottery-settlement.sql');
for (const expectation of [
  'disabled K3 accepted a bet',
  'non-admin enabled K3',
  'K3 base bet or expanded exact-SUM 8x settlement failed.',
  '5D digit or aggregate SUM 2x gross settlement failed.',
  'TRX Violet result did not settle to 5x gross payout',
  'ROLLBACK'
]) check(e2e.includes(expectation), 'disposable settlement regression covers: ' + expectation);

if (failures) {
  console.error('\nServer settlement gate failed: ' + failures + ' check(s).');
  process.exitCode = 1;
} else {
  console.log('\nServer settlement static gate passed; runtime confirmation is provided by the isolated PostgreSQL suite, not this source scan alone.');
}
