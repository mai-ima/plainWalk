const CACHE = "plainwalk-v9";
const FILES = [
  "./",
  "./index.html",
  "./style.css",
  "./app.js",
  "./core.js",
  "./map-geometry.js",
  "./diagnostics.js",
  "./developer-ui.js",
  "./collections.js",
  "./native.js",
  "./units.js",
  "./effects.js",
  "./media.js",
  "./photo-metadata.js",
  "./areas.js",
  "./notebook.js",
  "./notebook-pages.js",
  "./reference-ui.js",
  "./companion.js",
  "./data/japan-municipalities.geojson",
  "./icon.svg",
  "./icon.png",
  "./manifest.webmanifest",
];
self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(FILES))
      .then(() => self.skipWaiting()),
  );
});
self.addEventListener("activate", (e) =>
  e.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  ),
);
self.addEventListener("fetch", (e) => {
  const requestURL = new URL(e.request.url);
  const downloadsPath = new URL("downloads/", self.registration.scope).pathname;
  if (
    e.request.method !== "GET" ||
    requestURL.origin !== self.location.origin ||
    requestURL.pathname === downloadsPath.slice(0, -1) ||
    requestURL.pathname.startsWith(downloadsPath)
  )
    return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
        }
        return res;
      })
      .catch(() =>
        caches
          .match(e.request)
          .then(
            (res) =>
              res ||
              (e.request.mode === "navigate"
                ? caches.match("./index.html")
                : Response.error()),
          ),
      ),
  );
});
