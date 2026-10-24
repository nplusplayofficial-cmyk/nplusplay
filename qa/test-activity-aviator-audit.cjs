#!/usr/bin/env node
'use strict';

// Source-level audit for homepage activity privacy and Aviator recovery guarantees.
// Scheduler absence is reported as a release blocker, not falsely treated as a pass.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
let failures = 0;
function check(ok, message) {
  if (ok) console.log('PASS ' + message);
  else { failures++; console.error('FAIL ' + message); }
}
function read(file) {
  const full = path.join(root, file);
  if (!fs.existsSync(full)) {
    check(false, 'required file exists: ' + file);
    return '';
  }
  return fs.readFileSync(full, 'utf8');
}

const home = read('index.html');
const feed = read('core/recent-demo-activity.js');
const feedSql = read('sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql');
check(home.includes('id="recentDemoActivityRows"'), 'homepage has the recent demo activity container');
check(home.includes('core/recent-demo-activity.js'), 'homepage loads the activity feed script');
check(feed.includes('nplus_recent_demo_activity'), 'feed calls the server aggregate RPC');
check(feed.includes('document.createTextNode') && feed.includes('textContent'),
  'feed renders server data as text rather than injecting HTML');
check(/const games\s*=\s*\{[\s\S]*WINGO[\s\S]*MOTORACE[\s\S]*AVIATOR/.test(feed),
  'feed allowlists only supported game labels');
check(/p_window_minutes:\s*60/.test(feed), 'feed requests the bounded 60-minute window');
check(!/email|display_name|phone|user_id|stake|payout|selection/i.test(feed),
  'feed client does not request or render personal identifiers or per-bet amounts');
check(feedSql.toLowerCase().replace(/\\s+/g, ' ').includes('returns table ( game_key text, activity_count bigint )'),
  'server feed contract exposes only game key and aggregate count');
check(/security definer/i.test(feedSql) && /set search_path\s*=\s*pg_catalog,\s*public/i.test(feedSql),
  'server feed uses a fixed search_path');
check(/least\(\s*greatest\(coalesce\(p_window_minutes, 60\), 5\),\s*1440\s*\)/i.test(feedSql),
  'server feed clamps the requested time window to 5–1440 minutes');
check(feedSql.toLowerCase().replace(/\\s+/g, ' ').includes('grant execute on function public.nplus_recent_demo_activity(integer) to anon, authenticated'),
  'only the aggregate feed RPC is exposed for anonymous/authenticated reads');

const activity = read('activity.html');
check(activity.includes('window.NPlusAuth.requireAuth()'), 'private activity page requires authentication');
check(activity.includes('window.NPlusWallet.transactions(500)'), 'wallet history uses the wallet transaction bridge');
check(activity.includes('nplus_wingo_demo_my_bets') &&
      activity.includes('nplus_moto_demo_my_bets') &&
      activity.includes('nplus_aviator_demo_my_bets'),
  'activity page requests server-recorded WINGO, MotoRace and Aviator history');
check(activity.includes('esc('), 'activity page escapes displayed server values');

const aviatorSql = read('sql/NPLUS_PLAY_AVIATOR_RPC.sql');
const aviatorTest = read('qa/test-aviator-settlement.sql');
check(/pg_advisory_xact_lock\(74190311\)/.test(aviatorSql),
  'Aviator round creation uses a transaction advisory lock');
check(/unique\(user_id,request_id\)/i.test(read('sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql')),
  'Aviator bet requests have a database idempotency constraint');
check(/status='cashed_out'[\s\S]*duplicate_cashout/i.test(aviatorSql),
  'Aviator cash-out handles already-settled bets');
check(/late server auto cash-out/i.test(aviatorSql) &&
      /status='lost'/.test(aviatorSql),
  'Aviator server RPC includes delayed-polling auto-cashout and loss finalization paths');
check(/late-finalized Aviator auto cash-out/i.test(aviatorTest) &&
      /repeated cash-out credited twice/i.test(aviatorTest),
  'disposable SQL tests cover delayed recovery and duplicate cash-out');
check(/setInterval\(loop,50\)/.test(read('aviator.html')) &&
      /syncAviatorRound\(false\)/.test(read('aviator.html')),
  'Aviator client polls server state while a game page is open');

const schedulerSql = read(
  'docs/recovered-live-migration-sql-2026-10-23/20261021182724_nplus_aviator_persistent_scheduler.sql'
);
const schedulerRuntime = read('docs/AVIATOR-SCHEDULER-LIVE-VERIFICATION-2026-10-24.md');
check(/create extension if not exists pg_cron/i.test(schedulerSql) &&
      /cron\.schedule/i.test(schedulerSql) &&
      /nplus-aviator-worker/.test(schedulerSql) &&
      /1 seconds/.test(schedulerSql) &&
      /public\.nplus_aviator_demo_worker_tick\(\)/.test(schedulerSql),
  'recovered scheduler source documents the protected 1-second worker job');
check(/production Aviator scheduler is present and actively running/i.test(schedulerRuntime) &&
      /consecutive_failures = 0/i.test(schedulerRuntime) &&
      /not a canonical migration/i.test(schedulerRuntime),
  'runtime scheduler verification is documented with health evidence and source-chain caveats');

if (failures) {
  console.error('Activity/Aviator audit failed: ' + failures + ' check(s).');
  process.exitCode = 1;
} else {
  console.log('Activity/Aviator source audit passed. Production scheduler evidence is recorded separately; keep source/replay and hosted UI release gates open.');
}
