import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';

// Reuse the same self-signed certs as the API server
const certsDir = path.resolve(__dirname, '../server/certs');
const hasCerts = fs.existsSync(path.join(certsDir, 'server.key')) && fs.existsSync(path.join(certsDir, 'server.cert'));

export default defineConfig({
  root: path.resolve(__dirname),
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173, // Dev-only HMR server (production uses port 3020 directly)
    https: hasCerts ? {
      key: fs.readFileSync(path.join(certsDir, 'server.key')),
      cert: fs.readFileSync(path.join(certsDir, 'server.cert')),
    } : undefined,
    proxy: {
      '/api': {
        target: 'https://localhost:3020',
        changeOrigin: false, // Preserve original Host header for multi-tenant subdomain routing
        secure: false,
      },
      '/uploads': {
        target: 'https://localhost:3020',
        changeOrigin: false,
        secure: false,
      },
      '/super-admin': {
        target: 'https://localhost:3020',
        changeOrigin: false,
        secure: false,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false, // Never ship source maps to production — prevents source code exposure
  },
});
