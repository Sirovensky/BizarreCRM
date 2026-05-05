#!/usr/bin/env node
/**
 * BizarreCRM Universal Setup — Router (Phase 1)
 * ==============================================
 *
 * This script is the cross-platform setup entrypoint. It is invoked by the
 * three OS gateway shims (`setup.bat`, `setup.command`, `setup.sh`) AFTER
 * each gateway has verified Node.js >= v22 is on PATH.
 *
 * Phase 1 (this file): a thin router that delegates to the existing
 * Windows-only `scripts/setup-windows.bat` when running on Windows, and
 * prints a "not yet implemented" notice on Linux/macOS pointing at
 * `OPS-DEFERRED-001` in TODO.md.
 *
 * Phase 2 (deferred): the bulk of `scripts/setup-windows.bat` ports into
 * this file using cross-platform Node APIs (child_process, fs, path) so
 * the same flow runs on every OS without per-OS branching outside the
 * `scripts/autostart/` adapter folder.
 *
 * The split keeps Windows operators working today while the cross-platform
 * port is in progress.
 */

import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// import.meta.dirname is Node 22+. The gateway already verified that.
const __filename = fileURLToPath(import.meta.url);
const REPO_ROOT = path.dirname(__filename);

const REQUIRED_NODE_MAJOR = 22;

function fatal(msg) {
  process.stderr.write(`\n[setup.mjs] ${msg}\n`);
  process.exit(1);
}

// Belt-and-suspenders: the gateway already enforced this, but a direct
// `node setup.mjs` invocation skips the gateway. Re-check here.
const nodeMajor = parseInt(process.versions.node.split('.')[0], 10);
if (!Number.isFinite(nodeMajor) || nodeMajor < REQUIRED_NODE_MAJOR) {
  fatal(`Node.js v${REQUIRED_NODE_MAJOR}+ required (you have v${process.versions.node}).`);
}

const args = process.argv.slice(2);

if (process.platform === 'win32') {
  // Phase 1: delegate to the existing Windows-only flow. We invoke the
  // legacy .bat through cmd.exe so all of its `setlocal`, color codes,
  // labels (:try_install_node etc.) work as before. The legacy script
  // already handles everything: build, env, certs, PM2 launch, dashboard.
  const legacy = path.join(REPO_ROOT, 'scripts', 'setup-windows.bat');
  console.log(`[setup.mjs] Windows detected — delegating to scripts/setup-windows.bat`);
  console.log();
  // shell:true + cmd.exe quoting; pass forwarded args.
  const child = spawn('cmd.exe', ['/c', legacy, ...args], {
    cwd: REPO_ROOT,
    stdio: 'inherit',
    windowsVerbatimArguments: false,
  });
  child.on('exit', (code) => process.exit(code ?? 1));
  child.on('error', (err) => fatal(`Failed to launch ${legacy}: ${err.message}`));
} else if (process.platform === 'darwin' || process.platform === 'linux') {
  // Phase 2 work pending — see OPS-DEFERRED-001 in TODO.md.
  // For now, print the manual command list so the operator can complete
  // setup without the universal script. This matches what setup.bat does
  // on Windows step-by-step.
  console.log(`[setup.mjs] ${process.platform} detected — universal flow not yet ported.`);
  console.log();
  console.log('Until OPS-DEFERRED-001 lands, run these commands manually from the repo root:');
  console.log();
  console.log('  npm install');
  console.log('  node packages/server/scripts/ensure-env-secrets.cjs');
  console.log('  node packages/server/scripts/generate-certs.cjs');
  console.log('  npm run build');
  console.log('  pm2 start ecosystem.config.js');
  console.log('  pm2 save');
  console.log('  pm2 startup            # Linux/macOS — install init unit, then exec the printed sudo command');
  console.log();
  console.log('Tracking issue: TODO.md → OPS-DEFERRED-001');
  process.exit(0);
} else {
  fatal(`Unsupported platform: ${process.platform}`);
}
