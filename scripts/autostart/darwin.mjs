/**
 * macOS auto-startup adapter.
 *
 * Uses PM2's native `pm2 startup launchd` flow. PM2 generates a launchd
 * plist (`~/Library/LaunchAgents/pm2.<user>.plist` or the system-wide
 * equivalent) and prints the sudo command to install it. Same prompt-then-
 * exec pattern as the Linux adapter — the only difference is the
 * mechanism PM2 uses internally.
 *
 * API CONTRACT CAVEAT: PM2 startup installs ONE per-user (or system-wide)
 * launchd entry that resurrects ALL of that user's PM2 apps from a single
 * dump file. The `spec.command/args/env/workingDir` fields are IGNORED;
 * `unregister(name)` removes the entire entry regardless of `name`.
 *
 * Caveat: `pm2 startup launchd` on recent macOS sometimes registers a
 * LaunchAgent (per-user, no sudo, fires only after login) instead of a
 * LaunchDaemon (system-wide, sudo required, fires pre-login). The
 * LaunchAgent path means autostart works for desktop POS terminals that
 * auto-log-in but does NOT fire on a headless server with no GUI login.
 *
 * Caveat 2: macOS Gatekeeper may interject if the Node binary is
 * unsigned (rare on Homebrew/MSI builds but happens with custom
 * installs). The first-boot launchd start may fail with a quarantine
 * error.
 */
import { spawnSync } from 'node:child_process';
import readline from 'node:readline';

const MECHANISM = 'launchd';
const PM2_CMD_TIMEOUT_MS = 60_000;

function resolveUser() {
  return process.env.USER || process.env.LOGNAME || (() => {
    const r = spawnSync('whoami', [], { encoding: 'utf8' });
    return (r.stdout || '').trim();
  })();
}

async function confirmSudo(printable) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return { ok: false, reason: 'non_tty', message: `Cannot prompt for sudo (stdin/stdout is not a TTY). Run interactively, or pre-install the launchd plist with:\n  ${printable}` };
  }
  process.stdout.write(`\nAbout to run as root:\n  ${printable}\n\nProceed? [y/N] `);
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question('', (a) => { rl.close(); resolve(a); }));
  return { ok: /^y(es)?$/i.test(answer.trim()), reason: 'declined' };
}

/** Same defense-in-depth check as linux.mjs. PM2 prints either
 *  `sudo env PATH=...` (with daemon path) or `sudo /Library/...`. */
function isSafeSudoLine(line) {
  if (!/^sudo (env |\/)/.test(line)) return false;
  if (/[;&|`]|\$\(/.test(line)) return false;
  return true;
}

export async function register(spec) {
  const user = resolveUser();
  const home = process.env.HOME || `/Users/${user}`;

  const startup = spawnSync('pm2', ['startup', 'launchd', '-u', user, '--hp', home], {
    encoding: 'utf8',
    shell: false,
    timeout: PM2_CMD_TIMEOUT_MS,
  });
  if (startup.status !== 0) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup failed (exit ${startup.status}): ${startup.stderr || startup.stdout || 'no output'}` };
  }

  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!isSafeSudoLine(sudoLine)) {
      return { ok: false, mechanism: MECHANISM, message: `pm2 startup printed a sudo line that does not match the expected pattern (refusing to exec):\n  ${sudoLine}` };
    }
    const consent = await confirmSudo(sudoLine);
    if (!consent.ok) {
      return { ok: false, mechanism: MECHANISM, message: consent.message || 'Operator declined sudo install.' };
    }
    const r = spawnSync('/bin/sh', ['-c', sudoLine], { stdio: 'inherit' });
    if (r.status !== 0) {
      return { ok: false, mechanism: MECHANISM, message: `Sudo command failed (exit ${r.status})` };
    }
  } else if (!/startup file ready/i.test(text) && !/init configuration/i.test(text) && !/launch[da]/i.test(text)) {
    // PM2 5.x with LaunchAgent path may print just the plist path without
    // any of the legacy "startup file ready" string. Verify by status()
    // before declaring failure.
    const post = await status(spec.name);
    if (!post.enabled) {
      return { ok: false, mechanism: MECHANISM, message: `pm2 startup produced no sudo line and no launchd entry was registered. Output:\n${text}` };
    }
  }

  const save = spawnSync('pm2', ['save'], { stdio: 'inherit', timeout: PM2_CMD_TIMEOUT_MS });
  if (save.status !== 0) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 save failed (exit ${save.status})` };
  }

  return { ok: true, mechanism: MECHANISM, message: `launchd plist installed; apps will resurrect at boot.` };
}

export async function unregister(_name) {
  const startup = spawnSync('pm2', ['unstartup', 'launchd'], { encoding: 'utf8', timeout: PM2_CMD_TIMEOUT_MS });
  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!isSafeSudoLine(sudoLine)) {
      return { ok: false, mechanism: MECHANISM, message: `pm2 unstartup printed a sudo line that does not match the expected pattern (refusing to exec):\n  ${sudoLine}` };
    }
    const consent = await confirmSudo(sudoLine);
    if (!consent.ok) {
      return { ok: false, mechanism: MECHANISM, message: consent.message || 'Operator declined sudo uninstall.' };
    }
    const r = spawnSync('/bin/sh', ['-c', sudoLine], { stdio: 'inherit' });
    if (r.status !== 0) {
      return { ok: false, mechanism: MECHANISM, message: `Sudo command failed (exit ${r.status})` };
    }
  }
  return { ok: true, mechanism: MECHANISM, message: 'launchd plist removed.' };
}

export async function status(_name) {
  const user = resolveUser();
  // PM2's plist label varies between PM2 minor versions: it has historically
  // been `pm2.<user>` and `com.pm2.<user>` and `local.PM2`. Search both
  // standard plist locations for any match.
  const r = spawnSync('launchctl', ['list'], { encoding: 'utf8' });
  if (r.status !== 0) {
    return { enabled: false, mechanism: MECHANISM, raw: r.stderr };
  }
  const out = r.stdout || '';
  // eslint-disable-next-line no-useless-escape
  const re = new RegExp(`pm2[\\.\\-]${user}|com\\.pm2\\.${user}|local\\.PM2`, 'i');
  return { enabled: re.test(out), mechanism: MECHANISM, raw: out.split('\n').filter((l) => /pm2/i.test(l)).join('\n') };
}
