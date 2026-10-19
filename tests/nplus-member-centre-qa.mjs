import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const requiredPages = [
  "vip.html", "referral.html", "gift.html", "safe.html", "attendance.html",
  "game-statistics.html", "rebate.html", "notification.html", "beginner-guide.html",
  "about.html", "coupons.html", "jackpot.html", "support.html",
  "admin-vip.html", "admin-support.html", "account.html", "admin.html"
];
const knownExisting = [
  "index.html", "activity.html", "bonus.html", "promotion.html", "auth.html",
  "admin-login.html", "admin-deposits.html", "admin-withdrawals.html",
  "admin-users.html", "admin-reports.html", "deposit.html", "withdraw.html",
  "core/nplus-config.js", "core/nplus-auth.js", "sw.js", "manifest.webmanifest"
];
const failures = [];
let checks = 0;
function check(condition, message) {
  checks++;
  if (!condition) failures.push(message);
}
function read(file) {
  const full = path.resolve(file);
  check(fs.existsSync(full), `Missing required file: ${file}`);
  return fs.existsSync(full) ? fs.readFileSync(full, "utf8") : "";
}

const htmlFiles = new Set([...requiredPages, ...knownExisting].filter(f => f.endsWith(".html") && fs.existsSync(f)));
for (const file of requiredPages) {
  if (!fs.existsSync(file)) { check(false, `Missing page: ${file}`); continue; }
  const html = read(file);
  check((html.match(/<html\b/gi) || []).length === 1 && (html.match(/<\/html>/gi) || []).length === 1, `${file}: HTML root is not balanced`);
  check((html.match(/<script\b/gi) || []).length === (html.match(/<\/script>/gi) || []).length, `${file}: script tags are not balanced`);
  const ids = [...html.matchAll(/\bid=["']([^"']+)["']/g)].map(m => m[1]);
  const duplicates = ids.filter((id, i) => ids.indexOf(id) !== i);
  check(duplicates.length === 0, `${file}: duplicate ids: ${[...new Set(duplicates)].join(", ")}`);

  const links = [...html.matchAll(/\b(?:href|src)=["']([^"']+)["']/gi)].map(m => m[1]);
  for (const href of links) {
    if (/^(?:https?:|mailto:|tel:|data:|#|javascript:)/i.test(href)) continue;
    const raw = href.split(/[?#]/)[0];
    if (!raw || raw.startsWith("//")) continue;
    const target = path.normalize(path.join(path.dirname(file), decodeURIComponent(raw)));
    if (target.endsWith(".html") || target.endsWith(".js") || target.endsWith(".webmanifest") || target.endsWith(".svg")) {
      check(fs.existsSync(target), `${file}: missing local asset/link: ${href}`);
    }
  }
}

const sql = read("sql/NPLUS_VIP_REFERRAL_DEMO_2026-10-19.sql");
check(sql.includes("BEGIN;") && (sql.match(/COMMIT;/g) || []).length === 1, "Migration should be a single transaction.");
for (const table of [
  "nplus_demo_referral_codes", "nplus_demo_referrals", "nplus_demo_vip_state",
  "nplus_demo_safe_balances", "nplus_demo_safe_transfers", "nplus_demo_gift_codes",
  "nplus_demo_gift_claims", "nplus_demo_attendance_claims", "nplus_demo_support_requests"
]) {
  check(sql.includes(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;`), `Migration must enable RLS for ${table}`);
  check(sql.includes(`public.${table}`), `Migration missing table reference ${table}`);
}
check(sql.includes("REVOKE ALL ON TABLE public.nplus_demo_referral_codes"), "Migration must revoke direct table access from browser roles.");
check(sql.includes("FROM PUBLIC, anon, authenticated;"), "Migration should revoke browser direct table access.");
check(sql.includes("REVOKE ALL ON FUNCTION public.nplus_demo_admin_vip_dashboard() FROM PUBLIC, anon;"), "Admin VIP RPC must revoke anonymous execution.");
check(sql.includes("REVOKE ALL ON FUNCTION public.nplus_demo_admin_support_update(uuid,text,text) FROM PUBLIC, anon;"), "Admin support RPC must revoke anonymous execution.");
check(sql.includes("GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_vip_dashboard() TO authenticated;"), "Admin VIP RPC must grant authenticated execution.");
check(sql.includes("IF NOT coalesce(public.nplus_is_admin(),false)"), "Admin RPCs must check the server-side admin role.");
check(sql.includes("NEW.amount, 0) < 200"), "Referral award must enforce 200-point qualifying request.");
check(sql.includes("reward_amount numeric(12,2) NOT NULL DEFAULT 20.00"), "Referral reward must default to 20 virtual points.");
check(sql.includes("ON CONFLICT (user_id, code) DO NOTHING"), "Gift redemption must prevent duplicate code claims.");
check(sql.includes("PRIMARY KEY (user_id, claim_date)"), "Attendance must enforce one claim per account/day.");
check(sql.includes("ON CONFLICT (user_id,claim_date) DO NOTHING"), "Attendance award must be duplicate-safe.");
check(sql.includes("p_amount <= 0 OR p_amount > 1000000"), "Admin gift creation must validate reward amounts.");
check(!/CREATE\\s+TABLE[^;]*interest_rate|CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.nplus_demo_safe_interest/i.test(sql), "Migration must not add an interest/guaranteed-return feature.");

const vip = read("vip.html");
check(vip.includes("nplus_demo_vip_dashboard"), "VIP page must use server-side VIP dashboard.");
check(vip.includes("nplus_demo_referral_dashboard"), "VIP page must use server-side referral dashboard.");
check(vip.includes("auth.html?ref="), "Unique referral link generation should be present.");
const auth = read("auth.html");
check(auth.includes('get("ref")'), "Signup should prefill referral code from invite URL.");
check(auth.includes('setMode("signup")'), "Referral invite link should open signup mode.");
const adminVip = read("admin-vip.html");
check(adminVip.includes("nplus_demo_admin_vip_dashboard"), "N+ ADMIN should load server-side VIP overview.");
check(adminVip.includes("nplus_is_admin") || adminVip.includes("profiles"), "N+ ADMIN page should perform a client-side signed-in/admin guard.");
const adminSupport = read("admin-support.html");
check(adminSupport.includes("nplus_demo_admin_support_update"), "Support admin should use server-side update RPC.");
const rebate = read("rebate.html");
check(!rebate.includes("claim rebate") && rebate.includes("No validated rebate data"), "Rebate should remain non-claimable until trusted settlement exists.");

const sw = read("sw.js");
for (const file of ["vip.html", "referral.html", "gift.html", "safe.html", "attendance.html", "support.html", "admin-support.html"]) {
  check(sw.includes(`"./${file}"`), `PWA shell is missing ${file}`);
}
check(sw.includes("nplus-play-shell-v5"), "PWA shell cache version should be bumped for the new pages.");

if (failures.length) {
  console.error(`N+ Member Centre QA FAILED — ${failures.length} of ${checks} checks failed`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log(`N+ Member Centre QA PASSED — ${checks} checks, ${requiredPages.length} required pages.`);
