// Service worker removed — was causing cached 500 errors.
// This file self-unregisters any previously installed service worker.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => Promise.all(names.map((n) => caches.delete(n))))
  );
  self.clients.claim();
  // Unregister this service worker
  self.registration.unregister();
});
