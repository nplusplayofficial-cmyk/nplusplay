(() => {
  "use strict";

  const CFG = window.NPlusConfig || {};
  const PREFIX = "nplus_userstore_v3__";
  const WALLET_KEY = "__wallet_balance__";
  const TX_KEY = "__wallet_transactions__";

  const GAME_STORES = [
    "nplusplay_wingo_ultra_final_v2",
    "nplusplay_k3_wingo_style_v1",
    "nplus_moto_race_clean_v1",
    "nplus_aviator_demo_final_v3",
    "nplus_trxwingo_demo_v2",
    "nplus_5d_final_v5"
  ];

  async function uid() {
    const user = await window.NPlusAuth?.current?.();
    return user?.uid || user?.id || null;
  }

  function key(uidValue, keyName) {
    return PREFIX + uidValue + "__" + keyName;
  }

  async function getBalance() {
    const id = await uid();
    if (!id) return 0;

    const k = key(id, WALLET_KEY);
    const raw = localStorage.getItem(k);

    if (raw !== null && Number.isFinite(Number(raw))) return Number(raw);

    const initial = Number(CFG.initialDemoBalance ?? 1000);
    localStorage.setItem(k, String(initial));
    return initial;
  }

  async function setBalance(amount, meta = {}) {
    const id = await uid();
    if (!id) throw new Error("Authentication required.");

    const next = Number(amount);
    if (!Number.isFinite(next) || next < 0) throw new Error("Invalid balance.");

    const old = await getBalance();
    localStorage.setItem(key(id, WALLET_KEY), String(next));

    const tx = {
      id: crypto.randomUUID(),
      uid: id,
      before: old,
      after: next,
      delta: next - old,
      type: meta.type || "ADJUSTMENT",
      source: meta.source || "SYSTEM",
      note: meta.note || "",
      created_at: Date.now()
    };

    const txKey = key(id, TX_KEY);
    let list = [];
    try { list = JSON.parse(localStorage.getItem(txKey) || "[]"); } catch {}
    list.unshift(tx);
    localStorage.setItem(txKey, JSON.stringify(list.slice(0, 500)));

    window.dispatchEvent(new CustomEvent("nplus:wallet-change", { detail: tx }));
    return next;
  }

  async function changeBalance(delta, meta = {}) {
    const current = await getBalance();
    const amount = Number(delta);
    if (!Number.isFinite(amount)) throw new Error("Invalid amount.");
    if (current + amount < 0) throw new Error("Insufficient virtual balance.");
    return setBalance(current + amount, meta);
  }

  async function transactions() {
    const id = await uid();
    if (!id) return [];
    try { return JSON.parse(localStorage.getItem(key(id, TX_KEY)) || "[]"); }
    catch { return []; }
  }

  function installGameBridge() {
    // This bridge provides user-scoped storage helpers for future game adapters.
    // Existing game logic should be integrated one game at a time after the core is tested.
    window.NPlusWallet = {
      getBalance,
      setBalance,
      changeBalance,
      transactions,
      gameStores: [...GAME_STORES],
      walletKey: WALLET_KEY
    };
  }

  installGameBridge();
})();
