/* N+ PLAY — resilient server-settled round history for every demo game.
   Reads authenticated history RPCs only; never writes bets or wallets.
   Current/open round outcomes are intentionally excluded. */
(() => {
  "use strict";
  const page = (location.pathname.split("/").pop() || "").toLowerCase();
  const gameByPage = {
    "k3.html": "K3", "5d.html": "5D", "trx-wingo.html": "TRX",
    "wingo.html": "WINGO", "aviator.html": "AVIATOR", "motorace.html": "MOTO"
  };
  const game = gameByPage[page];
  if (!game) return;
  const defaults = { K3: 60, "5D": 60, TRX: 60, WINGO: 30 };
  let root, list, status, refreshButton, busy = false;

  const style = document.createElement("style");
  style.textContent = [
    ".nph-card{margin:10px 0 14px;padding:12px;border:1px solid rgba(201,165,91,.22);border-radius:15px;background:linear-gradient(145deg,rgba(28,27,21,.98),rgba(12,14,12,.98));color:#f4f1e8}",
    ".nph-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:8px}",
    ".nph-title{font-size:10px;font-weight:950;letter-spacing:1.25px;color:#e7d6ad}",
    ".nph-status{display:block;margin-top:4px;font-size:9px;color:#97978d}",
    ".nph-refresh{flex:0 0 auto;border:1px solid rgba(201,165,91,.28);border-radius:9px;padding:7px 10px;background:#181912;color:#efdfb7;font-size:9px;font-weight:850}",
    ".nph-refresh:disabled{opacity:.55}",
    ".nph-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;align-items:center;padding:9px 1px;border-top:1px solid rgba(255,255,255,.065)}",
    ".nph-row:first-child{border-top:0}",
    ".nph-row-latest{background:linear-gradient(90deg,rgba(201,165,91,.08),transparent);border-radius:7px}",
    ".nph-period{font-size:9px;color:#9e9c91;overflow-wrap:anywhere}",
    ".nph-result{margin-top:4px;font-size:11px;font-weight:900;line-height:1.45;overflow-wrap:anywhere;color:#f5f2e9}",
    ".nph-time{font-size:9px;color:#8a8a81;text-align:right;white-space:nowrap}",
    ".nph-empty{padding:12px 2px;color:#a6a69d;font-size:10px;line-height:1.6}",
    ".nph-foot{border-top:1px solid rgba(255,255,255,.06);padding-top:8px;margin-top:3px;color:#77786f;font-size:9px;line-height:1.5}",
    "@media(max-width:420px){.nph-row{grid-template-columns:minmax(0,1fr)}.nph-time{text-align:left}.nph-title{font-size:9px}}"
  ].join("\n");
  document.head.appendChild(style);

  function make(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = String(text);
    return el;
  }

  function mount() {
    if (document.getElementById("nplusServerRoundHistory")) return;
    root = make("section", "nph-card");
    root.id = "nplusServerRoundHistory";
    root.setAttribute("aria-label", "Latest server-settled demo rounds");
    const head = make("div", "nph-head");
    const titleWrap = make("div", "");
    titleWrap.appendChild(make("div", "nph-title", "LAST SETTLED ROUNDS"));
    status = make("span", "nph-status", "Loading verified server history…");
    titleWrap.appendChild(status);
    refreshButton = make("button", "nph-refresh", "REFRESH");
    refreshButton.type = "button";
    refreshButton.addEventListener("click", () => { void refresh(); });
    head.append(titleWrap, refreshButton);
    list = make("div", "nph-list");
    list.appendChild(make("div", "nph-empty", "Loading completed server rounds…"));
    const foot = make("div", "nph-foot", "Server-settled virtual demo results only. The current round stays hidden until settlement.");
    root.append(head, list, foot);
    // Keep the shared settled-round history at the end of the game content.
    // Inserting after the header placed this panel above the game on every page.
    const gameMain = document.querySelector("main");
    if (gameMain) gameMain.appendChild(root);
    else document.body.appendChild(root);
  }

  function activeDuration() {
    const active = document.querySelector(".mode.active, .mode[aria-pressed='true'], [data-sec].active");
    if (active) {
      const raw = Number(active.dataset.sec || active.dataset.durationSeconds || active.dataset.duration);
      if ([30, 60, 180, 300, 600].includes(raw)) return raw;
      const text = active.textContent || "";
      const match = text.match(/(30|60|180|300|600)\s*(SEC(?:OND)?S?|MIN(?:UTE)?S?)/i);
      if (match) {
        const n = Number(match[1]);
        return /MIN/i.test(match[2]) ? n * 60 : n;
      }
      const mins = text.match(/(1|3|5|10)\s*MIN/i);
      if (mins) return Number(mins[1]) * 60;
    }
    return defaults[game] || 60;
  }

  function asRows(value) {
    if (Array.isArray(value)) return value;
    if (typeof value === "string") {
      try { const parsed = JSON.parse(value); return Array.isArray(parsed) ? parsed : []; }
      catch (_) { return []; }
    }
    if (value && Array.isArray(value.rows)) return value.rows;
    if (value && Array.isArray(value.data)) return value.data;
    return [];
  }

  function fmtTime(value) {
    const parsed = value ? Date.parse(value) : NaN;
    if (!Number.isFinite(parsed)) return "Time unavailable";
    return new Date(parsed).toLocaleString("en-IN", {
      day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false
    });
  }

  function normalizeRow(row) {
    const gameStatus = String(row && row.status || "").toLowerCase();
    if (game === "AVIATOR") {
      if (gameStatus !== "crashed") return null;
      const crash = Number(row.crash_point);
      if (!Number.isFinite(crash) || crash < 1) return null;
      return { period: "Round " + String(row.round_index == null ? "—" : row.round_index),
        result: "Crash point " + crash.toFixed(2) + "×",
        time: fmtTime(row.crashed_at || row.crashes_at), sort: Number(row.round_index) || 0 };
    }
    if (gameStatus !== "settled") return null;

    if (["K3", "5D", "TRX"].includes(game)) {
      const outcome = row.result || row.outcome || {};
      const period = String(row.period || "");
      if (!period) return null;
      if (game === "K3") {
        const dice = asRows(outcome.dice).map(Number), sum = Number(outcome.sum);
        if (dice.length !== 3 || dice.some(n => !Number.isInteger(n) || n < 1 || n > 6) || !Number.isFinite(sum)) return null;
        return { period, result: "Dice " + dice.join(" · ") + "  |  Sum " + sum + "  |  " + String(outcome.size || "—") + " / " + String(outcome.parity || "—"),
          time: fmtTime(row.settled_at || row.ends_at), sort: Number(row.round_slot) || Date.parse(row.starts_at) || 0 };
      }
      const digits = asRows(outcome.digits).map(Number), sum = Number(outcome.sum);
      if (digits.length !== 5 || digits.some(n => !Number.isInteger(n) || n < 0 || n > 9) || !Number.isFinite(sum)) return null;
      if (game === "5D") {
        return { period, result: "Digits " + digits.join(" · ") + "  |  Sum " + sum + "  |  " + String(outcome.size || "—") + " / " + String(outcome.parity || "—"),
          time: fmtTime(row.settled_at || row.ends_at), sort: Number(row.round_slot) || Date.parse(row.starts_at) || 0 };
      }
      const color = String(outcome.color || outcome.colorName || "—").toUpperCase();
      return { period, result: "Digits " + digits.join(" · ") + "  |  Last " + String(outcome.last_digit == null ? digits[4] : outcome.last_digit) + "  |  " + color + " / " + String(outcome.size || "—"),
        time: fmtTime(row.settled_at || row.ends_at), sort: Number(row.round_slot) || Date.parse(row.starts_at) || 0 };
    }

    if (game === "WINGO") {
      const outcome = row.outcome || {}, number = Number(outcome.number);
      if (!Number.isInteger(number) || number < 0 || number > 9 || !row.period) return null;
      const color = String(outcome.colorName || outcome.color || "—").toUpperCase();
      return { period: String(row.period), result: "Number " + number + "  |  " + color + " / " + String(outcome.size || "—"),
        time: fmtTime(row.settled_at || row.ends_at), sort: Number(row.round_index) || Date.parse(row.starts_at) || 0 };
    }

    if (game === "MOTO") {
      const outcome = asRows(row.outcome).map(Number);
      if (outcome.length !== 10 || outcome.some(n => !Number.isInteger(n) || n < 1 || n > 10) || !row.period) return null;
      return { period: String(row.period), result: "Top 3: Bike " + outcome.slice(0, 3).join(" · Bike ") + "  |  10-bike finish recorded",
        time: fmtTime(row.settled_at || row.ends_at), sort: Date.parse(row.settled_at || row.starts_at) || Number(row.round_index) || 0 };
    }
    return null;
  }

  async function requestRows() {
    const auth = window.NPlusAuth, client = auth && auth.client;
    if (!client) throw new Error("Authentication client is not ready. Refresh after signing in.");
    if (typeof auth.current === "function") {
      const user = await auth.current();
      if (!user || !user.id) throw new Error("Sign in to see server-settled game history.");
    }
    if (["K3", "5D", "TRX"].includes(game)) {
      const response = await client.rpc("nplus_demo_lottery_snapshot", {
        p_game_key: game, p_duration_seconds: game === "TRX" ? 60 : activeDuration()
      });
      if (response.error) throw response.error;
      return asRows(response.data && response.data.history).map(normalizeRow).filter(Boolean).sort((a,b) => b.sort-a.sort);
    }
    if (game === "WINGO") {
      const response = await client.rpc("nplus_wingo_demo_history", { p_duration_seconds: activeDuration(), p_limit: 100 });
      if (response.error) throw response.error;
      return asRows(response.data).map(normalizeRow).filter(Boolean).sort((a,b) => b.sort-a.sort);
    }
    if (game === "AVIATOR") {
      const response = await client.rpc("nplus_aviator_demo_history", { p_limit: 100 });
      if (response.error) throw response.error;
      return asRows(response.data).map(normalizeRow).filter(Boolean).sort((a,b) => b.sort-a.sort);
    }
    const response = await client.rpc("nplus_moto_demo_history", { p_limit: 100 });
    if (response.error) throw response.error;
    return asRows(response.data).map(normalizeRow).filter(Boolean).sort((a,b) => b.sort-a.sort);
  }

  function renderRows(rows) {
    list.replaceChildren();
    if (!rows.length) {
      list.appendChild(make("div", "nph-empty", "No settled rounds returned for this game and duration yet. Open-round results are not shown."));
      status.textContent = "SYNCED · 0 SETTLED ROUNDS";
      return;
    }
    rows.slice(0, 8).forEach((row, index) => {
      const article = make("article", "nph-row" + (index === 0 ? " nph-row-latest" : ""));
      const main = make("div", "nph-main");
      main.appendChild(make("div", "nph-period", (index === 0 ? "LATEST · " : "") + row.period));
      main.appendChild(make("div", "nph-result", row.result));
      article.append(main, make("time", "nph-time", row.time));
      list.appendChild(article);
    });
    status.textContent = "SYNCED · " + rows.length + " SETTLED ROUNDS";
  }

  async function refresh() {
    if (busy || !root) return;
    busy = true; refreshButton.disabled = true; status.textContent = "SYNCING SERVER HISTORY…";
    try { renderRows(await requestRows()); }
    catch (error) {
      console.error("N+ PLAY settled history load failed (" + game + "):", error);
      list.replaceChildren(make("div", "nph-empty", (error && error.message) || "Server history is temporarily unavailable. Tap Refresh to retry."));
      status.textContent = "HISTORY UNAVAILABLE";
    } finally { busy = false; refreshButton.disabled = false; }
  }

  function start() {
    mount(); void refresh();
    window.setInterval(() => { if (!document.hidden) void refresh(); }, 5000);
    window.addEventListener("focus", () => void refresh());
    window.addEventListener("pageshow", () => void refresh());
    document.addEventListener("visibilitychange", () => { if (!document.hidden) void refresh(); });
    document.querySelectorAll(".mode").forEach(el => el.addEventListener("click", () => { window.setTimeout(() => void refresh(), 150); }));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();
