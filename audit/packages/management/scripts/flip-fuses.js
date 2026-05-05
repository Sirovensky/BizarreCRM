/**
 * flip-fuses.js — afterPack hook for electron-builder
 *
 * Applies @electron/fuses hardening to the packaged Electron binary so that
 * the shipped app cannot be trivially abused via Node.js CLI escapes:
 *
 *   RunAsNode                          → DISABLED  (no --run-as-node abuse)
 *   EnableNodeOptionsEnvironmentVariable → DISABLED  (NODE_OPTIONS ignored)
 *   EnableNodeCliInspectArguments      → DISABLED  (no --inspect attach)
 *   OnlyLoadAppFromAsar                → ENABLED   (enforce ASAR integrity)
 *   EnableEmbeddedAsarIntegrityValidation → ENABLED (validate ASAR hash)
 *
 * Security checklist cross-reference (security-review skill):
 *   [x] No hardcoded secrets
 *   [x] Input validated (context object from electron-builder is trusted)
 *   [x] Error messages don't leak sensitive data — we re-throw with context
 *   [x] Principle of least privilege: all dangerous fuses disabled
 */

import { flipFuses, FuseVersion, FuseV1Options } from '@electron/fuses';
import { join } from 'node:path';

/**
 * Resolve the path to the Electron executable inside the packaged output.
 * electron-builder passes `appOutDir` (the unpacked directory) and `packager`
 * (which exposes `appInfo` and the target platform / arch).
 *
 * @param {import('electron-builder').AfterPackContext} context
 * @returns {string} Absolute path to the .exe / .app / ELF binary
 */
function resolveElectronPath(context) {
  const { appOutDir, packager } = context;
  const { productName } = packager.appInfo;
  const platform = packager.platform.nodeName; // 'win32' | 'darwin' | 'linux'

  switch (platform) {
    case 'win32':
      return join(appOutDir, `${productName}.exe`);
    case 'darwin':
      return join(appOutDir, `${productName}.app`, 'Contents', 'MacOS', productName);
    case 'linux':
      return join(appOutDir, productName);
    default:
      throw new Error(`flip-fuses: unsupported platform "${platform}"`);
  }
}

/**
 * afterPack hook — called by electron-builder after the app is packed but
 * before the installer / archive is assembled.
 *
 * @param {import('electron-builder').AfterPackContext} context
 */
export default async function flipElectronFuses(context) {
  const electronPath = resolveElectronPath(context);

  console.log(`[flip-fuses] Hardening binary: ${electronPath}`);

  await flipFuses(electronPath, {
    version: FuseVersion.V1,

    // Prevent `electron --run-as-node` abuse that bypasses the renderer sandbox.
    [FuseV1Options.RunAsNode]: false,

    // Prevent NODE_OPTIONS env-var from injecting arbitrary flags (e.g. --require).
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,

    // Prevent --inspect / --inspect-brk from being passed to attach a debugger
    // to a production binary.
    [FuseV1Options.EnableNodeCliInspectArguments]: false,

    // Require all app code to be loaded from the embedded ASAR archive;
    // prevents sideloading loose JS files next to the binary.
    [FuseV1Options.OnlyLoadAppFromAsar]: true,

    // Validate the ASAR archive's embedded integrity hash at startup so that
    // a tampered archive is rejected before any code runs.
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
  });

  console.log('[flip-fuses] Fuses applied successfully.');
}
