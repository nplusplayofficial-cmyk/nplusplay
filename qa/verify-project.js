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

// Every N+ PLAY and N+ ADMIN HTML page must include the shared in-app back control.
try {
  const backNavPath = path.join(root, 'core/nplus-back-nav.js');
  if (!fs.existsSync(backNavPath)) fail('Shared in-app back navigation script is missing');
  const backNav = fs.readFileSync(backNavPath, 'utf8');
  for (const required of ['nplus-global-back','nplus.inAppBackStack.v1','referrerPath()','fallbackPath()','window.location.replace(target)']) {
    if (!backNav.includes(required)) fail('Shared back-navigation contract missing: ' + required);
  }
  for (const file of htmls) {
    const html = fs.readFileSync(path.join(root, file), 'utf8');
    if (!/<script\s+defer\s+src=["']\.\/core\/nplus-back-nav\.js["']><\/script>/i.test(html)) {
      fail('Shared back arrow is not included on HTML page: ' + file);
    }
  }
  const worker = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
  if (!worker.includes('nplus-play-shell-v6') || !worker.includes('"./core/nplus-back-nav.js"')) {
    fail('Service worker must bump its shell cache and precache the shared back-navigation script');
  }
} catch (e) { fail('Shared in-app back navigation guard failed: ' + e.message); }

// Admin login and wallet-adjustment source must remain aligned with the server security contract.
try {
  const adminLogin = fs.readFileSync(path.join(root, 'admin-login.html'), 'utf8');
  if (!adminLogin.includes('core/nplus-config.js?v=20261023-admin-auth-fix') ||
      !adminLogin.includes('supabase.auth.signInWithPassword') ||
      !adminLogin.includes('Password accepted, but the admin permission check failed')) {
    fail('Admin login must load the current config and distinguish profile-check failures from a non-admin account');
  }

  const adminUsers = fs.readFileSync(path.join(root, 'admin-users.html'), 'utf8');
  if (!adminUsers.includes('nplus_admin_adjust_demo_wallet') ||
      !adminUsers.includes('p_target_user:id') ||
      !adminUsers.includes('p_delta:delta') ||
      !adminUsers.includes('p_note:note') ||
      !adminUsers.includes('button.disabled=true')) {
    fail('Admin wallet-adjustment UI must call the audited RPC with matching arguments and prevent repeat clicks');
  }

  const profileRls = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_PROFILES_RLS_ADMIN_LOGIN_FIX_2026-10-23.sql'), 'utf8');
  if (!profileRls.includes('DROP POLICY IF EXISTS "Admins can view all profiles"') ||
      !profileRls.includes('DROP POLICY IF EXISTS "Public profiles are viewable by everyone"')) {
    fail('Profile RLS migration must remove recursive/public profile SELECT policies');
  }

  const walletGuard = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_ADMIN_DEMO_WALLET_ADJUSTMENT_GUARD_2026-10-23.sql'), 'utf8');
  if (!walletGuard.includes("coalesce(v_role, '') <> 'admin'") ||
      !walletGuard.includes('REVOKE ALL ON FUNCTION public.nplus_admin_adjust_demo_wallet(uuid, numeric, text)') ||
      !walletGuard.includes('TO authenticated, service_role')) {
    fail('Admin wallet adjustment migration must enforce role checks and least-privilege grants');
  }
} catch (error) {
  fail('Admin security guard checks could not be read: ' + (error.message || error));
}

// Demo request pages must use guarded RPCs and remain virtual-credit-only.
try {
  const depositPage = fs.readFileSync(path.join(root, 'deposit-demo.html'), 'utf8');
  if (!depositPage.includes('nplus_create_demo_deposit_request') ||
      /\.from\s*\(\s*['"]deposit_requests['"]\s*\)\s*\.insert\s*\(/i.test(depositPage)) {
    fail('Deposit request page must use the server-side idempotent RPC, not direct inserts');
  }
  const withdrawalPage = fs.readFileSync(path.join(root, 'withdraw.html'), 'utf8');
  if (!withdrawalPage.includes('nplus_create_demo_withdrawal_request') ||
      !/no cash payout/i.test(withdrawalPage) ||
      !withdrawalPage.includes('withdrawal-history.html')) {
    fail('Withdrawal page must use the protected demo RPC, show history link and state no cash payout');
  }
  const depositHistory = fs.readFileSync(path.join(root, 'deposit-history.html'), 'utf8');
  const withdrawalHistory = fs.readFileSync(path.join(root, 'withdrawal-history.html'), 'utf8');
  if (!depositHistory.includes('deposit_requests') || !withdrawalHistory.includes('withdrawal_requests')) {
    fail('Deposit/withdrawal history pages must query their own request table');
  }
  const adminWithdrawal = fs.readFileSync(path.join(root, 'admin-withdrawals.html'), 'utf8');
  if (!adminWithdrawal.includes('nplus_admin_resolve_demo_withdrawal') ||
      !adminWithdrawal.includes('No wallet credits or cash will move')) {
    fail('Admin withdrawal review must use the guarded status-only RPC');
  }
  const requestSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql'), 'utf8').toLowerCase();
  for (const contract of [
    'public.nplus_create_demo_deposit_request',
    'public.nplus_create_demo_withdrawal_request',
    'public.nplus_admin_resolve_demo_withdrawal',
    'withdrawal_requests_one_pending_per_user_uidx',
    'wallet_changed',
    'cash_paid',
    'revoke all on function public.nplus_admin_resolve_demo_withdrawal'
  ]) {
    if (!requestSql.includes(contract.toLowerCase())) fail('Demo request SQL contract missing: ' + contract);
  }
} catch (e) {
  fail('Demo wallet request guards failed: ' + e.message);
}

// Password recovery must use Supabase Auth, never a fixed OTP or browser-local fake reset.
try {
  const recoveryPage = fs.readFileSync(path.join(root, 'forgot-password.html'), 'utf8');
  for (const required of [
    'resetPasswordForEmail(email, { redirectTo })',
    'PASSWORD_RECOVERY',
    'client.auth.updateUser({ password })',
    'mode=reset',
    'getSession()'
  ]) {
    if (!recoveryPage.includes(required)) fail('Secure password recovery behavior missing: ' + required);
  }
  if (/Demo:\s*123456|localStorage\.setItem\(\s*['"]nplus_user['"]/i.test(recoveryPage) ||
      /function\s+sendOTP\s*\(/i.test(recoveryPage)) {
    fail('Password recovery must not use a fixed OTP or browser-local fake password reset');
  }
} catch (e) {
  fail('Password recovery guard failed: ' + e.message);
}

// Activity must show server-recorded history for supported games and fail visibly if RPCs are unavailable.
try {
  const activityPage = fs.readFileSync(path.join(root, 'activity.html'), 'utf8');
  for (const required of [
    'id="gameHistoryStatus"',
    'id="gameRows"',
    'nplus_wingo_demo_my_bets',
    'nplus_moto_demo_my_bets',
    'nplus_aviator_demo_my_bets',
    'Game history is unavailable in this environment',
    'readRpc(client,name,args)'
  ]) {
    if (!activityPage.includes(required)) fail('Activity game-history flow missing: ' + required);
  }
  if (/localStorage\.getItem\([^)]*(?:bets|game)/i.test(activityPage)) {
    fail('Activity game history must not be sourced from browser-local bet data');
  }
} catch (e) {
  fail('Activity game-history guard failed: ' + e.message);
}

// Bonus values must come from the signed-in account ledger, not stale localStorage or placeholder campaigns.
try {
  const bonusPage = fs.readFileSync(path.join(root, 'bonus.html'), 'utf8');
  for (const required of [
    'window.NPlusAuth.requireAuth()',
    'window.NPlusWallet.getBalance()',
    'window.NPlusWallet.transactions(500)',
    'BONUS_CREDIT',
    'REFERRAL_CREDIT',
    'heroStatus.textContent = "UNAVAILABLE"',
    'Reward-code redemption is unavailable until server-side validation'
  ]) {
    if (!bonusPage.includes(required)) fail('Bonus ledger flow missing: ' + required);
  }
  if (/localStorage\.getItem/i.test(bonusPage) ||
      /return\s+b\s*\?\?\s*1000/i.test(bonusPage) ||
      /id="redeem"/i.test(bonusPage) ||
      /virtual-credit activity system|Platform mode/i.test(bonusPage)) {
    fail('Bonus Center must not use browser-local wallet fallback, fake reward-code redemption or legacy platform-mode copy');
  }
} catch (e) {
  fail('Bonus ledger guard failed: ' + e.message);
}

// Promotion balances and referral tracking must be server-backed; demo rewards must never be cash.
try {
  const promotionPage = fs.readFileSync(path.join(root, 'promotion.html'), 'utf8');
  for (const required of [
    'window.NPlusAuth.requireAuth()',
    'window.NPlusWallet.getBalance()',
    'window.NPlusWallet.transactions(500)',
    'nplus_demo_referral_dashboard',
    'id="referralCode"',
    'id="referralLink"',
    'copyReferralCode',
    'copyReferralLink',
    '200 credits or more',
    '20 virtual demo credits exactly once',
    'No active campaigns configured',
    'promoSync',
    'historyStatus'
  ]) {
    if (!promotionPage.includes(required)) fail('Promotion/referral flow missing: ' + required);
  }
  if (/localStorage\.getItem/i.test(promotionPage) ||
      /value=["']NPLUSPLAY["']/i.test(promotionPage) ||
      /data-title=["']Weekly Reward Campaign["']/i.test(promotionPage) ||
      /Promotion Center · Platform mode/i.test(promotionPage) ||
      /window\.NPlusWallet\.changeBalance\s*\(/i.test(promotionPage)) {
    fail('Promotion page must not show local balances, shared fake codes, sample live campaigns or cash-like demo rewards');
  }

  const signupPage = fs.readFileSync(path.join(root, 'auth.html'), 'utf8');
  const authCore = fs.readFileSync(path.join(root, 'core/nplus-auth.js'), 'utf8');
  if (!signupPage.includes('id="signupReferralCode"') ||
      !signupPage.includes('new URLSearchParams(location.search).get("ref")') ||
      !signupPage.includes('referralCode: pendingSignup.referralCode') ||
      !authCore.includes('nplus_demo_referral_apply') ||
      !authCore.includes('referralResult')) {
    fail('Signup must prefill, preserve and server-apply the optional referral code after email OTP');
  }

  const referralSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_DEMO_REFERRALS.sql'), 'utf8');
  for (const required of [
    'create table if not exists public.nplus_demo_referral_codes',
    'create table if not exists public.nplus_demo_referrals',
    'public.nplus_demo_referral_dashboard',
    'public.nplus_demo_referral_apply',
    'public.nplus_demo_award_referral_on_approved_request',
    "NEW.amount < 200",
    "NEW.payment_method, '') <> 'DEMO_CREDIT'",
    "'REFERRAL_CREDIT', 'DEMO_REFERRAL'",
    'revoke all on table public.nplus_demo_referrals from public, anon, authenticated',
    'revoke all on function public.nplus_demo_referral_apply(text) from public, anon, authenticated'
  ]) {
    if (!referralSql.toLowerCase().includes(required.toLowerCase())) fail('Demo referral SQL contract missing: ' + required);
  }
  if (!referralSql.includes('nplus_demo_referral_approved_request') ||
      !referralSql.includes('qualifying_request_id') ||
      !referralSql.toLowerCase().includes('no cash value')) {
    fail('Referral SQL must have a guarded approval trigger, one-time qualification record and demo-only ledger note');
  }
} catch (e) {
  fail('Promotion/referral guard failed: ' + e.message);
}

// The account page must not display a stale browser-local balance as authoritative.
try {
  const accountPage = fs.readFileSync(path.join(root, 'account.html'), 'utf8');
  if (!accountPage.includes('syncEl.textContent="UNAVAILABLE"') ||
      /paintWallet\(\s*legacy\s*,\s*["']LOCAL FALLBACK["']\s*\)/i.test(accountPage) ||
      /localStorage\.getItem\(\s*LEGACY\s*\)/i.test(accountPage)) {
    fail('Account wallet must fail closed when Supabase balance cannot be loaded; no local balance fallback');
  }
  for (const rpc of [
    'nplus_wingo_demo_my_bets',
    'nplus_moto_demo_my_bets',
    'nplus_aviator_demo_my_bets'
  ]) {
    if (!accountPage.includes(rpc)) fail('Account game stats must use server history RPC: ' + rpc);
  }
  if (/function\s+legacyBets\s*\(/.test(accountPage) ||
      /setInterval\(renderStats,\s*1500\)/.test(accountPage) ||
      !accountPage.includes('statsStatusEl.textContent="UNAVAILABLE"')) {
    fail('Account game stats must be server-backed, throttled and fail closed');
  }
  for (const required of [
    '.from("profiles")',
    'client.auth.getSession()',
    'client.auth.getUser()',
    'notifyGameResults',
    'prefReduceMotion',
    'bindPreferenceControls()',
    'window.NPlusAuth.signOut("user_requested")'
  ]) {
    if (!accountPage.includes(required)) fail('Account profile/security/preferences behavior missing: ' + required);
  }
  for (const fake of [
    'Profile ID <b>NPLUS-PLAYER</b>',
    'Device check <b>Protected</b>',
    'Security status <b>Good</b>',
    'Notification controls will manage game results',
    'Platform terms and privacy controls can be connected here'
  ]) {
    if (accountPage.includes(fake)) fail('Hard-coded placeholder account claim remains: ' + fake);
  }
} catch (e) {
  fail('Account wallet consistency guard failed: ' + e.message);
}

// Account settings are authenticated and server-persisted, not browser-local placeholders.
try {
  const accountPage = fs.readFileSync(path.join(root, 'account.html'), 'utf8').toLowerCase();
  const accountMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261019000100_account_preferences.sql'), 'utf8').toLowerCase();

  for (const required of [
    'client.from("user_preferences")',
    'client.from("profiles").update({display_name:name})',
    'client.auth.updateuser({password:newpassword})',
    'client.auth.signinwithpassword({email:user.email,password:currentpassword})',
    'id="profileeditform"',
    'id="passwordform"'
  ]) {
    if (!accountPage.includes(required)) fail('Account settings implementation missing: ' + required);
  }
  if (accountPage.includes('nplus_account_preferences_v1') ||
      accountPage.includes('localstorage.setitem(local_prefs_key')) {
    fail('Account preferences must not be browser-local-only');
  }
  for (const contract of [
    'create table if not exists public.user_preferences',
    'alter table public.user_preferences enable row level security',
    'grant select, insert, update on table public.user_preferences to authenticated',
    'auth.uid() = user_id',
    'grant update (display_name) on table public.profiles to authenticated',
    'auth.uid() = id'
  ]) {
    if (!accountMigration.includes(contract)) fail('Account settings migration contract missing: ' + contract);
  }
  if (/grant update\s*\([^)]*role/i.test(accountMigration) ||
      /grant update\s*\([^)]*email/i.test(accountMigration) ||
      /grant update\s*\([^)]*phone/i.test(accountMigration)) {
    fail('Account migration must not grant edits to role, email or phone');
  }
} catch (e) {
  fail('Account settings persistence QA failed: ' + e.message);
}

// Repository-wide guard: browser code must never award a generic GAME_WIN credit.
for (const file of htmls) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  const calls = /(?:NPlusWallet|wallet)\.changeBalance\s*\(\s*([^,]+),\s*\{[^}]{0,250}?\btype\s*:\s*['"]GAME_WIN['"]/gi;
  for (const match of html.matchAll(calls)) {
    if (!String(match[1] || '').trim().startsWith('-')) {
      fail(file + ' contains a client-authored positive GAME_WIN wallet credit');
    }
  }
}

for (const required of [
  'manifest.webmanifest', 'sw.js', 'offline.html', 'assets/nplus-icon.svg',
  'core/nplus-config.js', 'core/nplus-auth.js', 'core/nplus-wallet-bridge.js',
  'admin-users.html', 'deposit-demo.html',
  'sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql', 'sql/NPLUS_PLAY_PROFILE_DEPOSIT_GUARDS.sql',
  'sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql',
  'sql/NPLUS_PLAY_MOTORACE_SCHEMA.sql',
  'sql/NPLUS_PLAY_MOTORACE_RPC.sql',
  'sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql',
  'sql/NPLUS_PLAY_AVIATOR_RPC.sql',
  'sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql',
  'sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql',
  'sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql',
  'sql/NPLUS_PLAY_ADMIN_DEPOSIT_ACTIONS.sql',
  'sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql',
  'qa/test-admin-game-status.sql',
  'qa/test-admin-user-tools.sql',
  'qa/test-admin-deposits.sql',
  'qa/test-phone-enumeration-revoke.sql',
  'qa/test-wingo-settlement.sql',
  'qa/test-motorace-settlement.sql',
  'qa/test-aviator-settlement.sql',
  'qa/test-generic-wallet-credit-guard.sql',
  'sql/NPLUS_PLAY_DEMO_WALLET_REQUESTS.sql',
  'supabase/migrations/20261019000150_demo_wallet_requests.sql',
  'supabase/migrations/20261019000175_admin_deposit_actions.sql',
  'qa/test-demo-wallet-requests.sql',
  'sql/NPLUS_PLAY_DEMO_REFERRALS.sql',
  'supabase/migrations/20261019000200_demo_referrals.sql',
  'qa/test-demo-referrals.sql',
  'deposit-history.html', 'withdrawal-history.html', 'admin-withdrawals.html'
]) {
  if (!exists(required)) fail('required file missing: ' + required);
}

// Release guard: WINGO must not credit wins through the legacy generic client RPC.
try {
  const wingo = fs.readFileSync(path.join(root, 'wingo.html'), 'utf8');
  if (/type\s*:\s*["']GAME_WIN["']/.test(wingo)) {
    fail('WINGO must not issue client-authoritative GAME_WIN credits');
  }
  if (!wingo.includes('nplus_wingo_demo_place_bet') ||
      !wingo.includes('nplus_wingo_demo_settle_round') ||
      !wingo.includes('nplus_wingo_demo_my_bets') ||
      !wingo.includes('nplus_wingo_demo_history')) {
    fail('WINGO server placement, settlement, history or recovery integration missing');
  }
  const settlementSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql'), 'utf8');
  for (const required of [
    'create table if not exists public.nplus_wingo_demo_rounds',
    'create table if not exists public.nplus_wingo_demo_bets',
    'public.nplus_wingo_demo_place_bet',
    'public.nplus_wingo_demo_settle_round',
    'public.nplus_wingo_demo_my_bets',
    'public.nplus_wingo_demo_history',
    'revoke all on function public.nplus_wingo_demo_place_bet',
    'revoke all on function public.nplus_wingo_demo_settle_round'
  ]) {
    if (!settlementSql.toLowerCase().includes(required.toLowerCase())) {
      fail('WINGO settlement SQL contract missing: ' + required);
    }
  }
} catch (e) {
  fail('WINGO server settlement guard failed: ' + e.message);
}

// Release guard: migrated games must use server settlement, never client-authored wins.
try {
  const adminDeposits = fs.readFileSync(path.join(root, 'admin-deposits.html'), 'utf8');
  for (const rpc of ['nplus_approve_deposit','nplus_reject_deposit']) {
    if (!adminDeposits.includes(rpc)) fail('N+ ADMIN deposit page RPC missing: ' + rpc);
  }
  const depositSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_ADMIN_DEPOSIT_ACTIONS.sql'), 'utf8').toLowerCase();
  for (const contract of [
    'create or replace function public.nplus_approve_deposit',
    'create or replace function public.nplus_reject_deposit',
    'raise exception \'admin access required.\'',
    'for update',
    'revoke all on function public.nplus_approve_deposit'
  ]) {
    if (!depositSql.includes(contract.toLowerCase())) fail('N+ ADMIN deposit RPC security contract missing: ' + contract);
  }

  const adminUsers = fs.readFileSync(path.join(root, 'admin-users.html'), 'utf8');
  for (const rpc of ['nplus_admin_user_directory','nplus_admin_user_transactions','nplus_admin_adjust_demo_wallet']) {
    if (!adminUsers.includes(rpc)) fail('N+ ADMIN Users page RPC missing: ' + rpc);
  }
  const adminSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql'), 'utf8').toLowerCase();
  for (const contract of [
    'create or replace function public.nplus_admin_user_directory',
    'create or replace function public.nplus_admin_user_transactions',
    'create or replace function public.nplus_admin_adjust_demo_wallet',
    'raise exception \'admin access required.\'',
    'revoke all on function public.nplus_admin_adjust_demo_wallet'
  ]) {
    if (!adminSql.includes(contract.toLowerCase())) fail('N+ ADMIN RPC security contract missing: ' + contract);
  }
  for (const [page, label] of [['k3.html','K3'], ['5d.html','5D'], ['trx-wingo.html','TRX WINGO']]) {
    const source = fs.readFileSync(path.join(root, page), 'utf8');
    if (/NPlusWallet\.changeBalance\s*\(/.test(source) || /type\s*:\s*['"]GAME_WIN['"]/.test(source)) {
      fail(page + ' must not write wallet entries client-side while payout rules are pending');
    }
    if (!source.includes('BETTING PAUSED')) {
      fail(page + ' must visibly pause bets until server payout rules are approved');
    }
    if (page === 'k3.html' && source.includes('<span class="live"><i></i>LIVE</span>')) {
      fail('K3 must not display a LIVE badge while wagering is paused');
    }
    if (page === 'trx-wingo.html' && source.includes('<span class="live">● LIVE</span>')) {
      fail('TRX WINGO must not display a LIVE badge while wagering is paused');
    }
  }

  const adminLogin = fs.readFileSync(path.join(root, 'admin-login.html'), 'utf8');
  if (!adminLogin.includes('Admin session check failed:') ||
      !adminLogin.includes('Admin login failed:') ||
      !adminLogin.includes('finally {')) {
    fail('N+ ADMIN login must recover cleanly from session/network exceptions');
  }

  const aiRoulette = fs.readFileSync(path.join(root, 'ai-roulette.html'), 'utf8');
  if (!aiRoulette.includes('Coming Soon') ||
      !aiRoulette.includes('AI ROULETTE') ||
      /₹\s*50,000|\b50,000\.00\b/.test(aiRoulette) ||
      /Math\.random\s*\(/.test(aiRoulette) ||
      /GAME_WIN|NPlusWallet|localStorage.*balance/i.test(aiRoulette)) {
    fail('AI Roulette must not show fake balance or unbacked betting; keep it Coming Soon until wallet/RPC integration exists');
  }

  const authPage = fs.readFileSync(path.join(root, 'auth.html'), 'utf8');
  const authCore = fs.readFileSync(path.join(root, 'core/nplus-auth.js'), 'utf8');
  if (!authPage.includes('resendOtpBtn') ||
      !authPage.includes('NPlusAuth.resendSignupEmailOtp') ||
      !authCore.includes('client.auth.resend') ||
      !authCore.includes('resendSignupEmailOtp')) {
    fail('Signup OTP recovery must provide a resend-code action');
  }

  const home = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  if (home.includes('readLegacyWallet') || home.includes('LEGACY_STORE') ||
      /localStorage\.getItem\([^)]*balance/i.test(home)) {
    fail('Home wallet must not fall back to a browser-stored balance');
  }
  if (!home.includes('walletEl.textContent = "SYNCING…";') ||
      !home.includes('walletEl.textContent = "UNAVAILABLE";')) {
    fail('Home wallet must show loading/unavailable state until Supabase sync succeeds');
  }

  if (!home.includes('VIRTUAL DEMO') || !home.includes('Demo Leaderboard') ||
      !home.includes('Sample scores • virtual credits only') ||
      !home.includes('class="badge paused"') ||
      /class="live-label"><span><\/span> LIVE/.test(home)) {
    fail('Homepage must clearly label virtual-demo mode, sample scores and paused games');
  }

  const adminGames = fs.readFileSync(path.join(root, 'admin-games.html'), 'utf8');
  if (!adminGames.includes('HARD_PAUSED_GAMES = new Set(["K3", "5D", "TRX"])') ||
      !adminGames.includes('BETTING PAUSED') ||
      !adminGames.includes('LOCKED · PAYOUT RULES PENDING') ||
      !adminGames.includes('PAUSED · RULES PENDING')) {
    fail('N+ ADMIN game cards must show and lock paused wagers until payout rules are approved');
  }
  if (!adminGames.includes('from("game_settings")') ||
      !adminGames.includes('nplus_set_game_status') ||
      !adminGames.includes('toggleServerGameStatus') ||
      !adminGames.includes('loadServerGameSettings')) {
    fail('N+ ADMIN game status toggles must read/write persistent Supabase settings');
  }
  const adminGameStatusSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql'), 'utf8');
  if (!adminGameStatusSql.includes('Payout rules pending; this game cannot be enabled.') ||
      !adminGameStatusSql.includes("v_key in ('K3','5D','TRX') and p_enabled")) {
    fail('N+ ADMIN must server-lock K3/5D/TRX until payout rules are approved');
  }

  const wingoSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql'), 'utf8');
  if (!wingoSql.includes("game_key = 'WINGO' and enabled = true") ||
      !wingoSql.includes('WINGO betting is disabled by admin') ||
      !wingoSql.includes("'betting_enabled'")) {
    fail('WINGO backend must enforce and expose the Admin pause status');
  }
  const wingoPage = fs.readFileSync(path.join(root, 'wingo.html'), 'utf8');
  if (!wingoPage.includes('serverRoundCache[state.sec]?.betting_enabled===false') ||
      !wingoPage.includes('async function syncWingoAdminStatus')) {
    fail('WINGO UI must refresh and explain an Admin pause before attempting a wager');
  }
  const motoSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_MOTORACE_RPC.sql'), 'utf8');
  if (!motoSql.includes("game_key='MOTO' and enabled=true") ||
      !motoSql.includes('MotoRace betting is disabled by admin') ||
      !motoSql.includes("'betting_enabled'")) {
    fail('MotoRace backend must enforce and expose the Admin pause status');
  }
  const motoPage = fs.readFileSync(path.join(root, 'motorace.html'), 'utf8');
  if (!motoPage.includes('serverRoundCache?.betting_enabled===false') ||
      !motoPage.includes('async function syncMotoAdminStatus')) {
    fail('MotoRace UI must refresh and explain an Admin pause before attempting a wager');
  }
  const aviatorGameGateSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_AVIATOR_RPC.sql'), 'utf8');
  if (!aviatorGameGateSql.includes("game_key='AVIATOR' and enabled=true") ||
      !aviatorGameGateSql.includes('Aviator betting is disabled by admin') ||
      !aviatorGameGateSql.includes("'betting_enabled'")) {
    fail('Aviator backend must enforce and expose the Admin pause status');
  }
  const aviatorPage = fs.readFileSync(path.join(root, 'aviator.html'), 'utf8');
  if (!aviatorPage.includes('row.betting_enabled===false') ||
      !aviatorPage.includes('serverRound?.betting_enabled===false')) {
    fail('Aviator UI must show and enforce the Admin pause state');
  }

  const adminReports = fs.readFileSync(path.join(root, 'admin-reports.html'), 'utf8');
  if (!adminReports.includes('ESTIMATED ALL-TIME COMMISSION') ||
      !adminReports.includes('Estimate only') ||
      !adminReports.includes('MotoRace charges a 1.5% demo stake fee') ||
      !adminReports.includes('Aviator has no entry fee')) {
    fail('N+ ADMIN commission figures must be labelled estimated until a recorded fee ledger exists');
  }

  const deposit = fs.readFileSync(path.join(root, 'deposit.html'), 'utf8');
  if (deposit.includes('nplusplay_wallet_v1') ||
      /localStorage\.getItem\(LEGACY\)/.test(deposit)) {
    fail('Deposit page must not display a stale localStorage wallet balance');
  }
  if (!deposit.includes('walletReady=false') ||
      !deposit.includes('Please sign in and wait for the shared wallet to sync')) {
    fail('Deposit page must disable requests when the shared wallet cannot sync');
  }

  const withdraw = fs.readFileSync(path.join(root, 'withdraw.html'), 'utf8');
  if (/function\s+addRequest\s*\(/.test(withdraw) || /addRequest\s*\(\s*\{/.test(withdraw)) {
    fail('Withdraw page must not store withdrawal requests in localStorage');
  }
  if (!withdraw.includes('nplus_create_demo_withdrawal_request') ||
      !/no cash payout/i.test(withdraw) ||
      !withdraw.includes('withdrawal-history.html') ||
      !withdraw.includes('credits have no cash value')) {
    fail('Withdraw page must use the server-side demo request flow and clearly disable cash payouts');
  }
  if (/id=["'](?:holder|bank|accountNo|ifsc|branch|upiId|upiHolder|upiBank)["']/i.test(withdraw)) {
    fail('Withdraw page must not collect bank, account, IFSC or UPI details in demo mode');
  }

  const auth = fs.readFileSync(path.join(root, 'core/nplus-auth.js'), 'utf8');
  if (auth.includes('nplus_phone_is_registered')) {
    fail('Signup must not call the public phone-registration lookup RPC');
  }
  if (!auth.includes('verifyOtp') || !auth.includes('type: "email"')) {
    fail('Signup must retain the six-digit email OTP verification flow');
  }

  if (exists('admin-users.htlm')) {
    fail('Misspelled legacy admin-users.htlm duplicate must not be present in the release candidate');
  }

  const moto = fs.readFileSync(path.join(root, 'motorace.html'), 'utf8');
  if (/type\s*:\s*['"]GAME_WIN['"]/.test(moto) || /window\.NPlusWallet\.changeBalance/.test(moto)) {
    fail('MotoRace must not use generic client-controlled wallet writes');
  }
  for (const rpc of ['nplus_moto_demo_place_bet','nplus_moto_demo_reveal_round','nplus_moto_demo_settle_round']) {
    if (!moto.includes(rpc)) fail('MotoRace server RPC integration missing: ' + rpc);
  }

  const aviator = fs.readFileSync(path.join(root, 'aviator.html'), 'utf8');
  if (/type\s*:\s*['"]GAME_WIN['"]/.test(aviator) || /wallet\.changeBalance\s*\(/.test(aviator)) {
    fail('Aviator must not use generic client-controlled wallet credits');
  }
  for (const rpc of ['nplus_aviator_demo_current_round','nplus_aviator_demo_place_bet','nplus_aviator_demo_cashout']) {
    if (!aviator.includes(rpc)) fail('Aviator server RPC integration missing: ' + rpc);
  }
  if (aviator.includes('function crashForRound(')) fail('Aviator must not generate crash points in the browser');

  const aviatorSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_AVIATOR_RPC.sql'), 'utf8').toLowerCase();
  for (const required of [
    'public.nplus_aviator_demo_current_round',
    'public.nplus_aviator_demo_place_bet',
    'public.nplus_aviator_demo_cashout',
    'revoke all on function public.nplus_aviator_demo_cashout'
  ]) {
    if (!aviatorSql.includes(required.toLowerCase())) fail('Aviator settlement SQL contract missing: ' + required);
  }
} catch (e) {
  fail('Server-authoritative game guard failed: ' + e.message);
}

try {
  const adminGuardSql = fs.readFileSync(path.join(root, 'sql/NPLUS_PLAY_ADMIN_NULL_PROFILE_GUARD_2026-10-19.sql'), 'utf8').toLowerCase();
  const guardedFunctions = [
    'public.nplus_admin_clear_wingo_manual',
    'public.nplus_admin_commission_summary',
    'public.nplus_admin_deposit_summary',
    'public.nplus_admin_save_wingo_manual',
    'public.nplus_admin_set_wingo_demo',
    'public.nplus_admin_wingo_live_bets',
    'public.nplus_admin_wingo_round_summary',
    'public.nplus_set_game_status'
  ];
  for (const signature of guardedFunctions) {
    if (!adminGuardSql.includes('create or replace function ' + signature)) {
      fail('NULL-safe Admin guard migration missing function: ' + signature);
    }
  }
  const roleGuards = adminGuardSql.split("if coalesce(v_role, '') <> 'admin' then").length - 1;
  if (roleGuards !== 9) fail('Admin null-profile migration must have 9 NULL-safe role guards; found ' + roleGuards);

  const guardTest = fs.readFileSync(path.join(root, 'qa/test-admin-null-profile-guard.sql'), 'utf8');
  if (!guardTest.includes('qa_null_guard_wallet_snapshot') ||
      !guardTest.includes('qa_null_guard_ledger_snapshot') ||
      !guardTest.includes('A valid admin was unexpectedly blocked') ||
      !guardTest.includes('public.nplus_set_game_status')) {
    fail('Admin NULL-profile regression must cover profile-missing denial, valid Admin access and unchanged wallet/ledger state');
  }
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/nplus-play-qa.yml'), 'utf8');
  if (!workflow.includes('qa/test-admin-null-profile-guard.sql')) {
    fail('Admin NULL-profile regression must remain wired into CI');
  }

  const preflight = fs.readFileSync(path.join(root, 'sql/READ_ONLY_NPLUS_PLAY_RELEASE_PREFLIGHT.sql'), 'utf8');
  const preflightLower = preflight.toLowerCase();
  if (!preflightLower.includes('with target_admin_functions as') ||
      !preflight.includes('nplus_wallet_change(numeric,text,text,text)') ||
      !preflight.includes('nplus_phone_is_registered(text)') ||
      !preflight.includes('nplus_wingo_demo_rounds')) {
    fail('Read-only release preflight is missing required security/schema checks');
  }
  const mutationPrefixes = ['insert ', 'update ', 'delete ', 'alter ', 'drop ', 'create ', 'grant ', 'revoke ', 'truncate ', 'begin;', 'commit;'];
  const mutationLine = preflight.split('\n').map(line => line.trim().toLowerCase())
    .find(line => line && !line.startsWith('--') && mutationPrefixes.some(prefix => line.startsWith(prefix)));
  if (mutationLine) {
    fail('Release preflight must remain read-only; found a possible mutation statement: ' + mutationLine);
  }
} catch (e) {
  fail('Admin NULL-profile static contract failed: ' + e.message);
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
