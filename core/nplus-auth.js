(() => {
  "use strict";

  const CFG = window.NPlusConfig || {};
  const KEYS = {
    accounts: "nplus_demo_accounts_v2",
    session: "nplus_session_v2",
    uid: "nplus_authenticated_uid_v2"
  };

  const hasSupabase =
    typeof window.supabase !== "undefined" &&
    CFG.supabaseUrl &&
    CFG.supabaseAnonKey &&
    !String(CFG.supabaseUrl).startsWith("YOUR_") &&
    !String(CFG.supabaseAnonKey).startsWith("YOUR_");

  let client = null;
  if (hasSupabase) {
    client = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  }

  function makeUID() {
    const bytes = crypto.getRandomValues(new Uint8Array(8));
    return "NPLUS-" + [...bytes].map(x => x.toString(16).padStart(2, "0")).join("").toUpperCase();
  }

  function localAccounts() {
    try { return JSON.parse(localStorage.getItem(KEYS.accounts) || "{}"); }
    catch { return {}; }
  }

  function saveAccounts(x) {
    localStorage.setItem(KEYS.accounts, JSON.stringify(x));
  }

  function setLocalSession(user) {
    localStorage.setItem(KEYS.session, JSON.stringify(user));
    localStorage.setItem(KEYS.uid, user.uid);
  }

  function clearLocalSession() {
    localStorage.removeItem(KEYS.session);
    localStorage.removeItem(KEYS.uid);
  }

  async function signUp({ email, password, name = "" }) {
    if (!email || !password) throw new Error("Email and password are required.");

    if (client) {
      const { data, error } = await client.auth.signUp({
        email,
        password,
        options: { data: { display_name: name } }
      });
      if (error) throw error;
      return data.user;
    }

    const accounts = localAccounts();
    if (accounts[email.toLowerCase()]) throw new Error("Account already exists.");

    const user = {
      id: crypto.randomUUID(),
      uid: makeUID(),
      email: email.toLowerCase(),
      name: name || email.split("@")[0],
      created_at: Date.now()
    };

    accounts[user.email] = { ...user, password };
    saveAccounts(accounts);
    setLocalSession(user);
    return user;
  }

  async function signIn({ email, password }) {
    if (!email || !password) throw new Error("Email and password are required.");

    if (client) {
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return data.user;
    }

    const accounts = localAccounts();
    const user = accounts[email.toLowerCase()];
    if (!user || user.password !== password) throw new Error("Invalid email or password.");

    const safeUser = { ...user };
    delete safeUser.password;
    setLocalSession(safeUser);
    return safeUser;
  }

  async function current() {
    if (client) {
      const { data } = await client.auth.getUser();
      return data?.user || null;
    }

    try {
      return JSON.parse(localStorage.getItem(KEYS.session) || "null");
    } catch {
      return null;
    }
  }

  async function signOut() {
    if (client) {
      const { error } = await client.auth.signOut();
      if (error) throw error;
    }
    clearLocalSession();
  }

  async function requireAuth(next = location.href) {
    const user = await current();
    if (!user) {
      location.href = "auth.html?next=" + encodeURIComponent(next);
      return null;
    }
    return user;
  }

  window.NPlusAuth = {
    mode: client ? "supabase" : "local-demo",
    client,
    signUp,
    signIn,
    signOut,
    current,
    requireAuth
  };
})();
