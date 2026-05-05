import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

// DASH-ELEC-008: Source-map policy
// Sourcemaps are intentionally disabled for ALL build outputs, including dev
// builds. Enabling sourcemaps in a dev build that gets accidentally packaged
// would expose full renderer source code to end-users. Set to `false`
// unconditionally — never switch to `true` or `'inline'` for production use.
// Developers who need stack-trace line numbers should attach the Electron
// renderer DevTools while running `vite dev` (the dev server never writes
// sourcemaps to disk, so they are local-only and not included in any build
// artifact).
const SOURCEMAPS_ENABLED = false as const;

export default defineConfig({
  root: path.resolve(__dirname, 'src/renderer'),
  base: './',
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src/renderer/src'),
    },
  },
  build: {
    outDir: path.resolve(__dirname, 'dist/renderer'),
    emptyOutDir: true,
    // Explicitly `false` — see DASH-ELEC-008 note above.
    sourcemap: SOURCEMAPS_ENABLED,
  },
  server: {
    port: 5174,
  },
});
