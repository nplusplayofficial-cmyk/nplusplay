/* N+ PLAY — shared server-backed game availability badge. */
(function (root) {
  "use strict";
  const LABELS = Object.freeze({
    syncing: "SYNCING",
    live: "LIVE DEMO",
    paused: "PAUSED BY ADMIN",
    offline: "SERVER OFFLINE"
  });

  function resolveState(input) {
    const state = input || {};
    if (state.unavailable === true) return "offline";
    if (state.ready !== true) return "syncing";
    return state.enabled === true ? "live" : "paused";
  }

  function paint(badge, input) {
    if (!badge) return resolveState(input);
    const state = resolveState(input);
    badge.className = "live nplus-live-badge nplus-live-" + state;
    badge.dataset.nplusGameState = state;
    badge.setAttribute("role", "status");
    badge.setAttribute("aria-live", "polite");
    badge.textContent = LABELS[state];
    return state;
  }

  root.NPlusGameLiveStatus = Object.freeze({ resolveState, paint });
})(window);
