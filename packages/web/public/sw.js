/**
 * ENR-INFRA1: Basic service worker for offline shell caching.
 * Caches the app shell (HTML, CSS, JS) for offline access.
 * API calls are NOT cached — they always go to network.
 */

const CACHE_NAME = 'bizarrecrm-shell-v2';

// Pre-cache the app shell on install
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll([
        '/',
      ]);
    })
  );
  // Activate immediately
  self.skipWaiting();
});

// Clean up old caches on activate
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

// Network-first strategy for API calls, cache-first for static assets
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Never cache API calls, WebSocket, or upload requests
  if (
    url.pathname.startsWith('/api') ||
    url.pathname.startsWith('/uploads') ||
    url.pathname.startsWith('/ws') ||
    event.request.method !== 'GET'
  ) {
    return; // Let the browser handle it normally
  }

  // For navigation requests (HTML pages), try network first, fall back to cache
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request).then((r) => r || caches.match('/')))
    );
    return;
  }

  // For static assets, try cache first, then network
  // Only return cached responses that were successful (200) — never serve cached errors
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached && cached.ok) return cached;
      return fetch(event.request).then((response) => {
        // Only cache successful responses
        if (response.ok && (url.pathname.match(/\.(js|css|svg|png|jpg|woff2?)$/))) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      });
    })
  );
});
