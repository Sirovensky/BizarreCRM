#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, watch } from 'node:fs';
import { dirname, join } from 'node:path';
import { spawn } from 'node:child_process';

const root = new URL('..', import.meta.url);
const preloadDir = join(root.pathname, 'dist', 'preload');
const emittedFile = join(preloadDir, 'index.js');
const electronFile = join(preloadDir, 'index.cjs');

function syncPreload() {
  if (!existsSync(emittedFile)) return;
  mkdirSync(dirname(electronFile), { recursive: true });
  copyFileSync(emittedFile, electronFile);
}

const tsc = spawn(
  process.platform === 'win32' ? 'npx.cmd' : 'npx',
  ['tsc', '--project', 'tsconfig.preload.json', '--watch', '--preserveWatchOutput'],
  {
    cwd: root,
    stdio: 'inherit',
  },
);

let watcher;
try {
  mkdirSync(preloadDir, { recursive: true });
  watcher = watch(preloadDir, { persistent: true }, (eventType, filename) => {
    if (filename !== 'index.js') return;
    if (eventType !== 'change' && eventType !== 'rename') return;
    setTimeout(syncPreload, 50);
  });
} catch (err) {
  console.error('[dev-preload-watch] could not watch preload output:', err);
}

const initial = setInterval(syncPreload, 500);
setTimeout(() => clearInterval(initial), 10_000);

function shutdown(signal) {
  watcher?.close();
  tsc.kill(signal);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
tsc.on('exit', (code) => {
  watcher?.close();
  process.exit(code ?? 0);
});
