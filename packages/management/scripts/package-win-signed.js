#!/usr/bin/env node
/**
 * Release packaging gate for the Windows management dashboard.
 *
 * The dashboard can also run as the `/super-admin/` web surface, so unsigned
 * Electron is not a product availability blocker. It is still a release trust
 * issue: a distributable .exe/.nsis installer should not be produced without
 * Authenticode signing.
 */
import { spawnSync } from 'node:child_process';

const subject = process.env.WIN_CERT_SUBJECT?.trim();
const certFile = process.env.WIN_CERT_FILE?.trim();
const certPassword = process.env.WIN_CERT_PASSWORD;

const hasSubject = Boolean(subject);
const hasPfx = Boolean(certFile || certPassword);

if (hasSubject && hasPfx) {
  console.error(
    'Use either WIN_CERT_SUBJECT or WIN_CERT_FILE/WIN_CERT_PASSWORD, not both.',
  );
  process.exit(1);
}

if (!hasSubject && !hasPfx) {
  console.error(
    [
      'Windows release packaging requires Authenticode signing.',
      'Set WIN_CERT_SUBJECT for a certificate in the Windows cert store, or',
      'set WIN_CERT_FILE and WIN_CERT_PASSWORD for a PFX-backed signing cert.',
      'Use npm start or npm run dev:electron for unsigned local development.',
    ].join('\n'),
  );
  process.exit(1);
}

if (hasPfx && (!certFile || !certPassword)) {
  console.error('PFX signing requires both WIN_CERT_FILE and WIN_CERT_PASSWORD.');
  process.exit(1);
}

const args = ['electron-builder', '--win'];
const env = { ...process.env };
if (subject) {
  args.push(
    `-c.win.certificateSubjectName=${subject}`,
    `-c.win.publisherName=${subject}`,
  );
} else {
  env.CSC_LINK = certFile;
  env.CSC_KEY_PASSWORD = certPassword;
  args.push('-c.win.publisherName=Bizarre Electronics LLC');
}

const result = spawnSync('npx', args, {
  cwd: new URL('..', import.meta.url),
  env,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

process.exit(result.status ?? 1);
