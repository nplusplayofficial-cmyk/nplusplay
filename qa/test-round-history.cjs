#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourceRoot = path.resolve(__dirname, "..");
const historySource = fs.readFileSync(path.join(sourceRoot, "core/nplus-round-history.js"), "utf8");
const workerSource = fs.readFileSync(path.join(sourceRoot, "sw.js"), "utf8");

class FakeElement {
  constructor(tagName, ownerDocument) {
    this.tagName = String(tagName || "").toUpperCase();
    this.ownerDocument = ownerDocument;
    this.children = [];
    this.dataset = {};
    this.listeners = {};
    this.attributes = {};
    this.className = "";
    this.id = "";
    this.type = "";
    this.disabled = false;
    this.parentNode = null;
    this._text = "";
  }
  set textContent(value) {
    this._text = String(value == null ? "" : value);
    this.children = [];
  }
  get textContent() {
    return this._text + this.children.map(child => child.textContent).join("");
  }
  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    if (this.ownerDocument) this.ownerDocument.register(child);
    return child;
  }
  append(...children) { children.forEach(child => this.appendChild(child)); }
  replaceChildren(...children) {
    this.children = [];
    this._text = "";
    children.forEach(child => this.appendChild(child));
  }
  insertBefore(child, before) {
    const index = this.children.indexOf(before);
    if (index < 0) return this.appendChild(child);
    child.parentNode = this;
    this.children.splice(index, 0, child);
    if (this.ownerDocument) this.ownerDocument.register(child);
    return child;
  }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  addEventListener(name, callback) {
    if (!this.listeners[name]) this.listeners[name] = [];
    this.listeners[name].push(callback);
  }
  querySelector(selector) {
    const wantedClass = selector.startsWith(".") ? selector.slice(1) : null;
    const wantedTag = wantedClass ? null : selector.toUpperCase();
    for (const child of this.children) {
      if (wantedClass && String(child.className).split(/\s+/).includes(wantedClass)) return child;
      if (wantedTag && child.tagName === wantedTag) return child;
      const nested = child.querySelector(selector);
      if (nested) return nested;
    }
    return null;
  }
}

class FakeDocument {
  constructor(pathname, duration) {
    this.readyState = "complete";
    this.hidden = false;
    this.ids = new Map();
    this.head = new FakeElement("head", this);
    this.body = new FakeElement("body", this);
    this.main = new FakeElement("main", this);
    this.footer = new FakeElement("footer", this);
    this.mode = null;
    if (pathname.endsWith("activity.html")) this.main.appendChild(this.footer);
    if (duration) {
      this.mode = new FakeElement("button", this);
      this.mode.className = "mode active";
      this.mode.dataset.sec = String(duration);
      this.mode.textContent = String(duration) + " SEC";
    }
  }
  register(element) {
    if (element.id) this.ids.set(element.id, element);
    for (const child of element.children) this.register(child);
  }
  createElement(tagName) { return new FakeElement(tagName, this); }
  getElementById(id) { return this.ids.get(id) || null; }
  querySelector(selector) {
    if (selector === "main") return this.main;
    if (selector === "footer") return this.footer;
    if (selector.startsWith(".mode") || selector.startsWith("[data-sec]")) return this.mode;
    return null;
  }
  querySelectorAll(selector) {
    if (selector === ".mode") return this.mode ? [this.mode] : [];
    return [];
  }
  addEventListener() {}
}

function isoMinutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}
function lotteryRow(game, slot, status, ageMinutes) {
  const outcome = game === "K3"
    ? { dice: [4, 2, 1], sum: 7, size: "SMALL", parity: "ODD" }
    : game === "5D"
      ? { digits: [1, 2, 3, 4, 5], sum: 15, size: "SMALL", parity: "ODD" }
      : { digits: [1, 8, 0, 3, 7], sum: 19, last_digit: 7, color: "GREEN", size: "BIG", parity: "ODD" };
  const starts = isoMinutesAgo(ageMinutes);
  return {
    period: game + "-" + slot, round_slot: slot, starts_at: starts,
    ends_at: starts, settled_at: starts, status, result: outcome
  };
}
function rowFor(game, roundIndex, status, ageMinutes) {
  const starts = isoMinutesAgo(ageMinutes);
  if (game === "WINGO") {
    return { period: "W-" + roundIndex, round_index: roundIndex, starts_at: starts,
      ends_at: starts, settled_at: starts, status,
      outcome: { number: 8, color: "red", colorName: "RED", size: "Big" } };
  }
  if (game === "AVIATOR") {
    return { round_id: "aviator-" + roundIndex, round_index: roundIndex,
      flight_starts_at: starts, crashes_at: starts, crashed_at: starts,
      status, crash_point: 1.42 };
  }
  const ranking = [7, 3, 8, 6, 9, 10, 4, 2, 1, 5];
  return { period: "M-" + roundIndex, round_index: roundIndex, starts_at: starts,
    ends_at: starts, settled_at: starts, status, outcome: JSON.stringify(ranking) };
}
function fixtureFor(name, args, options) {
  if (options.empty) {
    if (name === "nplus_demo_lottery_snapshot") return { data: { history: [] }, error: null };
    if (name === "nplus_wingo_demo_history" && args.p_duration_seconds === 30) return { data: [], error: null };
    if (name === "nplus_aviator_demo_history") return { data: [], error: null };
    if (name === "nplus_moto_demo_history") return { data: [], error: null };
  }
  if (options.failRPC === name) return { data: null, error: { message: "Simulated " + name + " error" } };
  if (name === "nplus_demo_lottery_snapshot") {
    const game = args.p_game_key;
    const rows = [
      lotteryRow(game, 101, "settled", 2),
      lotteryRow(game, 102, "settled", 1),
      lotteryRow(game, 103, "open", 0)
    ];
    return { data: { history: rows }, error: null };
  }
  if (name === "nplus_wingo_demo_history") {
    return { data: [
      rowFor("WINGO", 41, "settled", 2),
      rowFor("WINGO", 42, "settled", 1),
      rowFor("WINGO", 43, "open", 0)
    ], error: null };
  }
  if (name === "nplus_aviator_demo_history") {
    return { data: [
      rowFor("AVIATOR", 87, "crashed", 2),
      rowFor("AVIATOR", 88, "crashed", 1),
      rowFor("AVIATOR", 89, "flying", 0)
    ], error: null };
  }
  if (name === "nplus_moto_demo_history") {
    return { data: [
      rowFor("MOTO", 51, "settled", 2),
      rowFor("MOTO", 52, "settled", 1),
      rowFor("MOTO", 53, "open", 0)
    ], error: null };
  }
  throw new Error("Unexpected RPC: " + name);
}
async function makePage(pageName, options = {}) {
  const pathname = "/nplusplay/" + pageName;
  const duration = options.duration || null;
  const document = new FakeDocument(pathname, duration);
  const calls = [];
  const loggedErrors = [];
  const client = {
    async rpc(name, args) {
      calls.push({ name, args });
      return fixtureFor(name, args || {}, options);
    }
  };
  const window = {
    NPlusAuth: { client },
    addEventListener() {},
    setInterval() { return 1; },
    setTimeout(callback) { callback(); return 1; }
  };
  const context = {
    document, window, location: { pathname },
    console: { error(...args) { loggedErrors.push(args.map(String).join(" ")); }, warn() {} }
  };
  vm.runInNewContext(historySource, context, { filename: "core/nplus-round-history.js" });
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  const root = document.getElementById("nplusServerRoundHistory");
  assert.ok(root, pageName + " mounted its history panel");
  return {
    document, calls, loggedErrors, root,
    list: root.querySelector(".nph-list"),
    status: root.querySelector(".nph-status"),
    text: root.textContent
  };
}
function articleTexts(page) {
  return page.list.children.filter(child => child.tagName === "ARTICLE").map(child => child.textContent);
}

(async () => {
  for (const [pageName, latestPeriod, previousPeriod, latestResult, rpcName] of [
    ["k3.html", "K3-102", "K3-101", "Dice 4 · 2 · 1", "nplus_demo_lottery_snapshot"],
    ["5d.html", "5D-102", "5D-101", "Digits 1 · 2 · 3 · 4 · 5", "nplus_demo_lottery_snapshot"],
    ["trx-wingo.html", "TRX-102", "TRX-101", "Last 7", "nplus_demo_lottery_snapshot"],
    ["wingo.html", "W-42", "W-41", "Number 8", "nplus_wingo_demo_history"],
    ["aviator.html", "Round 88", "Round 87", "Crash point 1.42", "nplus_aviator_demo_history"],
    ["motorace.html", "M-52", "M-51", "Top 3: Bike 7 · Bike 3 · Bike 8", "nplus_moto_demo_history"]
  ]) {
    const page = await makePage(pageName);
    const articles = articleTexts(page);
    assert.ok(articles.length >= 2, pageName + " includes latest and previous settled rounds");
    assert.ok(articles[0].includes(latestPeriod), pageName + " shows latest settled round first");
    assert.ok(articles[1].includes(previousPeriod), pageName + " shows previous round below latest");
    assert.ok(articles[0].includes(latestResult), pageName + " formats the stored result");
    assert.ok(!page.list.textContent.includes(pageName === "aviator.html" ? "Round 89" : pageName === "wingo.html" ? "W-43" : pageName === "motorace.html" ? "M-53" : pageName === "k3.html" ? "K3-103" : pageName === "5d.html" ? "5D-103" : "TRX-103"), pageName + " hides the unsettled round");
    assert.ok(page.calls.some(call => call.name === rpcName), pageName + " calls the matching history RPC");
    if (pageName === "k3.html") {
      assert.equal(page.calls.find(call => call.name === rpcName).args.p_duration_seconds, 60);
    }
  }

  const switched = await makePage("5d.html", { duration: 180 });
  assert.equal(switched.calls.find(call => call.name === "nplus_demo_lottery_snapshot").args.p_duration_seconds, 180,
    "duration buttons feed the selected server-history duration");

  const empty = await makePage("k3.html", { empty: true });
  assert.match(empty.list.textContent, /No settled rounds returned/);
  assert.match(empty.status.textContent, /0 SETTLED ROUNDS/);

  const failed = await makePage("wingo.html", { failRPC: "nplus_wingo_demo_history" });
  assert.match(failed.status.textContent, /HISTORY UNAVAILABLE/);
  assert.match(failed.list.textContent, /Simulated nplus_wingo_demo_history error/);

  const activity = await makePage("activity.html");
  for (const game of ["K3", "5D", "TRX", "WINGO", "AVIATOR", "MOTO"]) {
    assert.ok(activity.list.textContent.includes(game), "Activity includes " + game + " settled history");
  }
  assert.match(activity.status.textContent, /6 GAMES/);
  assert.ok(articleTexts(activity).length >= 12, "Activity includes current and previous rounds across all six games");

  const partial = await makePage("activity.html", { failRPC: "nplus_wingo_demo_history" });
  assert.match(partial.status.textContent, /PARTIAL/);
  assert.match(partial.list.textContent, /unavailable: WINGO/);
  assert.ok(partial.list.textContent.includes("K3") && partial.list.textContent.includes("AVIATOR"),
    "Activity retains successful game histories when another RPC fails");

  assert.ok(workerSource.includes('const VERSION = "nplus-play-shell-v13"'), "service-worker cache version is bumped");
  assert.ok(!workerSource.includes('"./core/nplus-round-history.js"'), "live history script is not precached");
  assert.ok(workerSource.includes('fetch(req, { cache: "no-store" })'), "history script uses a no-store network fetch");
  assert.ok(workerSource.includes("nplus-round-history\\.js$/i"), "service worker has a history-script-only cache bypass");
  assert.ok(workerSource.includes("nplus-period-display\\.js$/i"), "unique period labels bypass stale PWA cache");

  console.log("Round history runtime tests passed: six game pages, latest-first order, open-round exclusion, formatting, duration switching, empty/error states, Activity all-six coverage, partial failures and stale-cache bypass.");
})().catch(error => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});