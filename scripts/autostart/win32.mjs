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
import { writeFileSync, unlinkSync } from 'node:fs';
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

/** Build the Task Scheduler XML for `spec`. Caller-side validation in
 *  index.mjs has already enforced required fields. */
function buildXml(spec) {
  const envEntries = Object.entries(spec.env || {})
    .map(([k, v]) => `      <Variable><Name>${esc(k)}</Name><Value>${esc(v)}</Value></Variable>`)
    .join('\n');
  const argsString = (spec.args || [])
    .map((a) => `&quot;${esc(a)}&quot;`)
    .join(' ');
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
      <Command>${esc(spec.command)}</Command>
      <Arguments>${argsString}</Arguments>
      <WorkingDirectory>${esc(spec.workingDir)}</WorkingDirectory>${envEntries ? `\n      <Environment>\n${envEntries}\n      </Environment>` : ''}
    </Exec>
  </Actions>
</Task>`;
}

export async function register(spec) {
  const xml = buildXml(spec);
  const xmlPath = path.join(tmpdir(), `${spec.name}.xml`);

  // schtasks /Create requires UTF-16 LE with BOM. Without it, the import
  // fails with cryptic "The data is invalid" at line 1. The leading
  // ﻿ + utf16le encoding is the canonical recipe.
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
  return { ok: true, mechanism: MECHANISM, message: `Scheduled Task "${spec.name}" registered to run at boot.` };
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

export async function status(name) {
  const r = spawnSync('schtasks', ['/Query', '/TN', name, '/FO', 'LIST'], {
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  if (r.status !== 0) {
    return { enabled: false, mechanism: MECHANISM, raw: (r.stderr || r.stdout || '').trim() };
  }
  // /Query returns the task's properties; the presence of the entry is
  // sufficient. Could be extended to detect Disabled state from the output
  // but for now any registered task counts as enabled.
  return { enabled: true, mechanism: MECHANISM, raw: (r.stdout || '').trim() };
}
