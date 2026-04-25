import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import fs from 'fs';

// Reuse the same self-signed certs as the API server
const certsDir = path.resolve(__dirname, '../server/certs');
const hasCerts = fs.existsSync(path.join(certsDir, 'server.key')) && fs.existsSync(path.join(certsDir, 'server.cert'));
// VITE_DEV_HTTP=1 disables HTTPS on the dev server so browsers that reject self-signed certs
// (e.g. automated preview tools) can connect. API proxy still targets HTTPS 443 upstream.
const useHttps = hasCerts && process.env.VITE_DEV_HTTP !== '1';

export default defineConfig({
  root: path.resolve(__dirname),
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173, // Dev-only HMR server (production uses port 443 directly)
    https: useHttps ? {
      key: fs.readFileSync(path.join(certsDir, 'server.key')),
      cert: fs.readFileSync(path.join(certsDir, 'server.cert')),
    } : undefined,
    proxy: {
      '/api': {
        target: 'https://localhost:443',
        changeOrigin: false, // Preserve original Host header for multi-tenant subdomain routing
        secure: false,
        // Override Host in dev so "localhost" requests route to a specific tenant.
        // Tenant slug is chosen via VITE_DEV_TENANT env var (defaults to bizarreelectronics).
        headers: process.env.VITE_DEV_TENANT !== undefined
          ? { Host: `${process.env.VITE_DEV_TENANT}.bizarrecrm.com` }
          : { Host: 'bizarreelectronics.bizarrecrm.com' },
      },
      '/uploads': {
        target: 'https://localhost:443',
        changeOrigin: false,
        secure: false,
        headers: process.env.VITE_DEV_TENANT !== undefined
          ? { Host: `${process.env.VITE_DEV_TENANT}.bizarrecrm.com` }
          : { Host: 'bizarreelectronics.bizarrecrm.com' },
      },
      '/super-admin': {
        target: 'https://localhost:443',
        changeOrigin: false,
        secure: false,
      },
      '/portal/api': {
        target: 'https://localhost:443',
        changeOrigin: false,
        secure: false,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false, // Never ship source maps to production — prevents source code exposure
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
});
