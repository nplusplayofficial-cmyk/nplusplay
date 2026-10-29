/* N+ PLAY — collision-free, user-facing period identifiers.
   Display-only: never send these labels to the settlement RPCs or persist them as keys. */
(function (root) {
  "use strict";
  const PREFIX = Object.freeze({
    K3: "K3",
    "5D": "5D",
    TRX: "TRX",
    WINGO: "WINGO",
    MOTO: "MOTO",
    AVIATOR: "AVIATOR"
  });

  function forGame(game, rawPeriod) {
    const key = String(game || "").toUpperCase();
    const prefix = PREFIX[key];
    const raw = rawPeriod == null ? "" : String(rawPeriod).trim();
    if (!raw || raw === "—") return raw || "—";
    if (!prefix) throw new Error("Unknown N+ PLAY game key: " + key);

    let period = raw;
    if (key === "K3") period = period.replace(/-K3-/g, "-");
    if (key === "5D") period = period.replace(/-5D-/g, "-");
    if (key === "TRX") period = period.replace(/-TRX-/g, "-");
    return prefix + "-" + period;
  }

  function aviatorRound(roundIndex, fallbackId) {
    const index = Number(roundIndex);
    const raw = Number.isSafeInteger(index) && index >= 0
      ? String(index).padStart(8, "0")
      : String(fallbackId || "unavailable");
    return forGame("AVIATOR", raw);
  }

  root.NPlusPeriodDisplay = Object.freeze({ forGame, aviatorRound });
})(window);
