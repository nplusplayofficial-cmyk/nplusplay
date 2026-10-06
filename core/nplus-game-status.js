(() => {
  "use strict";

  async function getClient() {
    const client =
      window.NPlusAuth?.client ||
      window.supabaseClient;

    if (!client) {
      throw new Error("Supabase client unavailable.");
    }

    return client;
  }

  async function getGameStatus(gameKey) {
    const client = await getClient();

    const key = String(gameKey || "").trim().toUpperCase();

    if (!key) {
      throw new Error("Game key is required.");
    }

    const { data, error } = await client
      .from("game_settings")
      .select("game_key,game_name,enabled")
      .eq("game_key", key)
      .maybeSingle();

    if (error) {
      console.error("Game status error:", error);
      throw error;
    }

    return data || null;
  }

  async function getAllGameStatus() {
    const client = await getClient();

    const { data, error } = await client
      .from("game_settings")
      .select("game_key,game_name,enabled")
      .order("game_name", {
        ascending: true
      });

    if (error) {
      console.error("Game status error:", error);
      throw error;
    }

    return data || [];
  }

  async function isGameEnabled(gameKey) {
    const game = await getGameStatus(gameKey);

    // If the game is not configured yet,
    // keep the existing game working.
    if (!game) {
      return true;
    }

    return game.enabled === true;
  }

  window.NPlusGameStatus = {
    getGameStatus,
    getAllGameStatus,
    isGameEnabled
  };
})();
