#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "core/nplus-game-live-status.js"), "utf8");
const context = { window: {} };
vm.runInNewContext(source, context, { filename: "core/nplus-game-live-status.js" });
const api = context.window.NPlusGameLiveStatus;

assert.equal(api.resolveState({ ready: false }), "syncing");
assert.equal(api.resolveState({ ready: true, enabled: true }), "live");
assert.equal(api.resolveState({ ready: true, enabled: false }), "paused");
assert.equal(api.resolveState({ ready: true, enabled: true, unavailable: true }), "offline");
assert.equal(api.resolveState({ unavailable: true }), "offline");

const badge = {
  className: "",
  dataset: {},
  attributes: {},
  textContent: "",
  setAttribute(key, value) { this.attributes[key] = value; }
};
assert.equal(api.paint(badge, { ready: true, enabled: true }), "live");
assert.equal(badge.textContent, "LIVE DEMO");
assert.equal(badge.dataset.nplusGameState, "live");
assert.equal(badge.attributes["aria-live"], "polite");
assert.equal(api.paint(badge, { ready: true, enabled: false }), "paused");
assert.equal(badge.textContent, "PAUSED BY ADMIN");
assert.equal(api.paint(badge, { unavailable: true }), "offline");
assert.equal(badge.textContent, "SERVER OFFLINE");

const k3 = fs.readFileSync(path.join(root, "k3.html"), "utf8");
assert.ok(k3.includes('id="gameLiveStatus"'), "K3 header badge has a stable ID");
assert.ok(k3.includes('NPlusGameLiveStatus.paint('), "K3 paints the header from the server snapshot");
assert.ok(!/class="live"><i><\/i>PAUSED<\/span>/.test(k3), "K3 no longer ships a hard-coded PAUSED label");

const wingo = fs.readFileSync(path.join(root, "wingo.html"), "utf8");
assert.ok(wingo.includes('id="gameLiveStatus"'), "WINGO header badge has a stable ID");
assert.ok(wingo.includes('NPlusGameLiveStatus.paint('), "WINGO paints the header from its live server round and admin state");
assert.ok(!/class="live"><i><\/i>LIVE<\/span>/.test(wingo), "WINGO no longer ships a hard-coded LIVE label");

for (const page of ["k3.html", "wingo.html"]) {
  const html = page === "k3.html" ? k3 : wingo;
  assert.ok(html.includes('core/nplus-game-live-status.js?v=20261030-live-status'),
    page + " loads the shared live-status helper");
}
console.log("Live status tests passed: syncing, live, admin-paused and server-offline states; K3 and WINGO no longer show static availability.");
