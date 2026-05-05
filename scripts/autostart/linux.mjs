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
 * API CONTRACT CAVEAT: PM2 startup installs ONE systemd unit per user
 * (`pm2-<user>.service`) that resurrects ALL PM2 apps for that user from
 * a single dump file. The `spec.command/args/env/workingDir` fields are
 * IGNORED here — PM2 records its own process list via `pm2 save`. As a
 * consequence, `unregister(name)` removes the entire pm2 unit regardless
 * of `name`; on a host with multiple PM2-using applications, do not call
 * unregister unless ALL of them should lose autostart.
 *
 * Caveat: requires sudo. We prompt the operator unless stdin is piped
 * (CI / unattended), in which case we abort with a clear message and a
 * non-zero exit so wrapping scripts can detect.
 */
import { spawnSync } from 'node:child_process';
import readline from 'node:readline';

const MECHANISM = 'systemd';
const PM2_CMD_TIMEOUT_MS = 60_000;

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
 * Confirm a sudo command with the operator before running. Returns false
 * on non-TTY (caller decides what to do); throws nothing so register()
 * can convert to a clean ok:false return without hitting setup.mjs's
 * outer catch.
 */
async function confirmSudo(printable) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return { ok: false, reason: 'non_tty', message: `Cannot prompt for sudo (stdin/stdout is not a TTY). Run interactively, or pre-install the systemd unit with:\n  ${printable}` };
  }
  process.stdout.write(`\nAbout to run as root:\n  ${printable}\n\nProceed? [y/N] `);
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question('', (a) => { rl.close(); resolve(a); }));
  return { ok: /^y(es)?$/i.test(answer.trim()), reason: 'declined' };
}

/**
 * Validate a sudo line printed by PM2 before we exec it via /bin/sh.
 * PM2 5.x prints lines of the form
 *     `sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u <user> --hp <home>`
 * We require the line to START with `sudo env ` (PM2's exact pattern) or
 * `sudo /` (older PM2) and to NOT contain shell metacharacters that would
 * let an injected line chain extra commands. This is defense-in-depth
 * against a supply-chain shadow of `pm2` on PATH printing a crafted
 * sudo line. The operator consent prompt is the primary gate; this
 * pattern check is a backstop.
 */
function isSafeSudoLine(line) {
  if (!/^sudo (env |\/)/.test(line)) return false;
  // Reject lines containing shell-control characters that would let an
  // injected newline chain extra commands. The `env PATH=$PATH:...`
  // segment uses `$` and `:` which are fine; we reject `;`, `&`,
  // `|`, backticks, `$(`, and embedded newlines (already split out).
  if (/[;&|`]|\$\(/.test(line)) return false;
  return true;
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
  // We pluck the `sudo ...` line, prompt, and exec it. spawnSync gets a
  // timeout to bail on a wedged PM2 daemon (corrupt socket file).
  const startup = spawnSync('pm2', ['startup', 'systemd', '-u', user, '--hp', home], {
    encoding: 'utf8',
    shell: false,
    timeout: PM2_CMD_TIMEOUT_MS,
  });
  if (startup.status !== 0) {
    // status === null when killed by timeout; status > 0 = real failure.
    return { ok: false, mechanism: MECHANISM, message: `pm2 startup failed (exit ${startup.status}): ${startup.stderr || startup.stdout || 'no output'}` };
  }

  const text = `${startup.stdout || ''}\n${startup.stderr || ''}`;
  const sudoLine = text.split('\n').map((l) => l.trim()).find((l) => l.startsWith('sudo '));
  if (sudoLine) {
    if (!isSafeSudoLine(sudoLine)) {
      return { ok: false, mechanism: MECHANISM, message: `pm2 startup printed a sudo line that does not match the expected pattern (refusing to exec):\n  ${sudoLine}\nIf this is genuinely the correct command, run it manually.` };
    }
    const consent = await confirmSudo(sudoLine);
    if (!consent.ok) {
      return { ok: false, mechanism: MECHANISM, message: consent.message || 'Operator declined sudo install. Run the printed command manually if desired.' };
    }
    // Exec the sudo command via /bin/sh so its `env PATH=...` prefix is
    // interpreted correctly. Inheriting stdio so the operator sees prompts.
    const r = spawnSync('/bin/sh', ['-c', sudoLine], { stdio: 'inherit' });
    if (r.status !== 0) {
      return { ok: false, mechanism: MECHANISM, message: `Sudo command failed (exit ${r.status})` };
    }
  } else if (!/startup file ready/i.test(text) && !/init configuration/i.test(text)) {
    // Newer PM2 (5.x) sometimes prints "Writing init configuration ..."
    // for an already-installed unit; that case is also success. We refuse
    // to silently treat unknown PM2 output as success — instead, verify
    // via status() below. If the unit reports enabled, we're good
    // regardless of what stdout said.
    const post = await status(spec.name);
    if (!post.enabled) {
      return { ok: false, mechanism: MECHANISM, message: `pm2 startup produced no sudo line and the systemd unit is not enabled. Output:\n${text}` };
    }
  }

  // Step 2: snapshot the current PM2 process list so resurrect brings them
  // back at boot. If `pm2 save` has nothing to save (no apps running) the
  // operator's autostart will simply boot an empty PM2 daemon — better than
  // failing the install.
  const save = spawnSync('pm2', ['save'], { stdio: 'inherit', timeout: PM2_CMD_TIMEOUT_MS });
  if (save.status !== 0) {
    return { ok: false, mechanism: MECHANISM, message: `pm2 save failed (exit ${save.status})` };
  }

  return { ok: true, mechanism: MECHANISM, message: `systemd unit pm2-${user} installed; apps will resurrect at boot.` };
}

export async function unregister(_name) {
  // PM2 ships `pm2 unstartup systemd` for symmetry with `pm2 startup`.
  // Same sudo prompt + safe-line check + timeout pattern.
  const startup = spawnSync('pm2', ['unstartup', 'systemd'], { encoding: 'utf8', timeout: PM2_CMD_TIMEOUT_MS });
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
  return { ok: true, mechanism: MECHANISM, message: 'systemd unit removed.' };
}

export async function status(_name) {
  const user = resolveUser();
  const r = spawnSync('systemctl', ['is-enabled', `pm2-${user}`], { encoding: 'utf8' });
  // `is-enabled` returns 0 + "enabled" when active, 1 + various states otherwise.
  return { enabled: r.status === 0 && (r.stdout || '').trim() === 'enabled', mechanism: MECHANISM, raw: r.stdout || r.stderr };
}
