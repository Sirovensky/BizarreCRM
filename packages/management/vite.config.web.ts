/**
 * Web build target for the management dashboard.
 *
 * Differs from the Electron build (`vite.config.ts`) in two ways:
 *
 *   1. `base: '/super-admin/'` — assets resolve under that path so the
 *      bundle works when served by the BizarreCRM server's static-file
 *      mount at `/super-admin/`.
 *
 *   2. `build.outDir` writes directly into the server's dist tree at
 *      `packages/server/dist/super-admin-spa/`. The server's build
 *      script ALREADY copies non-TS assets there (admin/, db/migrations,
 *      db-worker.mjs); the SPA bundle joins them.
 *
 * The renderer source is otherwise unchanged. The same code runs in
 * Electron (via main+preload) and in the browser (via the
 * electronAPIShim that polyfills window.electronAPI with fetch).
 *
 * Usage:
 *   npm run build:renderer:web -w @bizarre-crm/management
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

const REPO_ROOT = path.resolve(__dirname, '..', '..');

export default defineConfig({
  root: path.resolve(__dirname, 'src/renderer'),
  // Critical: every <script src> + <link href> + dynamic import in the
  // bundle is rewritten relative to this base. /super-admin/assets/X.js,
  // /super-admin/index.html, etc. Don't drop the trailing slash.
  base: '/super-admin/',
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src/renderer/src'),
    },
  },
  build: {
    outDir: path.resolve(REPO_ROOT, 'packages/server/dist/super-admin-spa'),
    emptyOutDir: true,
    // Same source-map policy as Electron build (DASH-ELEC-008): NEVER
    // ship source maps with a production bundle. Browser context makes
    // this even more important — the bundle is downloadable from any
    // operator's device.
    sourcemap: false,
  },
});
