/* N+ PLAY — server-settled history for every demo game and central Activity.
   Reads authenticated server history only. It never writes bets or wallets.
   Open/current round outcomes are never displayed. */
(() => {
  "use strict";
  const page = (location.pathname.split("/").pop() || "").toLowerCase();
  const gameByPage = {
    "k3.html": "K3", "5d.html": "5D", "trx-wingo.html": "TRX",
    "wingo.html": "WINGO", "aviator.html": "AVIATOR", "motorace.html": "MOTO",
    "activity.html": "ALL"
  };
  const game = gameByPage[page];
  if (!game) return;
  const games = ["K3", "5D", "TRX", "WINGO", "AVIATOR", "MOTO"];
  const defaults = { K3: 60, "5D": 60, TRX: 60, WINGO: 30 };
  let root, list, status, title, refreshButton, busy = false;

  const style = document.createElement("style");
  style.textContent = [
    ".nph-card{margin:14px 0;padding:12px;border:1px solid rgba(201,165,91,.22);border-radius:15px;background:linear-gradient(145deg,rgba(28,27,21,.98),rgba(12,14,12,.98));color:#f4f1e8}",
    ".nph-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:8px}",
    ".nph-title{font-size:10px;font-weight:950;letter-spacing:1.1px;color:#e7d6ad}",
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
    const existing = document.getElementById("nplusServerRoundHistory");
    if (existing) {
      root = existing;
      status = root.querySelector(".nph-status");
      title = root.querySelector(".nph-title");
      refreshButton = root.querySelector(".nph-refresh");
      list = root.querySelector(".nph-list");
      return;
    }
    root = make("section", "nph-card");
    root.id = "nplusServerRoundHistory";
    root.setAttribute("aria-label", "Latest server-settled demo rounds");
    const head = make("div", "nph-head");
    const titleWrap = make("div", "");
    title = make("div", "nph-title", game === "ALL" ? "LATEST SETTLED ROUNDS · ALL SIX GAMES" : "LAST SETTLED ROUNDS");
    titleWrap.appendChild(title);
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
    // Keep each game panel at the end of game content; place Activity history before its footer.
    const gameMain = document.querySelector("main");
    const footer = game === "ALL" && gameMain ? gameMain.querySelector("footer") : null;
    if (game === "ALL" && footer && gameMain) gameMain.insertBefore(root, footer);
    else if (gameMain) gameMain.appendChild(root);
    else document.body.appendChild(root);
  }

  function activeDuration(targetGame) {
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
    return defaults[targetGame] || 60;
  }

  function parseValue(value) {
    if (typeof value !== "string") return value;
    try { return JSON.parse(value); } catch (_) { return value; }
  }

  function asRows(value) {
    value = parseValue(value);
    if (Array.isArray(value)) return value;
    if (value && Array.isArray(value.rows)) return value.rows;
    if (value && Array.isArray(value.data)) return value.data;
    if (value && Array.isArray(value.history)) return value.history;
    return [];
  }

  function fmtTime(value) {
    const parsed = value ? Date.parse(value) : NaN;
    if (!Number.isFinite(parsed)) return "Time unavailable";
    return new Date(parsed).toLocaleString("en-IN", {
      day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false
    });
  }

  function timeSort(row) {
    return Date.parse(row.settled_at || row.crashed_at || row.crashes_at || row.ends_at || row.starts_at || "") || 0;
  }

  function normalizeRow(row, targetGame) {
    if (!row || typeof row !== "object") return null;
    const gameStatus = String(row.status || "").toLowerCase();
    const outcome = parseValue(row.result != null ? row.result : row.outcome);
    const period = String(row.period || row.round_index || row.round_slot || "");
    const sortIndex = Number(targetGame === "K3" || targetGame === "5D" || targetGame === "TRX" ? row.round_slot : row.round_index) || 0;
    const settledTime = row.settled_at || row.crashed_at || row.crashes_at || row.ends_at || row.starts_at;
    const displayPeriod = period
      ? (window.NPlusPeriodDisplay && typeof window.NPlusPeriodDisplay.forGame === "function"
        ? window.NPlusPeriodDisplay.forGame(targetGame, period)
        : targetGame + "-" + period)
      : targetGame + "-Round-unavailable";
    const common = {
      game: targetGame, period: displayPeriod,
      time: fmtTime(settledTime), timeSort: timeSort(row), sortIndex
    };

    if (targetGame === "AVIATOR") {
      if (gameStatus !== "crashed") return null;
      const crash = Number(row.crash_point);
      common.period = window.NPlusPeriodDisplay && typeof window.NPlusPeriodDisplay.aviatorRound === "function"
        ? window.NPlusPeriodDisplay.aviatorRound(row.round_index, row.round_id)
        : "AV-" + String(row.round_index == null ? "—" : row.round_index);
      common.result = Number.isFinite(crash) && crash >= 1
        ? "Crash point " + crash.toFixed(2) + "×"
        : "Recorded crash · result unavailable";
      return common;
    }
    if (gameStatus !== "settled") return null;
    if (!period) return null;

    if (targetGame === "K3") {
      const dice = asRows(outcome && outcome.dice).map(Number);
      if (dice.length !== 3 || dice.some(n => !Number.isInteger(n) || n < 1 || n > 6)) {
        common.result = "Settled round · result unavailable";
      } else {
        const sum = Number.isFinite(Number(outcome.sum)) ? Number(outcome.sum) : dice.reduce((a, n) => a + n, 0);
        common.result = "Dice " + dice.join(" · ") + "  |  Sum " + sum + "  |  "
          + String(outcome.size || "—") + " / " + String(outcome.parity || "—");
      }
      return common;
    }

    if (targetGame === "5D" || targetGame === "TRX") {
      const digits = asRows(outcome && outcome.digits).map(Number);
      if (digits.length !== 5 || digits.some(n => !Number.isInteger(n) || n < 0 || n > 9)) {
        common.result = "Settled round · result unavailable";
        return common;
      }
      const sum = Number.isFinite(Number(outcome.sum)) ? Number(outcome.sum) : digits.reduce((a, n) => a + n, 0);
      if (targetGame === "5D") {
        common.result = "Digits " + digits.join(" · ") + "  |  Sum " + sum + "  |  "
          + String(outcome.size || "—") + " / " + String(outcome.parity || "—");
      } else {
        const color = String(outcome.color || outcome.colorName || "—").toUpperCase();
        const last = outcome.last_digit == null ? digits[4] : outcome.last_digit;
        common.result = "Digits " + digits.join(" · ") + "  |  Last " + String(last) + "  |  "
          + color + " / " + String(outcome.size || "—");
      }
      return common;
    }

    if (targetGame === "WINGO") {
      const number = Number(outcome && outcome.number);
      if (!Number.isInteger(number) || number < 0 || number > 9) {
        common.result = "Settled round · result unavailable";
      } else {
        const color = String(outcome.colorName || outcome.color || "—").toUpperCase();
        common.result = "Number " + number + "  |  " + color + " / " + String(outcome.size || "—");
      }
      return common;
    }

    if (targetGame === "MOTO") {
      const ranking = asRows(outcome).map(Number);
      if (ranking.length !== 10 || ranking.some(n => !Number.isInteger(n) || n < 1 || n > 10)) {
        common.result = "Settled round · result unavailable";
      } else {
        common.result = "Top 3: Bike " + ranking.slice(0, 3).join(" · Bike ") + "  |  10-bike finish recorded";
      }
      return common;
    }
    return null;
  }

  async function fetchGameRows(client, targetGame) {
    let response, rawRows;
    if (["K3", "5D", "TRX"].includes(targetGame)) {
      response = await client.rpc("nplus_demo_lottery_snapshot", {
        p_game_key: targetGame,
        p_duration_seconds: targetGame === "TRX" ? 60 : activeDuration(targetGame)
      });
      if (response.error) throw response.error;
      const data = parseValue(response.data);
      rawRows = asRows(data && data.history);
    } else if (targetGame === "WINGO") {
      response = await client.rpc("nplus_wingo_demo_history", {
        p_duration_seconds: activeDuration(targetGame), p_limit: 100
      });
      if (response.error) throw response.error;
      rawRows = asRows(response.data);
    } else if (targetGame === "AVIATOR") {
      response = await client.rpc("nplus_aviator_demo_history", { p_limit: 100 });
      if (response.error) throw response.error;
      rawRows = asRows(response.data);
    } else {
      response = await client.rpc("nplus_moto_demo_history", { p_limit: 100 });
      if (response.error) throw response.error;
      rawRows = asRows(response.data);
    }
    return rawRows.map(row => normalizeRow(row, targetGame)).filter(Boolean)
      .sort((a, b) => b.sortIndex - a.sortIndex || b.timeSort - a.timeSort);
  }

  async function requestRows() {
    const auth = window.NPlusAuth, client = auth && auth.client;
    if (!client || typeof client.rpc !== "function") {
      throw new Error("Authentication client is not ready. Refresh after signing in.");
    }
    if (typeof auth.current === "function") {
      const user = await auth.current();
      if (!user || !user.id) throw new Error("Sign in to see server-settled game history.");
    }
    if (game !== "ALL") return { rows: await fetchGameRows(client, game), failed: [] };

    const results = await Promise.all(games.map(async targetGame => {
      try { return { game: targetGame, rows: await fetchGameRows(client, targetGame), error: null }; }
      catch (error) { return { game: targetGame, rows: [], error }; }
    }));
    const failed = results.filter(item => item.error).map(item => item.game);
    const rows = results.flatMap(item => item.rows.slice(0, 8).map((row, index) => ({
      ...row, latestForGame: index === 0
    }))).sort((a, b) => b.timeSort - a.timeSort || b.sortIndex - a.sortIndex);
    return { rows, failed };
  }

  function renderRows(rows, failed) {
    list.replaceChildren();
    failed = failed || [];
    if (failed.length) {
      list.appendChild(make("div", "nph-empty", "Some game histories are unavailable: " + failed.join(", ") + ". The displayed rows are verified server responses; tap Refresh to retry."));
    }
    if (!rows.length) {
      list.appendChild(make("div", "nph-empty", game === "ALL"
        ? "No settled results could be loaded. Open-round results stay hidden; tap Refresh to retry."
        : "No settled rounds returned for this game and duration yet. Open-round results are not shown."));
      status.textContent = failed.length ? "HISTORY UNAVAILABLE" : "SYNCED · 0 SETTLED ROUNDS";
      return;
    }
    const visible = game === "ALL" ? rows : rows.slice(0, 8);
    visible.forEach((row, index) => {
      const latest = game === "ALL" ? Boolean(row.latestForGame) : index === 0;
      const article = make("article", "nph-row" + (latest ? " nph-row-latest" : ""));
      const main = make("div", "nph-main");
      const label = game === "ALL" ? row.game + (latest ? " · LATEST · " : " · ") : (latest ? "LATEST · " : "");
      main.appendChild(make("div", "nph-period", label + row.period));
      main.appendChild(make("div", "nph-result", row.result));
      article.append(main, make("time", "nph-time", row.time));
      list.appendChild(article);
    });
    if (game === "ALL") {
      status.textContent = failed.length
        ? "PARTIAL · " + (games.length - failed.length) + "/6 GAMES · " + rows.length + " SETTLED ROUNDS"
        : "SYNCED · 6 GAMES · " + rows.length + " SETTLED ROUNDS";
    } else {
      status.textContent = "SYNCED · " + visible.length + " SETTLED ROUNDS";
    }
  }

  async function refresh() {
    if (busy || !root) return;
    busy = true;
    refreshButton.disabled = true;
    status.textContent = "SYNCING SERVER HISTORY…";
    try {
      const result = await requestRows();
      renderRows(result.rows, result.failed);
    } catch (error) {
      console.error("N+ PLAY settled history load failed (" + game + "):", error);
      list.replaceChildren(make("div", "nph-empty", (error && error.message) || "Server history is temporarily unavailable. Tap Refresh to retry."));
      status.textContent = "HISTORY UNAVAILABLE";
    } finally {
      busy = false;
      refreshButton.disabled = false;
    }
  }

  function start() {
    mount();
    void refresh();
    window.setInterval(() => { if (!document.hidden) void refresh(); }, 5000);
    window.addEventListener("focus", () => void refresh());
    window.addEventListener("pageshow", () => void refresh());
    document.addEventListener("visibilitychange", () => { if (!document.hidden) void refresh(); });
    document.querySelectorAll(".mode").forEach(el => el.addEventListener("click", () => {
      window.setTimeout(() => void refresh(), 150);
    }));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();