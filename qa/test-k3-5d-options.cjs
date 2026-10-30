#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "core/nplus-k3-rules.js"), "utf8");
const context = { window: {} };
vm.runInNewContext(source, context, { filename: "core/nplus-k3-rules.js" });
const rules = context.window.NPlusK3Rules;

assert.deepEqual(Array.from(rules.sumOptions()), Array.from({ length: 16 }, (_, i) => i + 3));
assert.equal(rules.grossMultiplier("size", "BIG"), 2);
assert.equal(rules.grossMultiplier("parity", "EVEN"), 2);
assert.equal(rules.grossMultiplier("sum", "3"), 216);
assert.equal(rules.grossMultiplier("sum", "4"), 72);
assert.equal(rules.grossMultiplier("sum", "10"), 8);
assert.equal(rules.grossMultiplier("sum", "18"), 216);
assert.ok(Math.abs(rules.grossMultiplier("single", "1") - 216 / 91) < 1e-12);
assert.equal(rules.grossMultiplier("double", "ANY"), 2.25);
assert.equal(rules.grossMultiplier("double", "6"), 13.5);
assert.equal(rules.grossMultiplier("triple", "ANY"), 36);
assert.equal(rules.grossMultiplier("triple", "1"), 216);
assert.equal(rules.grossMultiplier("different", "ALL"), 1.8);
assert.equal(rules.grossMultiplier("sum", "2"), 0);
assert.equal(rules.grossMultiplier("single", "7"), 0);
assert.equal(rules.grossMultiplier("double", "7"), 0);
assert.equal(rules.formatMultiplier("sum", "3"), "216.00×");

const k3 = fs.readFileSync(path.join(root, "k3.html"), "utf8");
assert.ok(k3.includes('core/nplus-k3-rules.js?v=20261030-k3-full-options'), "K3 loads the exact-odds rules");
assert.ok(k3.includes('data-type="sum"'), "K3 offers exact sum selections");
assert.ok(k3.includes('data-type="single"'), "K3 offers single-die number picks");
assert.ok(k3.includes('data-type="double"'), "K3 offers pair picks");
assert.ok(k3.includes('data-type="triple"'), "K3 offers triple picks");
assert.ok(k3.includes('data-type="different"'), "K3 offers all-different pick");
assert.ok(k3.includes('NPlusK3Rules.grossMultiplier('), "K3 displays the same multipliers that selection UI calculates");
assert.ok(!/Other K3 selections are disabled/i.test(k3), "K3 no longer tells users its additional selections are disabled");

const five = fs.readFileSync(path.join(root, "5d.html"), "utf8");
assert.ok(five.includes('SUM:(BIG|SMALL|ODD|EVEN)'), "5D SUM supports Big/Small/Odd/Even server selections");
assert.ok(five.includes("SUM:"), "5D displays and submits SUM-prefixed selections");
assert.ok(!/SUM betting is disabled|SUM bets are disabled/i.test(five), "5D no longer marks its SUM tab as disabled");

console.log("K3/5D selection tests passed: exact K3 sum odds, single/pair/triple/all-different picks, and 5D total-sum Big/Small/Odd/Even.");
