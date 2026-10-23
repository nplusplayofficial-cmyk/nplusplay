(() => {
  "use strict";

  const CFG = window.NPlusConfig || {};
  const IDLE_LIMIT_MS = 2 * 60 * 60 * 1000; // 2 hours

  const PUBLIC_PAGES = new Set(["", "index.html", "auth.html", "forgot-password.html"]);
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

  async function sendSignupOtp({
    email,
    mobile,
    password,
    name = "",
    referralCode = "",
    captchaToken
  }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = normalizeEmail(email);
    const cleanMobile = normalizeMobile(mobile);
    const cleanName = String(name || "").trim();
    const cleanReferralCode = String(referralCode || "").trim().toUpperCase();

    if (cleanReferralCode.length > 16) {
      throw new Error("Referral code is too long.");
    }

    if (!cleanName) throw new Error("Display name is required.");
    if (cleanName.length > 40) throw new Error("Display name is too long.");
    if (
      !password ||
      password.length < 12 ||
      password.length > 128 ||
      !/[a-z]/.test(password) ||
      !/[A-Z]/.test(password) ||
      !/\d/.test(password) ||
      !/[^A-Za-z0-9]/.test(password)
    ) {
      throw new Error("Use at least 12 characters with uppercase, lowercase, a number, and a symbol.");
    }

    // Duplicate mobiles are prevented atomically by the database unique index
    // profiles_phone_digits_unique_idx. Avoid exposing an anonymous phone-existence RPC.

    const { data, error } = await client.auth.signUp({
      email: cleanEmail,
      password,
      options: {
        data: {
          display_name: cleanName,
          signup_email: cleanEmail,
          signup_phone: cleanMobile
        },
        captchaToken
      }
    });

    if (error) {
      const msg = String(error.message || "").toLowerCase();
      if (msg.includes("already registered") ||
          msg.includes("already been registered") ||
          msg.includes("user already exists") ||
          msg.includes("already exists")) {
        throw new Error("Email address already used. Please use another email.");
      }
      if (msg.includes("database error saving new user") ||
          msg.includes("profiles_phone_digits_unique_idx") ||
          msg.includes("duplicate key")) {
        throw new Error("Account could not be created. The mobile number or email may already be registered. Check the details and try again.");
      }
      throw error;
    }

    const user = data?.user;
    if (!user) throw new Error("Account could not be created.");
    if (Array.isArray(user.identities) && user.identities.length === 0) {
      throw new Error("Email address already used. Please use another email.");
    }

    // With Supabase Confirm email ON, signUp returns no session and the user verifies by OTP.
    // With Confirm email OFF, Supabase returns an authenticated session. In that case,
    // validate the server-created profile before letting the account continue.
    if (data?.session) {
      const { data: profile, error: profileError } = await client
        .from("profiles")
        .select("phone,email")
        .eq("id", user.id)
        .maybeSingle();

      if (profileError || !profile) {
        await client.auth.signOut();
        throw new Error("Account was created, but profile setup could not be verified. Please contact support.");
      }

      const profileEmail = String(profile.email || "").trim().toLowerCase();
      const profilePhone = String(profile.phone || "").trim();
      if (profileEmail !== cleanEmail || profilePhone !== cleanMobile) {
        await client.auth.signOut();
        throw new Error("Account profile details could not be verified. Please contact support before retrying.");
      }

      let referralResult = null;
      if (cleanReferralCode) {
        try {
          const { data: result, error: referralError } = await client.rpc(
            "nplus_demo_referral_apply",
            { p_code: cleanReferralCode }
          );
          if (referralError) throw referralError;
          referralResult = result;
        } catch (referralError) {
          console.warn("N+ PLAY referral attribution skipped:", referralError);
          referralResult = {
            success: false,
            reason: "unavailable",
            message: "Referral service is not available yet."
          };
        }
      }

      markActivity();
      return {
        user,
        session: data.session,
        email: cleanEmail,
        mobile: cleanMobile,
        name: cleanName,
        immediateSession: true,
        referralResult
      };
    }

    return {
      user,
      email: cleanEmail,
      mobile: cleanMobile,
      name: cleanName,
      immediateSession: false
    };
  }

  async function resendSignupEmailOtp({ email, captchaToken }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = normalizeEmail(email);
    if (!cleanEmail) throw new Error("Enter the email used to create the account.");

    const { error } = await client.auth.resend({
      type: "signup",
      email: cleanEmail,
      options: { captchaToken }
    });

    if (error) {
      const msg = String(error.message || "").toLowerCase();
      if (msg.includes("rate limit") || msg.includes("too many")) {
        throw new Error("Too many code requests. Wait a little before requesting another email.");
      }
      throw new Error("Unable to resend the verification code. Check the email and try again.");
    }

    return { email: cleanEmail };
  }

  async function verifySignupEmailOtp({ email, token, mobile, name = "", referralCode = "" }) {
    if (!client) throw new Error("Supabase is not configured.");

    const cleanEmail = normalizeEmail(email);
    const cleanMobile = normalizeMobile(mobile);
    const cleanName = String(name || "").trim();
    const cleanReferralCode = String(referralCode || "").trim().toUpperCase();
    const code = String(token || "").trim();

    if (!/^\d{6}$/.test(code)) throw new Error("Enter the 6-digit email verification code.");

    const { data, error } = await client.auth.verifyOtp({
      email: cleanEmail,
      token: code,
      type: "email"
    });
    if (error) throw new Error("The email code is invalid or expired. Request a new code and try again.");

    const user = data?.user || data?.session?.user;
    if (!user?.id || !data?.session) throw new Error("Email verification did not create an active session.");

    const { data: profile, error: profileError } = await client
      .from("profiles")
      .select("phone,email")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !profile) {
      await client.auth.signOut();
      throw new Error("Email verified, but account profile setup failed. Please contact support before retrying signup.");
    }

    const profileEmail = String(profile.email || "").trim().toLowerCase();
    const profilePhone = String(profile.phone || "").trim();
    if (profileEmail !== cleanEmail || profilePhone !== cleanMobile) {
      await client.auth.signOut();
      throw new Error("Email verified, but the profile email/mobile does not match. Check the database profile trigger before logging in.");
    }

    let referralResult = null;
    if (cleanReferralCode) {
      try {
        const { data: result, error: referralError } = await client.rpc(
          "nplus_demo_referral_apply",
          { p_code: cleanReferralCode }
        );
        if (referralError) throw referralError;
        referralResult = result;
      } catch (referralError) {
        // Signup was verified. Referral failures must not invalidate the new account.
        console.warn("N+ PLAY referral attribution skipped:", referralError);
        referralResult = {
          success: false,
          reason: "unavailable",
          message: "Referral service is not available yet."
        };
      }
    }

    markActivity();
    return {
      user, session: data.session, email: cleanEmail, mobile: cleanMobile,
      name: cleanName, referralResult
    };
  }

  // -----------------------------
  // LOGIN
  // -----------------------------

  async function signIn({
    email,
    mobile,
    password,
    captchaToken
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
      password,
      options: { captchaToken }
    });

    if (error) {
      const message = String(error.message || "").toLowerCase();
      if (
        message.includes("weak password") ||
        message.includes("password does not meet") ||
        message.includes("password should be at least") ||
        message.includes("password must contain")
      ) {
        throw new Error("Your password needs an update. Use Forgot Password to set a new password with at least 12 characters, including uppercase, lowercase, a number, and a symbol.");
      }
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

    sendSignupOtp,
    resendSignupEmailOtp,
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
