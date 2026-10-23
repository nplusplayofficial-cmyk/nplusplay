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
    ("/dashboard.html", ["N+ PLAY"]),
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
    ("/bonus.html", []),
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

PRIMARY_NAV_PAGES = {
    "/", "/index.html", "/activity.html", "/bonus.html", "/promotion.html", "/account.html",
}

MOBILE_CRITICAL = {
    "/", "/index.html", "/auth.html", "/forgot-password.html", "/admin-login.html",
    "/deposit.html", "/withdraw.html", "/wingo.html", "/motorace.html",
    "/aviator.html", "/vip.html", "/referral.html", "/safe.html",
    "/activity.html", "/bonus.html", "/promotion.html", "/account.html",
}

def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)

def file_for_path(path: str) -> Path:
    return (REPO_ROOT / "index.html") if path == "/" else (REPO_ROOT / path.lstrip("/"))

def main() -> int:
    errors: list[str] = []
    loaded = 0
    responsive_checked = 0
    overflow_warnings: list[str] = []
    primary_nav_boxes: list[tuple[str, float, float]] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1365, "height": 900})
        page.set_default_timeout(12000)

        skipped_optional: list[str] = []
        for path, needles in PAGES:
            if not file_for_path(path).is_file():
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
                back_button = page.locator("#nplus-global-back")
                if path in PRIMARY_NAV_PAGES:
                    if back_button.count() != 0:
                        errors.append(f"{path}: floating back arrow should be hidden on primary navigation pages")
                    bottom_nav = page.locator(".nplus-bottom-nav")
                    bottom_nav.wait_for(state="visible", timeout=8000)
                    nav_items = bottom_nav.locator(".nplus-nav-item")
                    if nav_items.count() != 5:
                        errors.append(f"{path}: shared bottom nav must contain exactly five items")
                    active_items = bottom_nav.locator(".nplus-nav-item.active")
                    if active_items.count() != 1:
                        errors.append(f"{path}: exactly one bottom-nav item must be active")
                    expected_active = "index.html" if path == "/" else path.lstrip("/")
                    if active_items.count() == 1 and active_items.get_attribute("href") != expected_active:
                        errors.append(f"{path}: active bottom-nav target mismatch")
                    nav_box = bottom_nav.bounding_box()
                    if nav_box:
                        primary_nav_boxes.append((path, nav_box["width"], nav_box["height"]))
                    else:
                        errors.append(f"{path}: shared bottom nav has no visible bounding box")
                else:
                    back_button.wait_for(state="visible", timeout=8000)
                    if back_button.count() != 1:
                        errors.append(f"{path}: shared back arrow is missing or duplicated")
                    back_box = back_button.bounding_box()
                    if not back_box or back_box["width"] < 36 or back_box["height"] < 36:
                        errors.append(f"{path}: shared back arrow has an unusable tap target")
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

        # Verify previous in-app navigation and safe direct-entry fallback.
        try:
            page.goto(BASE_URL + "/beginner-guide.html", wait_until="domcontentloaded", timeout=25000)
            page.evaluate("location.href = '/about.html'")
            page.wait_for_url("**/about.html", timeout=12000)
            page.locator("#nplus-global-back").click()
            page.wait_for_url("**/beginner-guide.html", timeout=12000)
        except Exception as exc:
            errors.append(f"same-origin back navigation: {type(exc).__name__}: {exc}")
        # Compare the common bottom bar geometry across all five primary sections.
        if len(primary_nav_boxes) >= 5:
            widths = [box[1] for box in primary_nav_boxes]
            heights = [box[2] for box in primary_nav_boxes]
            if max(widths) - min(widths) > 2 or max(heights) - min(heights) > 2:
                errors.append("primary sections have inconsistent bottom-nav dimensions: " + repr(primary_nav_boxes))
        elif len(primary_nav_boxes) > 0:
            errors.append("not all primary navigation pages were measured: " + repr(primary_nav_boxes))

        # A direct entry on a secondary page should still have the shared back control and return Home.
        try:
            direct_page = browser.new_page(viewport={"width": 1365, "height": 900})
            direct_page.goto(BASE_URL + "/support.html", wait_until="domcontentloaded", timeout=25000)
            direct_page.locator("#nplus-global-back").wait_for(state="visible", timeout=8000)
            direct_page.locator("#nplus-global-back").click()
            direct_page.wait_for_url("**/index.html", timeout=12000)
            direct_page.close()
        except Exception as exc:
            errors.append(f"direct-entry safe fallback: {type(exc).__name__}: {exc}")
        browser.close()

    print(f"Rendered pages: {loaded}/{len(PAGES) - len(skipped_optional)} available in this branch")
    available_mobile = sum(1 for path in MOBILE_CRITICAL if file_for_path(path).is_file())
    print(f"Mobile viewport checks: {responsive_checked}/{available_mobile}")
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
