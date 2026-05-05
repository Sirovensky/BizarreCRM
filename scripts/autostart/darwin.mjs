/**
 * macOS auto-startup adapter.
 *
 * Uses PM2's native `pm2 startup launchd` flow. PM2 generates a launchd
 * plist (`~/Library/LaunchAgents/pm2.<user>.plist` or the system-wide
 * equivalent) and prints the sudo command to install it. Same prompt-then-
 * exec pattern as the Linux adapter — the only difference is the
 * mechanism PM2 uses internally.
 *
 * Caveat: `pm2 startup launchd` on recent macOS sometimes registers a
 * LaunchDaemon (system-wide, runs as root pre-login) instead of a
 * LaunchAgent (per-user, runs after login). Both work for boot
 * autostart; LaunchDaemon needs sudo to install. We let PM2 decide.
 *
 * Caveat 2: macOS Gatekeeper may interject if the Node binary is
 * unsigned (rare on Homebrew/MSI builds but happens with custom
 * installs). The first-boot launchd start may fail with a quarantine
 * error. Document in operator-guide if encountered.
 */
import { spawnSync } from 'node:child_process';
import readline from 'node:readline';

const MECHANISM = 'launchd';

function resolveUser() {
  return process.env.USER || process.env.LOGNAME || (() => {
    const r = spawnSync('whoami', [], { encoding: 'utf8' });
    return (r.stdout || '').trim();
  })();
}

async function confirmSudo(printable) {
  if (!process.stdin.isTTY) {
    throw new Error(
      `Cannot prompt for sudo (stdin is not a TTY). Run interactively, or ` +
      `pre-install the launchd plist with:\n  ${printable}`
    );
  }
  process.stdout.write(`\nAbout to run as root:\n  ${printable}\n\nProceed? [y/N] `);
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question('', (a) => { rl.close(); resolve(a); }));
  return /^y(es)?$/i.test(answer.trim());
}

export async function register(_spec) {
  const user = resolveUser();
  const home = process.env.HOME || `/Users/${user}`;

  const startup = spawnSync('pm2', ['startup', 'launchd', '-u', user, '--hp', home], { encoding: 'utf8' });
  if (startup.status !== 0 && startup.status !== null) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup failed: ${startup.stderr || startup.stdout}` };
  }

  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!(await confirmSudo(sudoLine))) {
      return { ok: false, mechanism: MECHANISM, message: 'Operator declined sudo install. Run the printed command manually if desired.' };
    }
    const r = spawnSync('/bin/sh', ['-c', sudoLine], { stdio: 'inherit' });
    if (r.status !== 0) {
      return { ok: false, mechanism: MECHANISM, message: `Sudo command failed (exit ${r.status})` };
    }
  } else if (!text.toLowerCase().includes('startup file ready')) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup did not produce a sudo command. Output:\n${text}` };
  }

  const save = spawnSync('pm2', ['save'], { stdio: 'inherit' });
  if (save.status !== 0) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 save failed (exit ${save.status})` };
  }

  return { ok: true, mechanism: MECHANISM, message: `launchd plist installed; apps will resurrect at boot.` };
}

export async function unregister(_name) {
  const startup = spawnSync('pm2', ['unstartup', 'launchd'], { encoding: 'utf8' });
  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!(await confirmSudo(sudoLine))) {
      return { ok: false, mechanism: MECHANISM, message: 'Operator declined sudo uninstall.' };
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
