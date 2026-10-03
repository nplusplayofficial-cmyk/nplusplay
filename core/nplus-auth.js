(() => {
  "use strict";

  const CFG = window.NPlusConfig || {};
  const IDLE_LIMIT_MS = 2 * 60 * 60 * 1000; // 2 hours
  const ACTIVITY_THROTTLE_MS = 30 * 1000;
  const PUBLIC_PAGES = new Set(["", "index.html", "auth.html"]);
  const SEPARATE_PAGES = new Set(["admin.html", "owner.html"]);

  const hasSupabase =
    typeof window.supabase !== "undefined" &&
    CFG.supabaseUrl &&
    CFG.supabaseAnonKey &&
    !String(CFG.supabaseUrl).startsWith("YOUR_") &&
    !String(CFG.supabaseAnonKey).startsWith("YOUR_");

  const client = hasSupabase
    ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey)
    : null;

  const IDLE_KEY = "nplus_last_activity_v1";
  let idleTimer = null;
  let lastActivityWrite = 0;
  let guardRunning = false;

  function pageName() {
    return (location.pathname.split("/").pop() || "").toLowerCase();
  }

  function currentTarget() {
    const page = pageName() || "index.html";
    return page + location.search + location.hash;
  }

  function normalizePhone(value) {
    let s = String(value || "").trim().replace(/[^\d+]/g, "");
    if (s.startsWith("00")) s = "+" + s.slice(2);
    if (/^\d{10}$/.test(s)) s = "+91" + s;
    if (!/^\+\d{8,15}$/.test(s)) {
      throw new Error("Enter a valid mobile number with country code.");
    }
    return s;
  }

  function setLastActivity() {
    const now = Date.now();
    if (now - lastActivityWrite < ACTIVITY_THROTTLE_MS) return;
    lastActivityWrite = now;
    localStorage.setItem(IDLE_KEY, String(now));
    armIdleTimer();
  }

  async function signOut(reason = "") {
    if (client) {
      try { await client.auth.signOut(); } catch {}
    }
    localStorage.removeItem("nplus_authenticated_uid_v2");
    localStorage.removeItem("nplus_session_v2");

    const isAuth = pageName() === "auth.html";
    if (!isAuth) {
      const params = new URLSearchParams();
      params.set("next", currentTarget());
      if (reason) params.set("reason", reason);
      location.replace("auth.html?" + params.toString());
    }
  }

  function armIdleTimer() {
    clearTimeout(idleTimer);

    const last = Number(localStorage.getItem(IDLE_KEY) || Date.now());
    const remaining = Math.max(1000, IDLE_LIMIT_MS - (Date.now() - last));

    idleTimer = setTimeout(async () => {
      await signOut("timeout");
    }, remaining);
  }

  function startIdleProtection() {
    if (!client || pageName() === "auth.html") return;

    const activityEvents = ["pointerdown", "keydown", "touchstart", "scroll"];
    activityEvents.forEach(eventName => {
      window.addEventListener(eventName, setLastActivity, { passive: true });
    });

    if (!localStorage.getItem(IDLE_KEY)) {
      setLastActivity();
    } else {
      armIdleTimer();
    }
  }

  function localAccounts() {
    try { return JSON.parse(localStorage.getItem("nplus_demo_accounts_v2") || "{}"); }
    catch { return {}; }
  }

  function saveLocalSession(user) {
    localStorage.setItem("nplus_session_v2", JSON.stringify(user));
    localStorage.setItem("nplus_authenticated_uid_v2", user.uid || user.id);
    setLastActivity();
  }

  async function signUp({ email, phone, password, name = "" }) {
    if (!client) {
      throw new Error("Supabase is not configured.");
    }

    const normalizedPhone = normalizePhone(phone);
    const cleanEmail = String(email || "").trim().toLowerCase();

    if (!cleanEmail) throw new Error("Email is required.");
    if (password.length < 6) throw new Error("Password must be at least 6 characters.");

    const { data, error } = await client.auth.signUp({
      phone: normalizedPhone,
      password,
      options: {
        channel: "sms",
        data: {
          display_name: String(name || "").trim(),
          signup_email: cleanEmail
        }
      }
    });

    if (error) throw error;

    return {
      ...data,
      phone: normalizedPhone,
      email: cleanEmail
    };
  }

  async function verifySignupOtp({ phone, token, email, name = "" }) {
    if (!client) throw new Error("Supabase is not configured.");

    const normalizedPhone = normalizePhone(phone);

    const { data, error } = await client.auth.verifyOtp({
      phone: normalizedPhone,
      token: String(token || "").trim(),
      type: "sms"
    });

    if (error) throw error;

    // Link the supplied email to the same authenticated account.
    // Keep Email Confirmations disabled in Supabase if the desired flow is
    // one SMS OTP only and immediate email+password login.
    if (email) {
      const { error: emailError } = await client.auth.updateUser({
        email: String(email).trim().toLowerCase(),
        data: {
          display_name: String(name || "").trim(),
          signup_email: String(email).trim().toLowerCase()
        }
      });

      if (emailError) throw emailError;
    }

    const user = data?.user || (await current());
    if (user) setLastActivity();
    return data;
  }

  async function signIn({ identifier, password }) {
    if (!client) throw new Error("Supabase is not configured.");

    const value = String(identifier || "").trim();
    if (!value) throw new Error("Email or mobile number is required.");

    let data, error;

    if (value.includes("@")) {
      ({ data, error } = await client.auth.signInWithPassword({
        email: value.toLowerCase(),
        password
      }));
    } else {
      const phone = normalizePhone(value);
      ({ data, error } = await client.auth.signInWithPassword({
        phone,
        password
      }));
    }

    if (error) throw error;
    setLastActivity();
    return data.user;
  }

  async function current() {
    if (client) {
      const { data, error } = await client.auth.getUser();
      if (error) return null;
      return data?.user || null;
    }
    return null;
  }

  async function requireAuth(next = currentTarget()) {
    if (!client) {
      location.replace("auth.html?next=" + encodeURIComponent(next));
      return null;
    }

    const user = await current();
    if (!user) {
      location.replace("auth.html?next=" + encodeURIComponent(next));
      return null;
    }

    setLastActivity();
    return user;
  }

  function installGuard() {
    if (guardRunning || !client) return;
    guardRunning = true;

    const page = pageName();
    if (PUBLIC_PAGES.has(page) || SEPARATE_PAGES.has(page)) return;

    const overlay = document.createElement("div");
    overlay.id = "nplus-auth-guard";
    overlay.style.cssText =
      "position:fixed;inset:0;z-index:2147483647;background:#080908;color:#f4f1e8;display:grid;place-items:center;font:800 12px Inter,system-ui,sans-serif;letter-spacing:1px;";
    overlay.textContent = "CHECKING SESSION…";
    document.documentElement.appendChild(overlay);

    requireAuth().then(user => {
      if (user) {
        overlay.remove();
        startIdleProtection();
      }
    });
  }

  window.NPlusAuth = {
    mode: client ? "supabase" : "unconfigured",
    client,
    normalizePhone,
    signUp,
    verifySignupOtp,
    signIn,
    signOut,
    current,
    requireAuth,
    startIdleProtection,
    idleLimitMs: IDLE_LIMIT_MS
  };

  if (client) {
    installGuard();
  }
})();
