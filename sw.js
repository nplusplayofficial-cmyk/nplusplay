/* N+ PLAY PWA shell. Never cache Supabase/auth/API requests or authenticated data. */
const VERSION = "nplus-play-shell-v1";
const SHELL = ["./offline.html", "./manifest.webmanifest", "./assets/nplus-icon.svg"];
self.addEventListener("install", event => {
  event.waitUntil(caches.open(VERSION).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (/\/rest\/v1\/|\/auth\/v1\/|supabase\.co/i.test(url.href)) return;
  if (req.mode === "navigate") {
    event.respondWith(fetch(req).then(res => {
      if (res.ok) { const clone = res.clone(); caches.open(VERSION).then(c => c.put(req, clone)); }
      return res;
    }).catch(async () => (await caches.match(req)) || (await caches.match("./offline.html"))));
    return;
  }
  event.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
    if (res.ok) { const clone = res.clone(); caches.open(VERSION).then(c => c.put(req, clone)); }
    return res;
  })));
});
