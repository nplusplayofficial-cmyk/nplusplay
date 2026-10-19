#!/usr/bin/env python3
"""Read-only Playwright smoke test for N+ PLAY's static HTML pages.

This serves the checked-out candidate locally, uses no credentials, submits no forms,
and never calls wallet/admin mutations intentionally. It validates page responses,
basic rendering, and a small set of critical UI contracts at desktop/mobile viewports.
"""
from __future__ import annotations

import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_URL = "http://127.0.0.1:4173"
REPO_ROOT = Path(__file__).resolve().parents[1]
PAGES = [
    ("/", ["N+ PLAY"]),
    ("/index.html", ["VIRTUAL DEMO"]),
    ("/auth.html", ["resendOtpBtn"]),
    ("/forgot-password.html", ["password"]),
    ("/admin-login.html", ["password"]),
    ("/admin.html", []),
    ("/admin-games.html", []),
    ("/admin-users.html", []),
    ("/admin-deposits.html", []),
    ("/admin-reports.html", []),
    ("/account.html", []),
    ("/activity.html", []),
    ("/deposit.html", []),
    ("/withdraw.html", []),
    ("/wingo.html", []),
    ("/motorace.html", []),
    ("/aviator.html", []),
    ("/k3.html", []),
    ("/5d.html", []),
    ("/trx-wingo.html", []),
    ("/ai-roulette.html", ["COMING SOON"]),
    ("/vip.html", []),
    ("/referral.html", []),
    ("/gift.html", []),
    ("/safe.html", []),
    ("/attendance.html", []),
    ("/support.html", []),
    ("/admin-support.html", []),
    ("/admin-vip.html", []),
    ("/notification.html", []),
    ("/beginner-guide.html", []),
    ("/coupons.html", []),
    ("/jackpot.html", []),
    ("/rebate.html", []),
    ("/game-statistics.html", []),
    ("/promotion.html", []),
]

MOBILE_CRITICAL = {
    "/", "/auth.html", "/forgot-password.html", "/admin-login.html",
    "/deposit.html", "/withdraw.html", "/wingo.html", "/motorace.html",
    "/aviator.html", "/vip.html", "/referral.html", "/safe.html",
}

def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)

def main() -> int:
    errors: list[str] = []
    loaded = 0
    responsive_checked = 0
    overflow_warnings: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1365, "height": 900})
        page.set_default_timeout(12000)

        skipped_optional: list[str] = []
        for path, needles in PAGES:
            local_file = (REPO_ROOT / path.lstrip("/")) if path != "/" else (REPO_ROOT / "index.html")
            if not local_file.is_file():
                skipped_optional.append(path)
                continue
            try:
                response = page.goto(BASE_URL + path, wait_until="domcontentloaded", timeout=25000)
                if response is None:
                    errors.append(f"{path}: navigation returned no response")
                    continue
                if response.status >= 400:
                    errors.append(f"{path}: HTTP {response.status}")
                    continue
                page.locator("body").wait_for(state="visible")
                body = page.locator("body").inner_text(timeout=8000).strip()
                if len(body) < 20:
                    errors.append(f"{path}: body rendered almost empty ({len(body)} chars)")
                    continue

                html = page.content()
                for needle in needles:
                    if needle.lower() == "password":
                        if page.locator('input[type="password"]').count() < 1:
                            errors.append(f"{path}: expected password input missing")
                    elif needle == "resendOtpBtn":
                        if page.locator("#resendOtpBtn").count() < 1:
                            errors.append(f"{path}: signup OTP resend control missing")
                    elif needle.lower() not in (body + " " + html).lower():
                        errors.append(f"{path}: expected contract text/control missing: {needle}")

                loaded += 1

                if path in MOBILE_CRITICAL:
                    page.set_viewport_size({"width": 390, "height": 844})
                    page.reload(wait_until="domcontentloaded", timeout=25000)
                    page.locator("body").wait_for(state="visible")
                    dimensions = page.evaluate("""() => ({
                      viewport: document.documentElement.clientWidth,
                      body: document.body.scrollWidth,
                      document: document.documentElement.scrollWidth
                    })""")
                    responsive_checked += 1
                    if dimensions["document"] > dimensions["viewport"] + 80:
                        overflow_warnings.append(
                            f"{path}: mobile horizontal overflow "
                            f"(viewport={dimensions['viewport']}, document={dimensions['document']})"
                        )
                    page.set_viewport_size({"width": 1365, "height": 900})
            except Exception as exc:  # report all affected paths in a single CI run
                errors.append(f"{path}: {type(exc).__name__}: {exc}")

        browser.close()

    print(f"Rendered pages: {loaded}/{len(PAGES) - len(skipped_optional)} available in this branch")
    print(f"Mobile viewport checks: {responsive_checked}/{sum(1 for path in MOBILE_CRITICAL if (REPO_ROOT / path.lstrip(\"/\")).is_file())}")
    for path in skipped_optional:
        print(f"SKIP {path}: not present in this checkout/PR branch")
    for warning in overflow_warnings:
        print("WARN " + warning)
    for error in errors:
        fail(error)

    if errors:
        print(f"Browser smoke failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1

    print("Browser smoke passed. This does not verify live Supabase Auth/RLS/RPC flows.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
