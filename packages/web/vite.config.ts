import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';

// Reuse the same self-signed certs as the API server
const certsDir = path.resolve(__dirname, '../server/certs');
const certKeyPath = path.join(certsDir, 'server.key');
const certCrtPath = path.join(certsDir, 'server.cert');
// VITE_DEV_HTTP=1 disables HTTPS on the dev server so browsers that reject self-signed certs
// (e.g. automated preview tools) can connect. API proxy still targets HTTPS 443 upstream.
// @audit-fixed (WEB-FW-009 / Fixer-C1 2026-04-25): defer fs.existsSync + readFileSync
// until vite actually wants the https config. Previously top-level reads ran on every
// HMR config-reload even with VITE_DEV_HTTP=1.
function loadHttpsConfig(devHttp: boolean): { key: Buffer; cert: Buffer } | undefined {
  if (devHttp) return undefined;
  if (!fs.existsSync(certKeyPath) || !fs.existsSync(certCrtPath)) return undefined;
  return {
    key: fs.readFileSync(certKeyPath),
    cert: fs.readFileSync(certCrtPath),
  };
}

function readRootEnvValue(key: string): string | undefined {
  const rootEnvPath = path.resolve(__dirname, '../../.env');
  if (!fs.existsSync(rootEnvPath)) return undefined;
  const match = fs.readFileSync(rootEnvPath, 'utf8').match(new RegExp(`^${key}=(.*)$`, 'm'));
  return match?.[1]?.trim();
}

function resolveApiTarget(env: Record<string, string>): string {
  const explicitTarget = env.VITE_API_TARGET || process.env.VITE_API_TARGET;
  if (explicitTarget) return explicitTarget.replace(/\/+$/, '');

  const port =
    env.VITE_API_PORT ||
    process.env.VITE_API_PORT ||
    env.PORT ||
    process.env.PORT ||
    readRootEnvValue('PORT') ||
    '443';

  return `https://localhost:${port}`;
}

// devSocketResetGuard plugin was removed: attaching a `clientError`
// listener disables Node's default 400/408 response, so any HMR cycle that
// triggered the listener (Firefox keep-alive timeouts, TLS handshake
// rejects, malformed requests) destroyed in-flight sockets along with the
// bad one. Result was indefinite-loading after every code change. Vite's
// own default error handling is fine in dev; benign ECONNRESET noise in
// the terminal isn't worth corrupting the keep-alive pool over.

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, __dirname, '');
  const devHttp = env.VITE_DEV_HTTP === '1' || process.env.VITE_DEV_HTTP === '1';
  const apiTarget = resolveApiTarget(env);
  const tenantHost = process.env.VITE_DEV_TENANT !== undefined
    ? `${process.env.VITE_DEV_TENANT}.bizarrecrm.com`
    : 'bizarreelectronics.bizarrecrm.com';
  const devHttpHeader = devHttp ? { 'X-Bizarre-Dev-Http': '1' } : {};
  const tenantProxyHeaders = { Host: tenantHost, ...devHttpHeader };

  return {
  root: path.resolve(__dirname),
  // WEB-FW-005 (Fixer-B24 2026-04-25): explicit `base` so a future sub-path
  // deploy (e.g. behind `crm.example.com/web/`) works without rebuilding.
  // Default is already `/` but making it env-driven means
  // `VITE_BASE=/web/ npm run build` produces correct asset URLs in
  // `index.html` instead of root-absolute 404s on chunked JS.
  base: process.env.VITE_BASE ?? '/',
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173, // Dev-only HMR server (production uses port 443 directly)
    // Force IPv4-only bind. With `--host` (or `host: true`) vite binds to
    // the IPv6 wildcard `::` which on Windows dual-stacks IPv4 — but the
    // dual-stack IPv6 path has a Node/Windows keep-alive bug where sockets
    // close after a single round-trip, producing a TIME_WAIT pile-up and
    // eternal-loading symptoms when the browser resolves `localhost` to
    // `::1` (which Firefox does first via Happy Eyeballs). Binding to
    // 0.0.0.0 means IPv6 attempts get ECONNREFUSED, browser falls back to
    // 127.0.0.1, and IPv4 sockets stay stable.
    host: '0.0.0.0',
    https: loadHttpsConfig(devHttp),
    // WEB-FW-008 (Fixer-B24 2026-04-25): set `xfwd: true` on every proxy block
    // so http-proxy injects `X-Forwarded-For` / `X-Forwarded-Proto` /
    // `X-Forwarded-Host` headers. Server-side rate-limiter and audit-log code
    // that reads these headers in dev otherwise sees `localhost` as origin
    // and `http` as protocol, blocking debugging of origin-guard /
    // rate-limit edge cases.
    // In VITE_DEV_HTTP visual-test mode the browser origin is intentionally HTTP
    // while the proxy upstream is still HTTPS. The extra dev header lets the
    // API skip its HTTPS redirect while still seeing X-Forwarded-Proto=http,
    // which keeps local auth cookies usable on the HTTP browser origin.
    proxy: {
      '/api': {
        target: apiTarget,
        changeOrigin: false, // Preserve original Host header for multi-tenant subdomain routing
        secure: false,
        xfwd: true,
        // Override Host in dev so "localhost" requests route to a specific tenant.
        // Tenant slug is chosen via VITE_DEV_TENANT env var (defaults to bizarreelectronics).
        headers: tenantProxyHeaders,
      },
      '/uploads': {
        target: apiTarget,
        changeOrigin: false,
        secure: false,
        xfwd: true,
        headers: tenantProxyHeaders,
      },
      '/super-admin': {
        target: apiTarget,
        changeOrigin: false,
        secure: false,
        xfwd: true,
        headers: devHttpHeader,
      },
      '/portal/api': {
        target: apiTarget,
        changeOrigin: false,
        secure: false,
        xfwd: true,
        headers: devHttpHeader,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false, // Never ship source maps to production — prevents source code exposure
    // WEB-UIUX-302: strip console.log + console.warn from production bundles so
    // debug noise is never visible in end-user DevTools. console.error is kept
    // because it's used for legitimate runtime error reporting (Sentry / uncaught
    // promise rejections). Terser's pure_funcs removes call-sites with no side
    // effects; drop_debugger also removes any stray debugger statements.
    minify: 'terser',
    terserOptions: {
      compress: {
        pure_funcs: ['console.log', 'console.warn'],
        drop_debugger: true,
      },
    },
    // WEB-FW-002 (Fixer-RRR 2026-04-25): explicit production budget. Default
    // chunkSizeWarningLimit is 500 kB which lets vendor chunks (recharts ~500 kB)
    // silently exceed the budget. Tightening to 350 kB surfaces a build-log
    // warning on bundle-size regressions; reportCompressedSize prints the
    // gzipped sizes so PR reviewers can spot growth at a glance.
    chunkSizeWarningLimit: 350,
    reportCompressedSize: true,
    cssCodeSplit: true,
    assetsInlineLimit: 4096, // 4 KB — keep tiny SVG/font data-uri'd, larger assets stay separate so HTTP caching wins
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom', 'react-router-dom'],
          'vendor-charts': ['recharts'],
          'vendor-query': ['@tanstack/react-query'],
          'vendor-icons': ['lucide-react'],
        },
      },
    },
  },
  optimizeDeps: {
    include: ['lucide-react'],
  },
  };
});
