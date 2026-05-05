/* eslint-disable no-console */
/**
 * Cross-platform health watchdog for BizarreCRM.
 *
 * Runs as a separate PM2 app (`bizarre-crm-watchdog` in ecosystem.config.js)
 * and polls the server's liveness endpoint to catch the failure mode PM2
 * itself cannot detect: process alive, but event loop wedged.
 *
 * Failure cascade:
 *   1. liveness fails 3 times in a row (default 90s) → pm2 restart bizarre-crm
 *   2. liveness keeps failing 5 times after restart  → pm2 stop bizarre-crm + dashboard alarm
 *   3. > 3 watchdog-triggered restarts in 1 hour     → cascade abort + alarm
 *
 * Long-task awareness: when /health/live payload includes a `longTask` block,
 * the wedge threshold extends to longTask.expectedDurationMs * multiplier
 * (default 1.5x), capped at 30 minutes. This is how migrations + bulk imports
 * avoid being killed by the watchdog.
 *
 * Log corroboration: before any destructive action (restart or stop), the
 * watchdog tails `logs/bizarre-crm.{out,err}.log` for the last
 * `WATCHDOG_LOG_CORROBORATION_WINDOW_MS` and skips the action if the server
 * has been logging within that window — server is doing SOMETHING, not
 * dead. Belt-and-suspenders against false-positive restarts.
 *
 * The watchdog NEVER calls process.exit() except from signal handlers. PM2
 * supervises the watchdog itself — let crashes happen and PM2 restart it.
 *
 * Tunables (env vars):
 *   WATCHDOG_POLL_INTERVAL_MS              (default 30000)
 *   WATCHDOG_FAILURE_THRESHOLD             (default 3)
 *   WATCHDOG_LONG_TASK_MULTIPLIER          (default 1.5)
 *   WATCHDOG_LONG_TASK_MAX_MS              (default 1800000 = 30 min)
 *   WATCHDOG_LOG_CORROBORATION_WINDOW_MS   (default 60000)
 *   WATCHDOG_CASCADE_WINDOW_MS             (default 3600000 = 1 hour)
 *   WATCHDOG_CASCADE_MAX_RESTARTS          (default 3)
 *   WATCHDOG_CERT_ERROR_THRESHOLD          (default 5)
 *   WATCHDOG_REQUEST_TIMEOUT_MS            (default 5000)
 *   WATCHDOG_TARGET_APP                    (default 'bizarre-crm')
 *
 * The watchdog and its state machine are intentionally extracted so they can
 * be unit-tested without touching real HTTPS, real PM2, or real fs.
 */

const https = require('node:https');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

// ─── State machine (pure, exportable for tests) ────────────────────────────

/**
 * Build a fresh state object. Centralized so tests can stand up a clean
 * machine, mutate it deterministically, and assert on transitions without
 * any I/O.
 */
function createState() {
  return {
    consecutiveWedgeCount: 0,
    consecutiveCertErrorCount: 0,
    /** Wall-clock timestamps of watchdog-triggered restarts. */
    restartTimestamps: [],
    /**
     * After we restart bizarre-crm, count how many wedge-candidates we see
     * before declaring fatal. Reset to 0 on first healthy poll.
     */
    postRestartWedgeCount: 0,
    /** Last classification produced by classifyResponse. */
    lastClassification: null,
    /** Most recent longTask snapshot from the server (or null). */
    activeLongTask: null,
    /** True if the watchdog has emitted a fatal event for this slump. */
    fatalEmitted: false,
  };
}

/**
 * Compute the dynamic wedge threshold in milliseconds for the current state.
 *
 * Default = WATCHDOG_FAILURE_THRESHOLD * WATCHDOG_POLL_INTERVAL_MS.
 *
 * If a longTask is active, the threshold extends to
 *   longTask.expectedDurationMs * WATCHDOG_LONG_TASK_MULTIPLIER
 * but never beyond WATCHDOG_LONG_TASK_MAX_MS.
 */
function computeWedgeThresholdMs(state, opts) {
  const baseMs = opts.failureThreshold * opts.pollIntervalMs;
  if (state.activeLongTask && typeof state.activeLongTask.expectedDurationMs === 'number') {
    const extended = Math.min(
      state.activeLongTask.expectedDurationMs * opts.longTaskMultiplier,
      opts.longTaskMaxMs,
    );
    return Math.max(baseMs, extended);
  }
  return baseMs;
}

/**
 * Classify a poll outcome. Pure function — no I/O. Returns one of:
 *   'healthy'         — 200 + alive: true, no longTask
 *   'long-task'       — 200 + alive: true + longTask populated
 *   'wedge-candidate' — connection refused, timeout, 5xx, or anything else
 *                       that isn't an explicit alive: true
 *   'cert-error'      — TLS handshake / certificate failure
 */
function classifyResponse(result) {
  if (result.kind === 'cert-error') return 'cert-error';
  if (result.kind === 'http-error') return 'wedge-candidate';
  if (result.kind === 'transport-error') return 'wedge-candidate';
  if (result.kind === 'success') {
    if (!result.body || result.body.alive !== true) return 'wedge-candidate';
    if (result.body.longTask) return 'long-task';
    return 'healthy';
  }
  return 'wedge-candidate';
}

/**
 * Apply a classification to the state and emit the action the watchdog
 * should take. Side-effect-free: the caller is responsible for executing
 * any returned action (pm2 restart, pm2 stop, dashboard event).
 *
 * Returns one of:
 *   { action: 'noop' }
 *   { action: 'extend-grace', reason }
 *   { action: 'restart', reason }
 *   { action: 'stop-and-fatal', reason }
 *   { action: 'cert-expired-alarm', reason }
 *   { action: 'cascade-abort', reason }
 */
function applyClassification(state, classification, opts, now, logCorroboration) {
  state.lastClassification = classification;

  // ── Healthy / long-task: reset counters ────────────────────────────────
  if (classification === 'healthy') {
    state.activeLongTask = null;
    state.consecutiveWedgeCount = 0;
    state.consecutiveCertErrorCount = 0;
    state.postRestartWedgeCount = 0;
    state.fatalEmitted = false;
    return { action: 'noop' };
  }

  if (classification === 'long-task') {
    state.consecutiveWedgeCount = 0;
    state.consecutiveCertErrorCount = 0;
    state.postRestartWedgeCount = 0;
    state.fatalEmitted = false;
    return { action: 'noop' };
  }

  // ── Cert error path ────────────────────────────────────────────────────
  if (classification === 'cert-error') {
    state.consecutiveCertErrorCount += 1;
    state.consecutiveWedgeCount = 0;
    if (state.consecutiveCertErrorCount >= opts.certErrorThreshold && !state.fatalEmitted) {
      state.fatalEmitted = true;
      return {
        action: 'cert-expired-alarm',
        reason: `Cert handshake failed ${state.consecutiveCertErrorCount} consecutive times.`,
      };
    }
    return { action: 'noop' };
  }

  // ── Wedge candidate ────────────────────────────────────────────────────
  state.consecutiveWedgeCount += 1;
  state.consecutiveCertErrorCount = 0;

  const thresholdMs = computeWedgeThresholdMs(state, opts);
  const wedgeElapsedMs = state.consecutiveWedgeCount * opts.pollIntervalMs;

  if (wedgeElapsedMs < thresholdMs) {
    return { action: 'noop' };
  }

  // Threshold crossed. Cascade check FIRST — if we've already restarted N
  // times in the rolling window, do not restart again.
  const cutoff = now - opts.cascadeWindowMs;
  state.restartTimestamps = state.restartTimestamps.filter((t) => t >= cutoff);
  if (state.restartTimestamps.length >= opts.cascadeMaxRestarts) {
    if (!state.fatalEmitted) {
      state.fatalEmitted = true;
      return {
        action: 'cascade-abort',
        reason: `${state.restartTimestamps.length} watchdog-triggered restarts in last ${Math.round(opts.cascadeWindowMs / 60000)} min.`,
      };
    }
    return { action: 'noop' };
  }

  // Log corroboration: if the server has logged anything recently, prefer
  // extending grace over destructive action. The corroboration check is
  // injected by the caller so tests can mock it.
  if (logCorroboration && logCorroboration.activeWithinMs(opts.logCorroborationWindowMs)) {
    return {
      action: 'extend-grace',
      reason: `Liveness unresponsive for ${wedgeElapsedMs}ms but server logged activity within ${opts.logCorroborationWindowMs}ms. Extending grace.`,
    };
  }

  // If we already restarted recently and bizarre-crm is wedging again,
  // escalate to fatal-stop instead of another restart.
  state.postRestartWedgeCount += 1;
  if (state.postRestartWedgeCount >= opts.failureThreshold + 2 && state.restartTimestamps.length > 0) {
    if (!state.fatalEmitted) {
      state.fatalEmitted = true;
      return {
        action: 'stop-and-fatal',
        reason: `Wedge persists ${state.postRestartWedgeCount} polls after watchdog-triggered restart.`,
      };
    }
    return { action: 'noop' };
  }

  state.restartTimestamps.push(now);
  state.consecutiveWedgeCount = 0;
  return {
    action: 'restart',
    reason: `Liveness unresponsive for ${wedgeElapsedMs}ms (threshold ${thresholdMs}ms).`,
  };
}

// ─── Liveness probe (real I/O) ─────────────────────────────────────────────

/**
 * Hit the liveness endpoint. Returns a structured outcome the state machine
 * can classify.
 *
 * Self-signed cert is allowed via rejectUnauthorized: false because the
 * watchdog runs as a sibling process to the server and only ever talks to
 * localhost. We still differentiate cert errors from generic transport
 * errors so the cert-expired alarm path can fire.
 */
function probeLiveness(opts) {
  return new Promise((resolve) => {
    const url = `https://localhost:${opts.port}/api/v1/health/live`;
    const req = https.request(
      url,
      {
        method: 'GET',
        timeout: opts.requestTimeoutMs,
        rejectUnauthorized: false,
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          if (res.statusCode !== 200) {
            resolve({ kind: 'http-error', statusCode: res.statusCode });
            return;
          }
          try {
            const text = Buffer.concat(chunks).toString('utf8');
            const json = JSON.parse(text);
            // Server responds with { success: true, data: { alive, longTask, ts } }
            const data = json && json.data ? json.data : json;
            resolve({ kind: 'success', body: data });
          } catch (err) {
            resolve({ kind: 'http-error', statusCode: res.statusCode, parseError: err && err.message });
          }
        });
      },
    );
    req.on('timeout', () => {
      req.destroy(new Error('watchdog request timeout'));
    });
    req.on('error', (err) => {
      const code = err && err.code;
      // Map known TLS errors to cert-error path so a real expired cert
      // surfaces as a different alarm than a wedged event loop.
      // We INTENTIONALLY do NOT match on err.message substrings — earlier
      // versions did and risked DNS / network errors whose message strings
      // happened to contain "certificate" (e.g. some EAI_AGAIN aggregations)
      // being silently routed to cert-error and never triggering a restart.
      // Strict code-based match keeps the cert-error path narrow.
      const TLS_CERT_CODES = new Set([
        'CERT_HAS_EXPIRED',
        'DEPTH_ZERO_SELF_SIGNED_CERT',
        'SELF_SIGNED_CERT_IN_CHAIN',
        'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
        'ERR_TLS_CERT_ALTNAME_INVALID',
        'CERT_NOT_YET_VALID',
        'CERT_REJECTED',
      ]);
      if (typeof code === 'string' && TLS_CERT_CODES.has(code)) {
        // Self-signed local certs hit DEPTH_ZERO_SELF_SIGNED_CERT but we set
        // rejectUnauthorized:false, so this branch is only reached for true
        // cert-validation faults the OS layer surfaced. Treat as cert-error.
        resolve({ kind: 'cert-error', code, message: err.message });
        return;
      }
      resolve({ kind: 'transport-error', code, message: err && err.message });
    });
    req.end();
  });
}

// ─── Log-corroboration helper ──────────────────────────────────────────────

/**
 * Build an object that can answer "has the server logged anything within
 * the last N ms?" by stat()-ing the PM2 log files. We intentionally do NOT
 * read file contents — file mtime advancing is sufficient signal. Cheap
 * and works on every platform.
 */
function buildLogCorroboration(repoRoot) {
  const candidates = [
    path.join(repoRoot, 'logs', 'bizarre-crm.out.log'),
    path.join(repoRoot, 'logs', 'bizarre-crm.err.log'),
  ];
  return {
    activeWithinMs(windowMs) {
      const cutoff = Date.now() - windowMs;
      for (const file of candidates) {
        try {
          const stat = fs.statSync(file);
          if (stat.mtimeMs >= cutoff) return true;
        } catch {
          /* file may not exist yet on a brand-new install */
        }
      }
      return false;
    },
  };
}

// ─── PM2 control ───────────────────────────────────────────────────────────

/**
 * Run a PM2 command. We spawn the CLI rather than using the programmatic
 * API to avoid PM2's daemon-connection lifecycle (a second source of bugs).
 *
 * All commands are hardcoded — no interpolation, no shell. The caller never
 * passes user input here; the only argv entries come from constants.
 */
function runPm2(args) {
  return new Promise((resolve) => {
    const proc = spawn('pm2', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    proc.stdout.on('data', (c) => {
      out += c.toString('utf8');
    });
    proc.stderr.on('data', (c) => {
      err += c.toString('utf8');
    });
    proc.on('error', (e) => {
      resolve({ ok: false, code: null, stdout: out, stderr: `spawn error: ${e.message}` });
    });
    proc.on('exit', (code) => {
      resolve({ ok: code === 0, code, stdout: out, stderr: err });
    });
  });
}

// ─── Dashboard event emission (best-effort) ────────────────────────────────

/**
 * Dashboard events are written to a small JSONL file the management process
 * tails. Server-side broadcast over WebSocket is preferred where the watchdog
 * is a sibling of a running server, but during a wedge the WebSocket might
 * not be reachable. The JSONL file is the durable channel.
 *
 * Path: <repoRoot>/logs/watchdog-events.jsonl
 *
 * Each line is one event; the dashboard reads the tail when ServerControlPage
 * mounts and subscribes to file changes.
 */
function emitWatchdogEvent(repoRoot, event) {
  const file = path.join(repoRoot, 'logs', 'watchdog-events.jsonl');
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.appendFileSync(file, JSON.stringify(event) + '\n', { encoding: 'utf8' });
  } catch (err) {
    // best-effort — log to stdout so PM2 captures it even if disk is read-only
    console.error('[watchdog] failed to append event to logs/watchdog-events.jsonl', err && err.message);
  }
}

// ─── Tunables loader ───────────────────────────────────────────────────────

function intEnv(name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return fallback;
  // Clamp to keep the watchdog loop sane: a zero / negative pollIntervalMs
  // would busy-loop the process, and a huge max-restarts threshold would
  // hide real wedges. Clamping is intentional silent fallback to defaults
  // — a console warning would spam every 30s on every rerun.
  if (parsed < min) return Math.max(fallback, min);
  if (parsed > max) return max;
  return parsed;
}
function floatEnv(name, fallback, { min = 0, max = Number.MAX_VALUE } = {}) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = parseFloat(raw);
  if (!Number.isFinite(parsed)) return fallback;
  if (parsed < min) return Math.max(fallback, min);
  if (parsed > max) return max;
  return parsed;
}
function strEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  return raw;
}

function loadOptions() {
  // All clamps are minimums; ceilings prevent absurd values (e.g. one-day
  // poll interval) that would defeat the watchdog. PORT is allowed to be
  // any 1-65535 so dev / co-tenant deployments work.
  return {
    port: intEnv('PORT', 443, { min: 1, max: 65535 }),
    pollIntervalMs: intEnv('WATCHDOG_POLL_INTERVAL_MS', 30_000, { min: 1000, max: 5 * 60_000 }),
    failureThreshold: intEnv('WATCHDOG_FAILURE_THRESHOLD', 3, { min: 1, max: 50 }),
    longTaskMultiplier: floatEnv('WATCHDOG_LONG_TASK_MULTIPLIER', 1.5, { min: 1, max: 10 }),
    longTaskMaxMs: intEnv('WATCHDOG_LONG_TASK_MAX_MS', 30 * 60 * 1000, { min: 60_000, max: 24 * 60 * 60 * 1000 }),
    logCorroborationWindowMs: intEnv('WATCHDOG_LOG_CORROBORATION_WINDOW_MS', 60_000, { min: 5_000, max: 30 * 60 * 1000 }),
    cascadeWindowMs: intEnv('WATCHDOG_CASCADE_WINDOW_MS', 60 * 60 * 1000, { min: 5 * 60_000, max: 24 * 60 * 60 * 1000 }),
    cascadeMaxRestarts: intEnv('WATCHDOG_CASCADE_MAX_RESTARTS', 3, { min: 1, max: 100 }),
    certErrorThreshold: intEnv('WATCHDOG_CERT_ERROR_THRESHOLD', 5, { min: 1, max: 50 }),
    requestTimeoutMs: intEnv('WATCHDOG_REQUEST_TIMEOUT_MS', 5000, { min: 500, max: 60_000 }),
    targetApp: strEnv('WATCHDOG_TARGET_APP', 'bizarre-crm'),
  };
}

function resolveRepoRoot() {
  // ecosystem.config.js sets cwd to repo root; fallback to ../../ relative
  // to this file (packages/server/scripts/watchdog.cjs → repo root).
  return process.cwd().endsWith(path.join('packages', 'server'))
    ? path.resolve(process.cwd(), '..', '..')
    : process.cwd();
}

// ─── Main loop ─────────────────────────────────────────────────────────────

async function tick(state, opts, deps) {
  const result = await deps.probe(opts);
  // Capture longTask snapshot if liveness payload included one — used by
  // the threshold extension on the NEXT poll.
  state.activeLongTask = result.kind === 'success' && result.body && result.body.longTask
    ? result.body.longTask
    : null;

  const classification = deps.classify(result);
  const decision = deps.apply(state, classification, opts, Date.now(), deps.logCorroboration);

  if (decision.action === 'noop') return decision;

  console.log(`[watchdog] ${decision.action}: ${decision.reason}`);

  if (decision.action === 'restart') {
    deps.emit({
      kind: 'restart',
      timestamp: new Date().toISOString(),
      reason: decision.reason,
      longTask: state.activeLongTask,
    });
    const r = await deps.pm2(['restart', opts.targetApp]);
    if (!r.ok) {
      console.error(`[watchdog] pm2 restart failed (code=${r.code}): ${r.stderr}`);
    }
  } else if (decision.action === 'stop-and-fatal' || decision.action === 'cascade-abort') {
    deps.emit({
      kind: 'fatal',
      timestamp: new Date().toISOString(),
      reason: decision.reason,
      cascadeAbort: decision.action === 'cascade-abort',
    });
    const r = await deps.pm2(['stop', opts.targetApp]);
    if (!r.ok) {
      console.error(`[watchdog] pm2 stop failed (code=${r.code}): ${r.stderr}`);
    }
  } else if (decision.action === 'extend-grace') {
    deps.emit({
      kind: 'extended-grace',
      timestamp: new Date().toISOString(),
      reason: decision.reason,
    });
  } else if (decision.action === 'cert-expired-alarm') {
    deps.emit({
      kind: 'cert-expired',
      timestamp: new Date().toISOString(),
      reason: decision.reason,
    });
  }

  return decision;
}

async function main() {
  const opts = loadOptions();
  const repoRoot = resolveRepoRoot();
  const state = createState();
  const logCorroboration = buildLogCorroboration(repoRoot);

  console.log(
    `[watchdog] starting; targetApp=${opts.targetApp} port=${opts.port} pollIntervalMs=${opts.pollIntervalMs} failureThreshold=${opts.failureThreshold}`,
  );

  let stopping = false;
  const onSignal = (sig) => {
    console.log(`[watchdog] received ${sig}, exiting cleanly`);
    stopping = true;
  };
  process.on('SIGTERM', () => onSignal('SIGTERM'));
  process.on('SIGINT', () => onSignal('SIGINT'));

  const deps = {
    probe: probeLiveness,
    classify: classifyResponse,
    apply: applyClassification,
    pm2: runPm2,
    emit: (event) => emitWatchdogEvent(repoRoot, event),
    logCorroboration,
  };

  // Tick loop — sleep between polls; never spin.
  while (!stopping) {
    try {
      await tick(state, opts, deps);
    } catch (err) {
      // Errors here are watchdog bugs, not server bugs. Log loudly so PM2
      // captures them, then keep going — PM2 will restart us if we crash
      // outright.
      console.error('[watchdog] tick threw', err && (err.stack || err.message));
    }
    await new Promise((r) => setTimeout(r, opts.pollIntervalMs));
  }

  console.log('[watchdog] exit 0');
  process.exit(0);
}

// Run the loop only when this file is the entrypoint (PM2 will do this).
// Imports from tests are no-ops.
if (require.main === module) {
  main().catch((err) => {
    console.error('[watchdog] fatal in main():', err && (err.stack || err.message));
    process.exit(1);
  });
}

module.exports = {
  // Pure helpers (testable without I/O)
  createState,
  classifyResponse,
  applyClassification,
  computeWedgeThresholdMs,
  // I/O wrappers (mockable in tests)
  probeLiveness,
  buildLogCorroboration,
  runPm2,
  emitWatchdogEvent,
  loadOptions,
  resolveRepoRoot,
  tick,
};
