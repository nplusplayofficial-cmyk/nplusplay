/* Shared N+ PLAY / N+ ADMIN same-origin back navigation. */
(() => {
  "use strict";
  if (window.__nplusBackNavInstalled) return;
  window.__nplusBackNavInstalled = true;
  const STACK_KEY = "nplus.inAppBackStack.v1";
  const PENDING_KEY = "nplus.inAppBackPending.v1";
  const BUTTON_ID = "nplus-global-back";
  const MAX_STACK = 60;
  const currentPath = () => location.pathname + location.search + location.hash;
  function readStack() {
    try {
      const value = JSON.parse(sessionStorage.getItem(STACK_KEY) || "[]");
      if (!Array.isArray(value)) return [];
      return value.filter(item => typeof item === "string" && item.startsWith("/") &&
        !item.startsWith("//") && !item.includes("\\")).slice(-MAX_STACK);
    } catch (_) { return []; }
  }
  function saveStack(stack) {
    try { sessionStorage.setItem(STACK_KEY, JSON.stringify(stack.slice(-MAX_STACK))); } catch (_) {}
  }
  function referrerPath() {
    try {
      if (!document.referrer) return "";
      const ref = new URL(document.referrer);
      if (ref.origin !== location.origin) return "";
      return ref.pathname + ref.search + ref.hash;
    } catch (_) { return ""; }
  }
  function fallbackPath() {
    const file = location.pathname.split("/").pop().toLowerCase();
    const adminSubpage = file.startsWith("admin-") && file !== "admin-login.html";
    return new URL(adminSubpage ? "./admin.html" : "./index.html", location.href).pathname;
  }
  const current = currentPath();
  let stack = readStack();
  let pending = "";
  try { pending = sessionStorage.getItem(PENDING_KEY) || ""; } catch (_) {}
  if (pending === current) {
    try { sessionStorage.removeItem(PENDING_KEY); } catch (_) {}
    if (stack[stack.length - 1] !== current) stack.push(current);
  } else {
    try { sessionStorage.removeItem(PENDING_KEY); } catch (_) {}
    const ref = referrerPath();
    if (!ref || ref === current) stack = [current];
    else {
      const i = stack.lastIndexOf(ref);
      stack = i >= 0 ? stack.slice(0, i + 1) : [ref];
      if (stack[stack.length - 1] !== current) stack.push(current);
    }
  }
  stack = stack.filter((item, index) => index === 0 || item !== stack[index - 1]);
  saveStack(stack);
  const style = document.createElement("style");
  style.textContent = [
    "#nplus-global-back{position:fixed;top:max(10px,env(safe-area-inset-top,0px));left:12px;z-index:2147483000;width:42px;height:42px;display:grid;place-items:center;padding:0;border:1px solid rgba(201,165,91,.62);border-radius:13px;color:#f0dfb5;background:rgba(12,12,10,.96);box-shadow:0 8px 26px rgba(0,0,0,.38);font:28px/1 system-ui,sans-serif;cursor:pointer;-webkit-tap-highlight-color:transparent;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px)}",
    "#nplus-global-back:hover{background:#211c12;border-color:#f0dfb5}",
    "#nplus-global-back:focus-visible{outline:2px solid #f0dfb5;outline-offset:3px}",
    "#nplus-global-back:active{transform:translateY(1px)}",
    "@media(prefers-reduced-motion:reduce){#nplus-global-back{transition:none}}"
  ].join("\n");
  (document.head || document.documentElement).appendChild(style);
  const button = document.createElement("button");
  button.id = BUTTON_ID; button.type = "button"; button.textContent = "←";
  button.setAttribute("aria-label", "Back to the previous N+ page");
  button.title = "Back to the previous N+ page";
  document.body.appendChild(button);
  function alignButton() {
    const root = document.querySelector("main.app, main.wrap, .app, .wrap, .page-shell, .shell, main");
    let left = 12;
    if (root) { const rect = root.getBoundingClientRect(); if (rect.width > 0 && Number.isFinite(rect.left)) left = Math.round(rect.left + 2); }
    button.style.left = Math.max(12, Math.min(left, Math.max(12, innerWidth - 54))) + "px";
  }
  alignButton(); addEventListener("resize", alignButton, { passive: true });
  button.addEventListener("click", () => {
    const now = currentPath(); let trail = readStack(); const index = trail.lastIndexOf(now); let target = "";
    if (index > 0) { target = trail[index - 1]; trail = trail.slice(0, index); }
    else { const ref = referrerPath(); target = ref && ref !== now ? ref : fallbackPath(); trail = target === now ? [now] : [target]; }
    if (!target || !target.startsWith("/") || target.startsWith("//") || target.includes("\\")) { target = fallbackPath(); trail = [target]; }
    if (target === now) { button.title = "You are already at the start of this page trail"; return; }
    saveStack(trail);
    try { sessionStorage.setItem(PENDING_KEY, target); } catch (_) {}
    window.location.replace(target);
  });
})();
