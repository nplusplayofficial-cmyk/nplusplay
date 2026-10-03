(() => {
  "use strict";

  const CFG = window.NPlusConfig || {};
  const IDLE_LIMIT_MS = 2 * 60 * 60 * 1000; // 2 hours
  const PUBLIC_PAGES = new Set(["", "index.html", "auth.html"]);
  const SEPARATE_PAGES = new Set(["admin.html", "owner.html"]);
  const IDLE_KEY = "nplus_last_activity_v1";

  const configured =
    typeof window.supabase !== "undefined" &&
    CFG.supabaseUrl &&
    CFG.supabaseAnonKey &&
    !String(CFG.supabaseUrl).startsWith("YOUR_") &&
    !String(CFG.supabaseAnonKey).startsWith("YOUR_");

  const client = configured
    ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey)
    : null;

  let idleTimer = null;
  let lastWrite = 0;

  function pageName() {
    return (location.pathname.split("/").pop() || "").toLowerCase();
  }

  function targetUrl() {
    return (pageName() || "index.html") + location.search + location.hash;
  }

  function normalizeMobile(value) {
    let s = String(value || "").trim().replace(/[^\d+]/g, "");
    if (s.startsWith("00")) s = "+" + s.slice(2);
    if (/^\d{10}$/.test(s)) s = "+91" + s;
    if (!/^\+\d{8,15}$/.test(s)) {
      throw new Error("Enter a valid mobile number with country code.");
    }
    return s;
  }

  function markActivity() {
    const now = Date.now();
    if (now - lastWrite < 30000) return;
    lastWrite = now;
    localStorage.setItem(IDLE_KEY, String(now));
    armIdleTimer();
  }

  function armIdleTimer() {
    clearTimeout(idleTimer);
    const last = Number(localStorage.getItem(IDLE_KEY) || Date.now());
    const left = Math.max(1000, IDLE_LIMIT_MS - (Date.now() - last));
    idleTimer = setTimeout(() => signOut("timeout"), left);
  }

  async function signOut(reason = "") {
    if (client) {
      try { await client.auth.signOut(); } catch {}
    }
    localStorage.removeItem("nplus_authenticated_uid_v2");
    localStorage.removeItem("nplus_session_v2");

    if (pageName() !== "auth.html") {
      const q = new URLSearchParams({ next: targetUrl() });
      if (reason) q.set("reason", reason);
      location.replace("auth.html?" + q.toString());
    }
  }

  function startIdleProtection() {
    if (!client || pageName() === "auth.html") return;
    ["pointerdown", "keydown", "touchstart", "scroll"].forEach(evt =>
      window.addEventListener(evt, markActivity, { passive: true })
    );
    if (!localStorage.getItem(IDLE_KEY)) markActivity();
    else armIdleTimer();
  }

  async function sendSignupOtp({ email, mobile, password, name = "" }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = String(email || "").trim().toLowerCase();
    const cleanMobile = normalizeMobile(mobile);

    if (!cleanEmail) throw new Error("Email is required.");
    if (password.length < 6) throw new Error("Password must be at least 6 characters.");

    // Prevent a known duplicate mobile before creating the Auth user.
    // This RPC returns only a boolean and does not expose another user's data.
    const { data: phoneUsed, error: phoneCheckError } =
      await client.rpc("nplus_phone_is_registered", { p_phone: cleanMobile });

    if (phoneCheckError) {
      throw new Error("Could not check the mobile number. Please try again.");
    }
    if (phoneUsed === true) {
      throw new Error("This email and mobile number are already registered or the mobile number is already in use.");
    }

    const { data, error } = await client.auth.signUp({
      email: cleanEmail,
      password,
      options: {
        data: {
          display_name: String(name || "").trim(),
          signup_email: cleanEmail,
          signup_phone: cleanMobile
        }
      }
    });

    if (error) {
      const text = String(error.message || "").toLowerCase();
      if (text.includes("already registered") || text.includes("already been registered") || text.includes("user already exists")) {
        throw new Error("This email and mobile number are already registered.");
      }
      throw error;
    }

    markActivity();

    return {
      user: data?.user || null,
      session: data?.session || null,
      email: cleanEmail,
      mobile: cleanMobile,
      name: String(name || "").trim()
    };
  }

  async function verifySignupEmailOtp({ email, token, mobile, name = "" }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = String(email || "").trim().toLowerCase();
    const cleanMobile = normalizeMobile(mobile);
    const cleanToken = String(token || "").trim();

    if (!/^\d{6}$/.test(cleanToken)) {
      throw new Error("Enter the 6-digit email OTP.");
    }

    const { data, error } = await client.auth.verifyOtp({
      email: cleanEmail,
      token: cleanToken,
      type: "email"
    });

    if (error) throw error;

    // The signup trigger stores profile data from auth metadata and creates
    // the user's ₹108 demo wallet. Update profile contact fields defensively.
    const user = data?.user;
    if (!user) throw new Error("Verification succeeded, but no user session was returned.");

    const { error: profileError } = await client
      .from("profiles")
      .update({
        email: cleanEmail,
        phone: cleanMobile,
        display_name: String(name || "").trim()
      })
      .eq("id", user.id);

    if (profileError) {
      throw new Error("Account verified, but profile setup could not be completed.");
    }

    markActivity();
    return user;
  }

  async function signIn({ email, mobile, password }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = String(email || "").trim().toLowerCase();
    const cleanMobile = normalizeMobile(mobile);

    const { data, error } = await client.auth.signInWithPassword({
      email: cleanEmail,
      password
    });

    if (error) throw error;
    const user = data?.user;
    if (!user) throw new Error("Login failed.");

    // Require the mobile number entered at login to match the verified profile record.
    const { data: profile, error: profileError } = await client
      .from("profiles")
      .select("phone")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      await client.auth.signOut();
      throw new Error("Unable to verify the mobile number.");
    }

    if (!profile || profile.phone !== cleanMobile) {
      await client.auth.signOut();
      throw new Error("Email, mobile number, or password is incorrect.");
    }

    markActivity();
    return user;
  }

  async function current() {
    if (!client) return null;
    const { data } = await client.auth.getUser();
    return data?.user || null;
  }

  async function requireAuth(next = targetUrl()) {
    if (!client) {
      location.replace("auth.html?next=" + encodeURIComponent(next));
      return null;
    }

    const user = await current();
    if (!user) {
      location.replace("auth.html?next=" + encodeURIComponent(next));
      return null;
    }

    markActivity();
    return user;
  }

  function installGuard() {
    const page = pageName();
    if (!client || PUBLIC_PAGES.has(page) || SEPARATE_PAGES.has(page)) return;

    const overlay = document.createElement("div");
    overlay.style.cssText =
      "position:fixed;inset:0;z-index:2147483647;background:#080908;color:#f4f1e8;display:grid;place-items:center;font:800 12px Inter,system-ui,sans-serif;letter-spacing:1px";
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
    normalizeMobile,
    sendSignupOtp,
    verifySignupEmailOtp,
    signIn,
    signOut,
    current,
    requireAuth,
    startIdleProtection,
    idleLimitMs: IDLE_LIMIT_MS
  };

  installGuard();
})();
