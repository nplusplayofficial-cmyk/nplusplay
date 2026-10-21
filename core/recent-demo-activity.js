(() => {
  "use strict";

  const container = document.getElementById("recentDemoActivityRows");
  if (!container) return;

  const games = {
    WINGO: "WINGO",
    MOTORACE: "MotoRace",
    AVIATOR: "Aviator"
  };

  let loading = false;

  function renderMessage(title, detail) {
    container.replaceChildren();

    const item = document.createElement("div");
    item.className = "champion";

    const player = document.createElement("div");
    player.className = "player";
    player.appendChild(document.createTextNode(title));

    const small = document.createElement("small");
    small.textContent = detail;

    player.appendChild(small);
    item.appendChild(player);
    container.appendChild(item);
  }

  async function refreshActivity() {
    if (loading) return;

    const client = window.NPlusAuth?.client;

    if (!client || typeof client.rpc !== "function") {
      renderMessage(
        "Recent activity unavailable",
        "The verified server feed is not connected. No sample activity is shown."
      );
      return;
    }

    loading = true;

    try {
      const { data, error } = await client.rpc(
        "nplus_recent_demo_activity",
        { p_window_minutes: 60 }
      );

      if (error) throw error;

      const rows = Array.isArray(data)
        ? data.filter(row => {
            const key = String(row?.game_key || "").toUpperCase();
            const count = Number(row?.activity_count);

            return Object.prototype.hasOwnProperty.call(games, key)
              && Number.isSafeInteger(count)
              && count > 0;
          }).slice(0, 3)
        : [];

      container.replaceChildren();

      if (rows.length === 0) {
        renderMessage(
          "No verified recent activity yet",
          "No server-recorded demo bets in the last 60 minutes."
        );
        return;
      }

      rows.forEach(row => {
        const key = String(row.game_key).toUpperCase();
        const count = Number(row.activity_count);

        const item = document.createElement("div");
        item.className = "champion";

        const player = document.createElement("div");
        player.className = "player";
        player.appendChild(document.createTextNode(games[key]));

        const small = document.createElement("small");
        small.textContent =
          count + " demo bet" + (count === 1 ? "" : "s")
          + " recorded in the last 60 minutes";

        player.appendChild(small);
        item.appendChild(player);
        container.appendChild(item);
      });
    } catch (error) {
      console.warn("N+ PLAY recent activity feed unavailable:", error);

      renderMessage(
        "Recent activity unavailable",
        "The server-backed feed could not be verified. No sample activity is shown."
      );
    } finally {
      loading = false;
    }
  }

  void refreshActivity();

  window.addEventListener("focus", () => {
    void refreshActivity();
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) void refreshActivity();
  });

  window.setInterval(() => {
    void refreshActivity();
  }, 60000);
})();
