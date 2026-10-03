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
    ? window.supabase.createClient(
        CFG.supabaseUrl,
        CFG.supabaseAnonKey
      )
    : null;

  let idleTimer = null;
  let lastWrite = 0;

  function pageName() {
    return (location.pathname.split("/").pop() || "").toLowerCase();
  }

  function targetUrl() {
    return (
      (pageName() || "index.html") +
      location.search +
      location.hash
    );
  }

  // -----------------------------
  // EMAIL VALIDATION
  // -----------------------------

  function normalizeEmail(value) {
    const email = String(value || "").trim().toLowerCase();

    if (!email) {
      throw new Error("Email address is required.");
    }

    // Basic practical email validation
    if (
      email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)
    ) {
      throw new Error("Enter a valid email address.");
    }

    return email;
  }

  // -----------------------------
  // MOBILE VALIDATION
  // -----------------------------

  function normalizeMobile(value) {
    let s = String(value || "")
      .trim()
      .replace(/[^\d+]/g, "");

    if (s.startsWith("00")) {
      s = "+" + s.slice(2);
    }

    // Indian 10-digit number
    if (/^[6-9]\d{9}$/.test(s)) {
      s = "+91" + s;
    }

    // Accept +91XXXXXXXXXX
    if (!/^\+91[6-9]\d{9}$/.test(s)) {
      throw new Error("Enter a valid Indian mobile number.");
    }

    return s;
  }

  // -----------------------------
  // ACTIVITY / SESSION
  // -----------------------------

  function markActivity() {
    const now = Date.now();

    if (now - lastWrite < 30000) return;

    lastWrite = now;
    localStorage.setItem(IDLE_KEY, String(now));
    armIdleTimer();
  }

  function armIdleTimer() {
    clearTimeout(idleTimer);

    const last = Number(
      localStorage.getItem(IDLE_KEY) || Date.now()
    );

    const left = Math.max(
      1000,
      IDLE_LIMIT_MS - (Date.now() - last)
    );

    idleTimer = setTimeout(() => {
      signOut("timeout");
    }, left);
  }

  async function signOut(reason = "") {
    if (client) {
      try {
        await client.auth.signOut();
      } catch {}
    }

    localStorage.removeItem("nplus_authenticated_uid_v2");
    localStorage.removeItem("nplus_session_v2");
    localStorage.removeItem(IDLE_KEY);

    if (pageName() !== "auth.html") {
      const q = new URLSearchParams({
        next: targetUrl()
      });

      if (reason) {
        q.set("reason", reason);
      }

      location.replace("auth.html?" + q.toString());
    }
  }

  function startIdleProtection() {
    if (!client || pageName() === "auth.html") return;

    ["pointerdown", "keydown", "touchstart", "scroll"].forEach(
      evt => {
        window.addEventListener(evt, markActivity, {
          passive: true
        });
      }
    );

    if (!localStorage.getItem(IDLE_KEY)) {
      markActivity();
    } else {
      armIdleTimer();
    }
  }

  // -----------------------------
  // SIGNUP
  // -----------------------------

  async function signUp({
    email,
    mobile,
    password,
    name = ""
  }) {
    if (!client) {
      throw new Error("Supabase is not configured.");
    }

    const cleanEmail = normalizeEmail(email);
    const cleanMobile = normalizeMobile(mobile);
    const cleanName = String(name || "").trim();

    if (!cleanName) {
      throw new Error("Display name is required.");
    }

    if (cleanName.length > 40) {
      throw new Error("Display name is too long.");
    }

    if (!password || password.length < 6) {
      throw new Error(
        "Password must be at least 6 characters."
      );
    }

    // -----------------------------------------
    // CHECK DUPLICATE MOBILE
    // -----------------------------------------

    const {
      data: phoneUsed,
      error: phoneCheckError
    } = await client.rpc(
      "nplus_phone_is_registered",
      {
        p_phone: cleanMobile
      }
    );

    if (phoneCheckError) {
      throw new Error(
        "Could not check the mobile number. Please try again."
      );
    }

    if (phoneUsed === true) {
      throw new Error(
        "Mobile number already used. Please use another number."
      );
    }

    // -----------------------------------------
    // CREATE AUTH USER
    //
    // IMPORTANT:
    // Supabase Email Confirmation must be OFF.
    // -----------------------------------------

    const {
      data,
      error
    } = await client.auth.signUp({
      email: cleanEmail,
      password,
      options: {
        data: {
          display_name: cleanName,
          signup_email: cleanEmail,
          signup_phone: cleanMobile
        }
      }
    });

    if (error) {
      const msg = String(
        error.message || ""
      ).toLowerCase();

      if (
        msg.includes("already registered") ||
        msg.includes("already been registered") ||
        msg.includes("user already exists") ||
        msg.includes("already exists")
      ) {
        throw new Error(
          "Email address already used. Please use another email."
        );
      }

      throw error;
    }

    const user = data?.user;

    if (!user) {
      throw new Error(
        "Account could not be created."
      );
    }

    // With email confirmation OFF,
    // Supabase should return an active session.
    if (!data?.session) {
      throw new Error(
        "Account was created, but automatic login is unavailable. Please check Supabase Email confirmation settings."
      );
    }

    markActivity();

    return {
      user,
      session: data.session,
      email: cleanEmail,
      mobile: cleanMobile,
      name: cleanName
    };
  }

  // -----------------------------
  // LOGIN
  // -----------------------------

  async function signIn({
    email,
    mobile,
    password
  }) {
    if (!client) {
      throw new Error("Supabase is not configured.");
    }

    const cleanEmail = normalizeEmail(email);
    const cleanMobile = normalizeMobile(mobile);

    if (!password) {
      throw new Error("Password is required.");
    }

    const {
      data,
      error
    } = await client.auth.signInWithPassword({
      email: cleanEmail,
      password
    });

    if (error) {
      throw new Error(
        "Email, mobile number, or password is incorrect."
      );
    }

    const user = data?.user;

    if (!user) {
      throw new Error("Login failed.");
    }

    // -----------------------------------------
    // CHECK MOBILE AGAINST PROFILE
    // -----------------------------------------

    const {
      data: profile,
      error: profileError
    } = await client
      .from("profiles")
      .select("phone,email")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !profile) {
      await client.auth.signOut();

      throw new Error(
        "Unable to verify account details."
      );
    }

    const profileEmail =
      String(profile.email || "")
        .trim()
        .toLowerCase();

    const profilePhone =
      String(profile.phone || "").trim();

    if (
      profileEmail !== cleanEmail ||
      profilePhone !== cleanMobile
    ) {
      await client.auth.signOut();

      throw new Error(
        "Email, mobile number, or password is incorrect."
      );
    }

    markActivity();

    return user;
  }

  // -----------------------------
  // CURRENT USER
  // -----------------------------

  async function current() {
    if (!client) return null;

    const {
      data,
      error
    } = await client.auth.getUser();

    if (error) return null;

    return data?.user || null;
  }

  // -----------------------------
  // PROTECTED PAGES
  // -----------------------------

  async function requireAuth(
    next = targetUrl()
  ) {
    if (!client) {
      location.replace(
        "auth.html?next=" +
        encodeURIComponent(next)
      );

      return null;
    }

    const user = await current();

    if (!user) {
      location.replace(
        "auth.html?next=" +
        encodeURIComponent(next)
      );

      return null;
    }

    markActivity();

    return user;
  }

  function installGuard() {
    const page = pageName();

    if (
      !client ||
      PUBLIC_PAGES.has(page) ||
      SEPARATE_PAGES.has(page)
    ) {
      return;
    }

    const overlay =
      document.createElement("div");

    overlay.style.cssText =
      "position:fixed;inset:0;z-index:2147483647;background:#080908;color:#f4f1e8;display:grid;place-items:center;font:800 12px Inter,system-ui,sans-serif;letter-spacing:1px";

    overlay.textContent =
      "CHECKING SESSION…";

    document.documentElement.appendChild(
      overlay
    );

    requireAuth().then(user => {
      if (user) {
        overlay.remove();
        startIdleProtection();
      }
    });
  }

  // -----------------------------
  // PUBLIC API
  // -----------------------------

  window.NPlusAuth = {
    mode: client
      ? "supabase"
      : "unconfigured",

    client,

    normalizeEmail,
    normalizeMobile,

    signUp,
    signIn,
    signOut,
    current,
    requireAuth,
    startIdleProtection,

    idleLimitMs: IDLE_LIMIT_MS
  };

  installGuard();
})();
