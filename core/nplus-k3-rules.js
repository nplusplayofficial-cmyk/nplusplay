/* N+ PLAY K3 selection catalogue.
   Gross multipliers are derived from the exact outcomes of three fair six-sided dice.
   Multipliers include the original stake and apply to virtual/demo credits only. */
(function (root) {
  "use strict";
  const SUM_WAYS = Object.freeze({
    3: 1, 4: 3, 5: 6, 6: 10, 7: 15, 8: 21,
    9: 25, 10: 27, 11: 27, 12: 25, 13: 21,
    14: 15, 15: 10, 16: 6, 17: 3, 18: 1
  });

  function grossMultiplier(type, value) {
    const kind = String(type || "").toLowerCase();
    const pick = String(value == null ? "" : value).toUpperCase();
    if (kind === "size" || kind === "parity") return 2;
    if (kind === "sum" && Object.prototype.hasOwnProperty.call(SUM_WAYS, pick)) {
      return 216 / SUM_WAYS[pick];
    }
    if (kind === "single" && /^[1-6]$/.test(pick)) return 216 / 91;
    if (kind === "double" && pick === "ANY") return 216 / 96;
    if (kind === "double" && /^[1-6]$/.test(pick)) return 216 / 16;
    if (kind === "triple" && pick === "ANY") return 216 / 6;
    if (kind === "triple" && /^[1-6]$/.test(pick)) return 216;
    if (kind === "different" && pick === "ALL") return 216 / 120;
    return 0;
  }

  function formatMultiplier(type, value) {
    const amount = grossMultiplier(type, value);
    return amount > 0 ? amount.toFixed(2) + "×" : "—";
  }

  function sumOptions() {
    return Object.keys(SUM_WAYS).map(Number);
  }

  root.NPlusK3Rules = Object.freeze({ SUM_WAYS, grossMultiplier, formatMultiplier, sumOptions });
})(window);
