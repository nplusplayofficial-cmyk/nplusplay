#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "core/nplus-period-display.js"), "utf8");
const context = { window: {} };
vm.runInNewContext(source, context, { filename: "core/nplus-period-display.js" });
const api = context.window.NPlusPeriodDisplay;
assert.ok(api && typeof api.forGame === "function", "period display helper is available");

const sameSlot = "29888366";
const displayed = [
  api.forGame("K3", "202610300056-K3-60-" + sameSlot),
  api.forGame("5D", "202610300056-5D-60-" + sameSlot),
  api.forGame("TRX", "202610300056-TRX-60-" + sameSlot),
  api.forGame("WINGO", "202610302000" + "88366"),
  api.forGame("MOTO", "202610301927"),
  api.aviatorRound(51825, "aviator-test-id")
];
assert.equal(new Set(displayed).size, 6, "same-time game rounds render as unique IDs across all six games");
assert.deepEqual(displayed.map(id => id.split("-")[0]), ["K3", "D5", "TX", "WG", "MR", "AV"]);
assert.equal(api.forGame("K3", "202610300056-K3-60-29888366"), "K3-202610300056-60-29888366");
assert.equal(api.forGame("5D", "202610300056-5D-60-29888366"), "D5-202610300056-60-29888366");
assert.equal(api.forGame("TRX", "202610300056-TRX-60-29888366"), "TX-202610300056-60-29888366");
assert.equal(api.forGame("WINGO", "20261030200088366"), "WG-20261030200088366");
assert.equal(api.forGame("MOTO", "202610301927"), "MR-202610301927");
assert.equal(api.aviatorRound(51825, "unused"), "AV-00051825");
assert.equal(api.aviatorRound(null, "aviator-test-id"), "AV-aviator-test-id");
assert.equal(api.forGame("K3", "—"), "—", "unavailable value is not disguised as a round ID");

const contracts = [
  ["k3.html", 'NPlusPeriodDisplay.forGame("K3"'],
  ["5d.html", "NPlusPeriodDisplay.forGame('5D'"],
  ["trx-wingo.html", "NPlusPeriodDisplay.forGame('TRX'"],
  ["wingo.html", 'NPlusPeriodDisplay.forGame("WINGO"'],
  ["motorace.html", 'NPlusPeriodDisplay.forGame("MOTO"'],
  ["aviator.html", "NPlusPeriodDisplay.aviatorRound("],
  ["activity.html", "NPlusPeriodDisplay.forGame(targetGame, period)"]
];
for (const [file, token] of contracts) {
  const html = fs.readFileSync(path.join(root, file), "utf8");
  assert.ok(html.includes('core/nplus-period-display.js?v=20261030-unique-periods'),
    file + " loads the display-only period helper");
  assert.ok(html.includes(token), file + " renders a game-specific unique period ID");
}
console.log("Round-period uniqueness tests passed: six disjoint game prefixes, Aviator sequence IDs, unavailable-state handling, all game-page and Activity integrations.");
