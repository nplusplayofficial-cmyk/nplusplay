(() => {
  "use strict";

  const GAME_STORES = [
    "nplusplay_wingo_ultra_final_v2",
    "nplusplay_k3_wingo_style_v1",
    "nplus_moto_race_clean_v1",
    "nplus_aviator_demo_final_v3",
    "nplus_trxwingo_demo_v2",
    "nplus_5d_final_v5"
  ];

  function getClient() {
    const client = window.NPlusAuth?.client;

    if (!client) {
      throw new Error("Supabase client unavailable.");
    }

    return client;
  }

  async function getUser() {
    if (!window.NPlusAuth?.current) {
      throw new Error("Authentication system unavailable.");
    }

    const user = await window.NPlusAuth.current();

    if (!user?.id) {
      throw new Error("Authentication required.");
    }

    return user;
  }

  async function getBalance() {
    const user = await getUser();
    const client = getClient();

    const { data, error } = await client
      .from("demo_wallets")
      .select("balance")
      .eq("user_id", user.id)
      .maybeSingle();

    if (error) {
      console.error("Wallet read error:", error);
      throw new Error("Unable to load wallet.");
    }

    if (!data) {
      throw new Error("Wallet not found.");
    }

    return Number(data.balance);
  }

  async function changeBalance(delta, meta = {}) {
    await getUser();

    const client = getClient();
    const amount = Number(delta);

    if (!Number.isFinite(amount) || amount === 0) {
      throw new Error("Invalid wallet amount.");
    }

    const { data, error } = await client.rpc(
      "nplus_wallet_change",
      {
        p_delta: amount,
        p_type: meta.type || "GAME",
        p_source: meta.source || "SYSTEM",
        p_note: meta.note || ""
      }
    );

    if (error) {
      console.error("Wallet change error:", error);
      throw new Error(
        error.message || "Unable to update wallet."
      );
    }

    const result = Array.isArray(data)
      ? data[0]
      : data;

    if (!result) {
      throw new Error(
        "Wallet update returned no result."
      );
    }

    const tx = {
      id: crypto.randomUUID(),
      uid: result.user_id,
      before: Number(result.before),
      after: Number(result.after),
      delta: Number(result.delta),
      type: meta.type || "GAME",
      source: meta.source || "SYSTEM",
      note: meta.note || "",
      created_at: Date.now()
    };

    window.dispatchEvent(
      new CustomEvent(
        "nplus:wallet-change",
        {
          detail: tx
        }
      )
    );

    return Number(result.after);
  }

  async function setBalance(amount, meta = {}) {
    const current = await getBalance();
    const next = Number(amount);

    if (!Number.isFinite(next) || next < 0) {
      throw new Error("Invalid balance.");
    }

    const delta = next - current;

    if (delta === 0) {
      return current;
    }

    return changeBalance(delta, meta);
  }

  async function transactions() {
    const user = await getUser();
    const client = getClient();

    const { data, error } = await client
      .from("demo_wallet_transactions")
      .select(
        "id,user_id,delta,balance_before,balance_after,type,source,note,created_at"
      )
      .eq("user_id", user.id)
      .order("created_at", {
        ascending: false
      })
      .limit(500);

    if (error) {
      console.error(
        "Transaction read error:",
        error
      );

      throw new Error(
        "Unable to load wallet transactions."
      );
    }

    return data || [];
  }

  window.NPlusWallet = {
    getBalance,
    setBalance,
    changeBalance,
    transactions,
    gameStores: [...GAME_STORES]
  };
})();
