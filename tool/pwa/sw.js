// minimal offline shell
const C="sp-v1";
self.addEventListener("install",e=>e.waitUntil(caches.open(C).then(c=>c.addAll(["/","/index.html","/manifest.json"]))));
self.addEventListener("fetch",e=>{ if(e.request.url.includes("/pad")||e.request.url.includes("/say")||e.request.url.includes("/pads"))return;
  e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request))); });
