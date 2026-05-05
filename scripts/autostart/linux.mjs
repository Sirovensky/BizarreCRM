/**
 * Linux auto-startup adapter.
 *
 * Uses PM2's native `pm2 startup systemd` flow. PM2 generates a systemd
 * unit file (`pm2-<user>.service`) and prints the `sudo` command needed
 * to install it. We capture that command, surface it to the operator,
 * and exec it with their consent. Then `pm2 save` persists the current
 * process list so `pm2 resurrect` (called by the systemd unit at boot)
 * brings the apps back.
 *
 * This adapter intentionally delegates to PM2 rather than rolling our own
 * systemd unit. PM2's flow has been battle-tested across distros for
 * years; reinventing it would create a different brittleness in the same
 * place.
 *
 * Caveat: requires sudo. We prompt the operator unless stdin is piped
 * (CI / unattended), in which case we abort with a clear message and a
 * non-zero exit so wrapping scripts can detect.
 */
import { spawnSync } from 'node:child_process';
import readline from 'node:readline';

const MECHANISM = 'systemd';

/**
 * Resolve the user under which PM2 is running, for the systemd unit name.
 * Falls back to $USER, then to `whoami`. PM2 itself does the same internally.
 */
function resolveUser() {
  return process.env.USER || process.env.LOGNAME || (() => {
    const r = spawnSync('whoami', [], { encoding: 'utf8' });
    return (r.stdout || '').trim();
  })();
}

/**
 * Confirm a sudo command with the operator before running. Aborts on
 * non-TTY stdin so a piped/CI invocation can't hang on a phantom prompt.
 */
async function confirmSudo(printable) {
  if (!process.stdin.isTTY) {
    throw new Error(
      `Cannot prompt for sudo (stdin is not a TTY). Run interactively, or ` +
      `pre-install the systemd unit with:\n  ${printable}`
    );
  }
  process.stdout.write(`\nAbout to run as root:\n  ${printable}\n\nProceed? [y/N] `);
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question('', (a) => { rl.close(); resolve(a); }));
  return /^y(es)?$/i.test(answer.trim());
}

export async function register(spec) {
  // PM2's startup flow does not take per-app spec — it installs ONE
  // systemd unit per user and `pm2 save` snapshots the current PM2 app
  // list. The `spec` arg is therefore advisory; we ignore command/args
  // because PM2 itself records what to resurrect.
  const user = resolveUser();
  const home = process.env.HOME || `/home/${user}`;

  // Step 1: ask PM2 to print the sudo command. `pm2 startup systemd ...`
  // emits something like:
  //   [PM2] To setup the Startup Script, copy/paste the following command:
  //   sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u serega --hp /home/serega
  // We pluck the `sudo ...` line, prompt, and exec it.
  const startup = spawnSync('pm2', ['startup', 'systemd', '-u', user, '--hp', home], { encoding: 'utf8' });
  if (startup.status !== 0 && startup.status !== null) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup failed: ${startup.stderr || startup.stdout}` };
  }

  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!(await confirmSudo(sudoLine))) {
      return { ok: false, mechanism: MECHANISM, message: 'Operator declined sudo install. Run the printed command manually if desired.' };
    }
    // Exec the sudo command via /bin/sh so its `env PATH=...` prefix is
    // interpreted correctly. Inheriting stdio so the operator sees prompts.
    const r = spawnSync('/bin/sh', ['-c', sudoLine], { stdio: 'inherit' });
    if (r.status !== 0) {
      return { ok: false, mechanism: MECHANISM, message: `Sudo command failed (exit ${r.status})` };
    }
  } else if (!text.toLowerCase().includes('startup file ready')) {
    // Some PM2 versions print "[PM2] Startup file ready" when the unit is
    // already installed; treat that as success. Otherwise, surface the
    // PM2 output so the operator can debug.
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup did not produce a sudo command. Output:\n${text}` };
  }

  // Step 2: snapshot the current PM2 process list so resurrect brings them
  // back at boot. If `pm2 save` has nothing to save (no apps running) the
  // operator's autostart will simply boot an empty PM2 daemon — better than
  // failing the install.
  const save = spawnSync('pm2', ['save'], { stdio: 'inherit' });
  if (save.status !== 0) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 save failed (exit ${save.status})` };
  }

  return { ok: true, mechanism: MECHANISM, message: `systemd unit pm2-${user} installed; apps will resurrect at boot.` };
}

export async function unregister(_name) {
  // PM2 ships `pm2 unstartup systemd` for symmetry with `pm2 startup`.
  // Same sudo prompt pattern.
  const startup = spawnSync('pm2', ['unstartup', 'systemd'], { encoding: 'utf8' });
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
  return { ok: true, mechanism: MECHANISM, message: 'systemd unit removed.' };
}

export async function status(_name) {
  const user = resolveUser();
  const r = spawnSync('systemctl', ['is-enabled', `pm2-${user}`], { encoding: 'utf8' });
  // `is-enabled` returns 0 + "enabled" when active, 1 + various states otherwise.
  return { enabled: r.status === 0 && (r.stdout || '').trim() === 'enabled', mechanism: MECHANISM, raw: r.stdout || r.stderr };
}
