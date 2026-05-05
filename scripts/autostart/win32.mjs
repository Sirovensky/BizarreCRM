/**
 * Windows auto-startup adapter.
 *
 * Uses Windows Task Scheduler ("Scheduled Tasks") via the built-in
 * `schtasks.exe` CLI to register a boot-time task that runs:
 *
 *   <command> <args...>     (cwd: workingDir, env: spec.env baked in)
 *
 * For BizarreCRM the typical caller passes `node.exe` + the absolute path
 * to PM2's `pm2` script + `resurrect`, so the task spawns PM2 at boot and
 * PM2 in turn resurrects bizarre-crm + bizarre-crm-watchdog from its dump.
 *
 * Why Task Scheduler instead of NSSM/WinSW (per docs/dashboard-migration-plan.md
 * + serviceplan.md):
 *   - schtasks is built into every Windows since XP — zero vendored binaries
 *   - "At startup" trigger fires before any user logs in
 *   - Runs as SYSTEM (S-1-5-18) so PM2_HOME is consistent across sessions
 *   - No code-signing concerns; no install of WinSW/NSSM to begin with
 *   - Recovery actions handled natively (RestartOnFailure / Count)
 *
 * The task XML pins:
 *   - <BootTrigger> with PT30S delay so the OS finishes its own startup work
 *   - <Principal> S-1-5-18 (SYSTEM) + HighestAvailable so secrets in env
 *     resolve correctly
 *   - <DisallowStartIfOnBatteries>false (shop POS terminals are often
 *     wall-powered desktops, but we don't want a laptop install to silently
 *     skip)
 *   - <ExecutionTimeLimit>PT5M (the task should finish quickly — its only
 *     job is to spawn PM2 daemon, which detaches and exits)
 */
import { spawnSync } from 'node:child_process';
import { writeFileSync, unlinkSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const MECHANISM = 'taskscheduler';

/** Minimal XML-attribute escape. The XML body is built by string concat
 *  but every interpolated value goes through this so paths with `&`, `<`,
 *  `"`, `'` cannot break out of the XML structure. */
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;',
  })[c]);
}

/** Build the Task Scheduler XML for `spec`.
 *
 *  Important: the Task Scheduler v1.4 XML schema's `ExecType` defines only
 *  three children of `<Exec>`: `<Command>`, `<Arguments>`, `<WorkingDirectory>`.
 *  There is NO `<Environment>` element. An earlier draft of this adapter
 *  emitted one and `schtasks` silently dropped it, leaving PM2_HOME unset
 *  at boot — the SYSTEM-context PM2 then read its dump from
 *  `%SystemRoot%\system32\config\systemprofile\.pm2\` (empty) instead of
 *  the repo's `.pm2/`, and bizarre-crm never resurrected.
 *
 *  Fix: register() writes a small launcher `.cmd` file that sets env vars
 *  via `set ...` then exec's the underlying command. The XML's
 *  `<Command>` points at the launcher so env vars survive.
 *
 *  Also: `<Command>` value must be the bare path with NO quoting; Task
 *  Scheduler does not shell-parse it. We assume the launcher path is
 *  under `<repo>/scripts/autostart/<name>.cmd` which never contains
 *  unusual characters (the repo path itself might, but the launcher
 *  path is under that, and Task Scheduler accepts UTF-16-encoded paths
 *  with spaces in `<Command>` directly).
 */
function buildXml(spec, launcherPath) {
  return `<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>${esc(spec.description || spec.name)}</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="A">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RestartOnIdle>false</RestartOnIdle>
    <WakeToRun>false</WakeToRun>
  </Settings>
  <Actions Context="A">
    <Exec>
      <Command>${esc(launcherPath)}</Command>
      <WorkingDirectory>${esc(spec.workingDir)}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>`;
}

/**
 * Build the launcher .cmd content. Sets each env var via `set`, then
 * invokes the underlying command with its args. `cmd.exe` quoting rules
 * are ugly but well-known: wrap each argument in double-quotes, escape
 * embedded `"` as `""`, escape `^` `&` `<` `>` `|` as `^X`. We ONLY
 * double-quote here because the args we receive are absolute paths
 * resolved by setup.mjs — they don't contain `"`, `^`, `&`, etc.
 */
function buildLauncher(spec) {
  const lines = ['@echo off', 'setlocal'];
  for (const [k, v] of Object.entries(spec.env || {})) {
    if (!/^[A-Z_][A-Z0-9_]*$/i.test(k)) {
      throw new Error(`win32 autostart: env var name "${k}" contains invalid characters`);
    }
    // cmd.exe `set` quoting: `set "NAME=value"` to preserve trailing
    // whitespace and special chars. The value is written verbatim — paths
    // with `&` etc would need escaping but PM2_HOME and similar are
    // operator-controlled and trusted.
    lines.push(`set "${k}=${v}"`);
  }
  // Build the command line. cmd-quote each argv element.
  const cmdQuote = (s) => `"${String(s).replace(/"/g, '""')}"`;
  const cmdLine = [cmdQuote(spec.command), ...(spec.args || []).map(cmdQuote)].join(' ');
  lines.push(cmdLine);
  lines.push('endlocal');
  return lines.join('\r\n') + '\r\n';
}

/** Validate spec.name to keep it safe for filename + Task Scheduler use. */
function validateName(name) {
  if (typeof name !== 'string' || !name) {
    throw new Error('win32 autostart: spec.name must be a non-empty string');
  }
  if (/[/\\]|\.\./.test(name)) {
    throw new Error(`win32 autostart: spec.name "${name}" must not contain path separators or ..`);
  }
  if (!/^[A-Za-z0-9._-]+$/.test(name)) {
    throw new Error(`win32 autostart: spec.name "${name}" must match [A-Za-z0-9._-]+`);
  }
}

export async function register(spec) {
  validateName(spec.name);

  // Persist the launcher .cmd at <workingDir>/scripts/autostart/<name>.cmd
  // so it survives reboots (tmp/ would be cleared) and lives next to the
  // adapter source for visibility. mkdirSync is recursive + idempotent.
  const launcherDir = path.join(spec.workingDir, 'scripts', 'autostart');
  const launcherPath = path.join(launcherDir, `${spec.name}.cmd`);
  try {
    mkdirSync(launcherDir, { recursive: true });
    writeFileSync(launcherPath, buildLauncher(spec), 'utf8');
  } catch (err) {
    return {
      ok: false,
      mechanism: MECHANISM,
      message: `Failed to write launcher ${launcherPath}: ${err.message}`,
    };
  }

  const xml = buildXml(spec, launcherPath);
  const xmlPath = path.join(tmpdir(), `${spec.name}.xml`);

  // schtasks /Create requires UTF-16 LE with BOM. The leading U+FEFF char
  // + 'utf16le' encoding produces the correct 0xFF 0xFE prefix; without
  // the BOM, schtasks rejects with cryptic "The data is invalid".
  writeFileSync(xmlPath, '﻿' + xml, 'utf16le');

  // Best-effort delete any prior task with this name. /F forces and
  // suppresses the confirm prompt. Errors here are fine — task may not exist.
  spawnSync('schtasks', ['/Delete', '/TN', spec.name, '/F'], { stdio: 'ignore' });

  // Create the new task. /XML imports our generated XML; no other flags
  // override it. We surface stdio so the operator sees any failure
  // (most common: not running as Administrator).
  const r = spawnSync('schtasks', ['/Create', '/XML', xmlPath, '/TN', spec.name], {
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  try { unlinkSync(xmlPath); } catch { /* tmp cleanup best-effort */ }

  if (r.status !== 0) {
    const stderr = (r.stderr || r.stdout || '').trim();
    return {
      ok: false,
      mechanism: MECHANISM,
      message: `schtasks /Create failed (exit ${r.status}). Are you running as Administrator? schtasks output:\n${stderr}`,
    };
  }
  return {
    ok: true,
    mechanism: MECHANISM,
    message: `Scheduled Task "${spec.name}" registered to run at boot via ${launcherPath}.`,
  };
}

export async function unregister(name) {
  const r = spawnSync('schtasks', ['/Delete', '/TN', name, '/F'], {
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  // /Delete on a non-existent task returns exit 1 with "ERROR: The system
  // cannot find the file specified." — treat that as success because
  // unregister is idempotent.
  if (r.status === 0) {
    return { ok: true, mechanism: MECHANISM, message: `Scheduled Task "${name}" removed.` };
  }
  const text = `${r.stderr || ''}${r.stdout || ''}`;
  if (/cannot find/i.test(text)) {
    return { ok: true, mechanism: MECHANISM, message: `Scheduled Task "${name}" was not present (no-op).` };
  }
  return { ok: false, mechanism: MECHANISM, message: `schtasks /Delete failed (exit ${r.status}): ${text.trim()}` };
}

// Internal helpers exported for unit tests only — do not call from
// non-test code. Stable contract is the three async functions above.
export const __test = { buildXml, buildLauncher, validateName, esc };

export async function status(name) {
  const r = spawnSync('schtasks', ['/Query', '/TN', name, '/FO', 'LIST', '/V'], {
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  if (r.status !== 0) {
    return { enabled: false, mechanism: MECHANISM, raw: (r.stderr || r.stdout || '').trim() };
  }
  // Parse the LIST output for the Status field. A task that's been
  // manually disabled in Task Scheduler GUI shows `Status: Disabled`;
  // the prior implementation reported any registered task as enabled
  // regardless of state. The /V flag adds verbose fields including the
  // Status line. `Ready` and `Running` both count as enabled.
  const out = r.stdout || '';
  const statusMatch = out.match(/^\s*(?:Status|Scheduled Task State)\s*:\s*(.+)$/mi);
  const stateValue = statusMatch ? statusMatch[1].trim() : '';
  const enabled = /^(Ready|Running|Enabled)$/i.test(stateValue);
  return { enabled, mechanism: MECHANISM, raw: out.trim() };
}
