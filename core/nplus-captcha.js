(() => {
  "use strict";

  // Turnstile site keys are public and intended to be embedded in browser code.
  // Never place the Turnstile secret key in this file or any frontend bundle.
  const SITE_KEY = "0x4AAAAAAAFiSyD8E8QoP0jb4";
  const mountId = "nplusCaptcha";
  let widgetId = null;
  let token = "";
  let available = false;
  let resolveReady;

  const ready = new Promise(resolve => {
    resolveReady = resolve;
  });

  function renderWidget() {
    const mount = document.getElementById(mountId);
    if (!window.turnstile || !mount) {
      resolveReady(false);
      return;
    }

    try {
      widgetId = window.turnstile.render(mount, {
        sitekey: SITE_KEY,
        theme: "dark",
        callback(value) {
          token = String(value || "");
        },
        "expired-callback"() {
          token = "";
        },
        "error-callback"() {
          token = "";
        }
      });
      available = true;
      resolveReady(true);
    } catch (error) {
      console.error("N+ PLAY Turnstile initialization failed:", error);
      resolveReady(false);
    }
  }

  window.NPlusCaptcha = {
    async getToken() {
      const loaded = await ready;
      if (!loaded || !available) {
        throw new Error("Security verification could not load. Refresh the page and try again.");
      }
      if (!token) {
        throw new Error("Complete the Cloudflare security check before continuing.");
      }
      return token;
    },

    reset() {
      token = "";
      if (available && window.turnstile && widgetId !== null) {
        try {
          window.turnstile.reset(widgetId);
        } catch (error) {
          console.warn("N+ PLAY Turnstile reset skipped:", error);
        }
      }
    }
  };

  const script = document.createElement("script");
  script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
  script.async = true;
  script.defer = true;
  script.onload = renderWidget;
  script.onerror = () => resolveReady(false);
  document.head.appendChild(script);
})();
