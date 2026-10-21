#!/usr/bin/env node
'use strict';
// Credential-free static release guards. These checks are not a substitute for runtime/staging review.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const failures = [];
const warnings = [];
let checks = 0;
const check = (ok, message) => { checks++; if (!ok) failures.push(message); };

const admin = read('admin-games.html');
const aviator = read('sql/NPLUS_PLAY_AVIATOR_RPC.sql');
const home = read('index.html');
const recentActivityJs = read('core/recent-demo-activity.js');
const recentActivitySql = read('sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql');
const statusSql = read('sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql');
const phoneSql = read('sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql');
const walletSql = read('sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql');
const aviatorPage = read('aviator.html');
const schedulerDoc = read('docs/NPLUS_AVIATOR_SCHEDULER_RECOVERY_DESIGN_2026-10-19.md');
const memberSql = read('sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql');
const memberSmoke = read('tests/nplus-member-centre-smoke.sql');
const memberQa = read('tests/nplus-member-centre-qa.mjs');
const memberHtml = read('referral.html');
const adminVipHtml = read('admin-vip.html');

check(admin.includes('nplus_set_game_status'), 'Admin game status must call server-side RPC.');
check(admin.includes('HARD_PAUSED_GAMES'), 'Unsupported games must remain hard-paused in Admin UI.');
check(statusSql.includes("('K3','5D','TRX')"), 'K3/5D/TRX rollout pause contract missing.');
check(statusSql.includes('Admin access required.'), 'Server-side Admin authorization contract missing.');
check(aviator.includes('pg_advisory_xact_lock'), 'Aviator transaction-level round lock contract missing.');
check(/for update/i.test(aviator), 'Aviator row-locking contract missing.');
check(aviator.includes('auth.uid()'), 'Aviator user-scoped authentication contract missing.');
check(home.includes('VIRTUAL DEMO'), 'Homepage must disclose virtual demo mode.');
check(home.includes('id="recent-demo-activity"') && home.includes('No verified recent activity yet'), 'Homepage must show an honest empty state until a server-backed activity feed is verified.');
check(home.includes('id="recentDemoActivityRows"') && home.includes('core/recent-demo-activity.js'), 'Homepage must mount the recent demo activity widget.');
check(/client\.rpc\(\s*["']nplus_recent_demo_activity["']/.test(recentActivityJs), 'Homepage activity widget must call the recent activity RPC.');
check(
  /create or replace function public\.nplus_recent_demo_activity\s*\(/i.test(recentActivitySql) &&
  /returns table\s*\(\s*game_key text,\s*activity_count bigint\s*\)/i.test(recentActivitySql) &&
  recentActivitySql.includes('public.nplus_wingo_demo_bets') &&
  recentActivitySql.includes('public.nplus_moto_demo_bets') &&
  recentActivitySql.includes('public.nplus_aviator_demo_bets') &&
  /security definer/i.test(recentActivitySql) &&
  /revoke all on function public\.nplus_recent_demo_activity\(integer\)\s+from public, anon, authenticated/i.test(recentActivitySql) &&
  /grant execute on function public\.nplus_recent_demo_activity\(integer\)\s+to anon, authenticated/i.test(recentActivitySql),
  'Recent-activity SQL must aggregate the three bet tables and restrict function grants.'
);
check(!admin.includes('nplus_admin_demo_controls') && !/localStorage/.test(admin) && admin.includes('Admin demo display state is temporary and never controls game outcomes.'), 'Admin demo state must remain in-memory display-only; never store privileged/outcome-affecting controls in browser storage.');
check(/nplus_phone_is_registered/i.test(phoneSql) && /revoke/i.test(phoneSql), 'Phone enumeration revoke candidate missing.');
check(walletSql.includes('create or replace function public.nplus_wallet_change(') && walletSql.includes('p_delta > 0') && walletSql.toLowerCase().includes('positive virtual credits must be awarded') && walletSql.toLowerCase().includes('do not run before'), 'Wallet mutation candidate must reject direct positive credits and remain gated post-rollout.');
check(/rpc\(['\"]nplus_aviator_demo_place_bet['\"]/.test(aviatorPage) && /rpc\(['\"]nplus_aviator_demo_cashout['\"]/.test(aviatorPage), 'Aviator page must submit bets and cash-outs through server RPCs.');
check(!/p_crash_point\s*:/.test(aviatorPage), 'Aviator client must not submit a crash point override.');
check(/No demo bets yet/.test(aviatorPage) && /No real-money payments, withdrawals or real-money winnings/.test(aviatorPage), 'Aviator page must retain honest demo-only disclosures and empty state.');
check(/revoke all on function public\.nplus_aviator_demo_make_crash_point\(\) from public,anon,authenticated/i.test(aviator), 'Aviator crash-point helper must not be callable by client roles.');
check(/grant execute on function public\.nplus_aviator_demo_place_bet\(uuid,integer,numeric,uuid,numeric\) to authenticated/i.test(aviator), 'Aviator bet RPC must explicitly grant authenticated execution.');
check(/grant execute on function public\.nplus_aviator_demo_cashout\(uuid\) to authenticated/i.test(aviator), 'Aviator cash-out RPC must explicitly grant authenticated execution.');
check(/'crash_point',case when v_phase='CRASH' then v_round\.crash_point else null end/i.test(aviator), 'Aviator RPC must not disclose the crash point before crash phase.');
check(schedulerDoc.includes('BLOCKED — design only') && schedulerDoc.includes('Do not schedule this function directly.'), 'Aviator scheduler must remain explicitly blocked until a safe worker is verified.');
check(schedulerDoc.includes('service-role credentials') && schedulerDoc.includes('disposable database'), 'Aviator scheduler design must document secret isolation and disposable-database testing.');
check(/CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referrals_referred_uidx/i.test(memberSql), 'Referral system must enforce one inviter per referred account.');
check(/CREATE UNIQUE INDEX IF NOT EXISTS nplus_demo_referrals_request_uidx/i.test(memberSql), 'Referral attribution must prevent reuse of one qualifying request.');
check(memberSql.includes('CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_tier_rules') && memberSql.includes('(100000, 500.00, 7555555.00)'), 'Referral tiers must match the Daman screenshot tier table.');
check(memberSql.includes('DROP TRIGGER IF EXISTS nplus_demo_referral_approved_request ON public.deposit_requests') && !memberSql.includes('CREATE TRIGGER nplus_demo_referral_approved_request'), 'Generic deposit approvals must not trigger demo referral rewards.');
check(/UNIQUE \(user_id, code\)/i.test(memberSql) && /ON CONFLICT \(user_id, code\) DO NOTHING/i.test(memberSql), 'Gift claims must be idempotent per user/code.');
check(/PRIMARY KEY \(user_id, claim_date\)/i.test(memberSql) && /ON CONFLICT \(user_id,claim_date\) DO NOTHING/i.test(memberSql), 'Attendance must be one claim per account/day.');
check(memberSmoke.includes('generic deposit request incorrectly triggered a referral reward') && memberSmoke.includes('Direct access to new feature tables'), 'Disposable DB smoke tests must block generic deposit-linked rewards and guard private table access.');
check(memberQa.includes('Legacy 200-point qualification rule must be removed.') && memberQa.includes('Admin RPCs must check the server-side admin role.'), 'Member Centre static QA must reject the invented 200/20 rule and check server-side Admin guards.');
check(memberSql.includes('CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral(') && memberSql.includes('p_verified_virtual_amount < 500.00'), 'Admin qualification must enforce the screenshot 500-point virtual threshold.');
check(memberSql.includes('CREATE OR REPLACE FUNCTION public.nplus_demo_claim_referral_bonus(p_invitee_count integer)') && memberSql.includes('PRIMARY KEY (user_id, invitee_count)'), 'Invitation tier claim must be server-side and idempotent.');
check(memberSql.includes('CREATE TABLE IF NOT EXISTS public.nplus_demo_referral_qualifications') && memberSql.includes('UNIQUE (referrer_user_id, referred_user_id)'), 'Verified invite qualification must be unique per inviter/invitee.');
check(memberHtml.includes('nplus_demo_referral_bonus_dashboard') && memberHtml.includes('nplus_demo_claim_referral_bonus') && memberHtml.includes('id="tierRows"'), 'Member Centre must display server-backed screenshot tier progress and claim action.');
check(memberHtml.includes('500 verified virtual demo points') && memberHtml.includes('virtual demo points only'), 'Member Centre must state the screenshot qualification threshold and demo-only unit.');
check(adminVipHtml.includes('id="qualifyForm"') && adminVipHtml.includes('nplus_demo_admin_qualify_referral') && adminVipHtml.includes("v.referred_user_id||'UUID unavailable'"), 'N+ ADMIN must verify invitations using the protected RPC and actual profile UUID.');
check(memberSmoke.includes('tier claims should award exactly 210 demo points once each') && memberSmoke.includes('repeat tier 1 claim must be rejected'), 'Disposable DB smoke must verify tier award values and replay protection.');
check(memberSmoke.includes('invitation claim must be rejected after the event ends') && memberSmoke.includes('actual invited profile UUID for qualification'), 'Disposable DB smoke must cover event expiry and Admin invitation UUID lookup.');


if (admin.includes('nplus_admin_demo_controls')) warnings.push('Admin localStorage demo controls remain: trace all consumers; privileged/outcome-affecting state must be server-authoritative.');
const activityMigrationPath = path.join(root, 'supabase/migrations/20261021182728_nplus_recent_demo_activity.sql');
const activityMigration = fs.existsSync(activityMigrationPath)
  ? fs.readFileSync(activityMigrationPath, 'utf8')
  : '';

if (
  !home.includes('core/recent-demo-activity.js') ||
  !/client\.rpc\(\s*["']nplus_recent_demo_activity["']/.test(recentActivityJs) ||
  !/create or replace function public\.nplus_recent_demo_activity\s*\(/i.test(recentActivitySql) ||
  !/create or replace function public\.nplus_recent_demo_activity\s*\(/i.test(activityMigration) ||
  !/security definer/i.test(activityMigration) ||
  !/grant execute on function public\.nplus_recent_demo_activity\(integer\)\s+to anon, authenticated/i.test(activityMigration)
) {
  warnings.push('Recent-activity source or versioned migration is incomplete; do not claim a genuine activity feed.');
} else {
  warnings.push('Recent-activity migration is present; verify target Supabase deployment and live browser rendering before release.');
}
const schedulerMigrationPath = path.join(root, 'supabase/migrations/20261021182724_nplus_aviator_persistent_scheduler.sql');
const schedulerMigration = fs.existsSync(schedulerMigrationPath)
  ? fs.readFileSync(schedulerMigrationPath, 'utf8')
  : '';

if (
  !/create extension if not exists pg_cron/i.test(schedulerMigration) ||
  !/cron\.schedule\s*\(/i.test(schedulerMigration) ||
  !/nplus-aviator-worker/.test(schedulerMigration) ||
  !/nplus_aviator_demo_worker_tick/.test(schedulerMigration)
) {
  warnings.push('Aviator persistent scheduler migration is missing or incomplete; do not release.');
} else {
  warnings.push('Aviator scheduler migration is present; verify target deployment and monitor cron runs and worker heartbeat before release.');
}
for (const warning of warnings) console.warn('REVIEW: ' + warning);
for (const failure of failures) console.error('FAIL: ' + failure);
if (failures.length) process.exit(1);
console.log('PASS: ' + checks + ' static source-contract checks. ' + warnings.length + ' release blockers remain for human/runtime verification.');
