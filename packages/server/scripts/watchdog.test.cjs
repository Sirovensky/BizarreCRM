/* eslint-disable no-console */
/**
 * Pure-state-machine tests for the watchdog. No HTTPS, no PM2, no fs —
 * everything is exercised via the exported helpers and mocked deps.
 *
 * Why CJS test alongside CJS watchdog: the watchdog itself is .cjs (PM2
 * runs it without a build step), so colocating the test in .cjs avoids
 * a TS toolchain surface for a 200-line operational script. Run with:
 *
 *   node packages/server/scripts/watchdog.test.cjs
 *
 * Exits 0 on pass, 1 on fail. Output is line-per-test so it's easy to
 * read in PM2 logs or CI output.
 */

const assert = require('node:assert/strict');
const wd = require('./watchdog.cjs');

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ok  ${name}`);
  } catch (err) {
    failed += 1;
    failures.push({ name, err });
    console.log(`  FAIL ${name}`);
    console.log(`       ${err.message}`);
  }
}

const baseOpts = {
  port: 443,
  pollIntervalMs: 30_000,
  failureThreshold: 3,
  longTaskMultiplier: 1.5,
  longTaskMaxMs: 30 * 60 * 1000,
  logCorroborationWindowMs: 60_000,
  cascadeWindowMs: 60 * 60 * 1000,
  cascadeMaxRestarts: 3,
  certErrorThreshold: 5,
  requestTimeoutMs: 5000,
  targetApp: 'bizarre-crm',
};

function noLogActivity() {
  return { activeWithinMs: () => false };
}
function withLogActivity() {
  return { activeWithinMs: () => true };
}

// ─── classifyResponse ──────────────────────────────────────────────────────

console.log('classifyResponse');

test('200 + alive:true + no longTask → healthy', () => {
  assert.equal(
    wd.classifyResponse({ kind: 'success', body: { alive: true, longTask: null } }),
    'healthy',
  );
});

test('200 + alive:true + longTask → long-task', () => {
  assert.equal(
    wd.classifyResponse({
      kind: 'success',
      body: { alive: true, longTask: { kind: 'tenant-migration', expectedDurationMs: 600_000 } },
    }),
    'long-task',
  );
});

test('200 + alive:false → wedge-candidate (server reports unwell)', () => {
  assert.equal(
    wd.classifyResponse({ kind: 'success', body: { alive: false, longTask: null } }),
    'wedge-candidate',
  );
});

test('connection refused (transport-error) → wedge-candidate', () => {
  assert.equal(wd.classifyResponse({ kind: 'transport-error', code: 'ECONNREFUSED' }), 'wedge-candidate');
});

test('http 500 → wedge-candidate', () => {
  assert.equal(wd.classifyResponse({ kind: 'http-error', statusCode: 500 }), 'wedge-candidate');
});

test('cert-error stays cert-error path', () => {
  assert.equal(wd.classifyResponse({ kind: 'cert-error', code: 'CERT_HAS_EXPIRED' }), 'cert-error');
});

// ─── computeWedgeThresholdMs ───────────────────────────────────────────────

console.log('computeWedgeThresholdMs');

test('no longTask → base = failureThreshold * pollIntervalMs', () => {
  const s = wd.createState();
  assert.equal(wd.computeWedgeThresholdMs(s, baseOpts), 3 * 30_000); // 90s
});

test('longTask 600s × 1.5 → 900_000ms', () => {
  const s = wd.createState();
  s.activeLongTask = { kind: 'tenant-migration', expectedDurationMs: 600_000 };
  assert.equal(wd.computeWedgeThresholdMs(s, baseOpts), 900_000);
});

test('longTask × multiplier capped at longTaskMaxMs (30 min)', () => {
  const s = wd.createState();
  s.activeLongTask = { kind: 'huge', expectedDurationMs: 60 * 60 * 1000 }; // 1h × 1.5 = 1.5h
  assert.equal(wd.computeWedgeThresholdMs(s, baseOpts), 30 * 60 * 1000);
});

test('longTask threshold never below base (e.g. tiny longTask)', () => {
  const s = wd.createState();
  s.activeLongTask = { kind: 'small', expectedDurationMs: 1000 };
  assert.equal(wd.computeWedgeThresholdMs(s, baseOpts), 3 * 30_000);
});

// ─── applyClassification ───────────────────────────────────────────────────

console.log('applyClassification');

test('healthy resets all counters', () => {
  const s = wd.createState();
  s.consecutiveWedgeCount = 5;
  s.consecutiveCertErrorCount = 3;
  s.postRestartWedgeCount = 4;
  s.fatalEmitted = true;
  const decision = wd.applyClassification(s, 'healthy', baseOpts, Date.now(), noLogActivity());
  assert.equal(decision.action, 'noop');
  assert.equal(s.consecutiveWedgeCount, 0);
  assert.equal(s.consecutiveCertErrorCount, 0);
  assert.equal(s.postRestartWedgeCount, 0);
  assert.equal(s.fatalEmitted, false);
});

test('long-task does not increment wedge counter', () => {
  const s = wd.createState();
  for (let i = 0; i < 10; i += 1) {
    wd.applyClassification(s, 'long-task', baseOpts, Date.now(), noLogActivity());
  }
  assert.equal(s.consecutiveWedgeCount, 0);
});

test('3 consecutive wedge-candidates triggers restart', () => {
  const s = wd.createState();
  const now = Date.now();
  let last;
  for (let i = 0; i < 3; i += 1) {
    last = wd.applyClassification(s, 'wedge-candidate', baseOpts, now + i * baseOpts.pollIntervalMs, noLogActivity());
  }
  assert.equal(last.action, 'restart');
  assert.equal(s.restartTimestamps.length, 1);
});

test('log-corroboration → extend-grace instead of restart', () => {
  const s = wd.createState();
  const now = Date.now();
  let last;
  for (let i = 0; i < 3; i += 1) {
    last = wd.applyClassification(s, 'wedge-candidate', baseOpts, now + i * baseOpts.pollIntervalMs, withLogActivity());
  }
  assert.equal(last.action, 'extend-grace');
  // Restart not triggered, no restart timestamp recorded.
  assert.equal(s.restartTimestamps.length, 0);
});

test('long-task active extends threshold — no restart at base 3-poll mark', () => {
  const s = wd.createState();
  s.activeLongTask = { kind: 'tenant-migration', expectedDurationMs: 600_000 }; // → 900s threshold
  const now = Date.now();
  let last;
  // 5 consecutive wedge-candidates × 30s = 150s elapsed, way under 900s threshold
  for (let i = 0; i < 5; i += 1) {
    last = wd.applyClassification(s, 'wedge-candidate', baseOpts, now + i * baseOpts.pollIntervalMs, noLogActivity());
  }
  assert.equal(last.action, 'noop');
  assert.equal(s.restartTimestamps.length, 0);
});

test('cascade: 3 prior restarts in window blocks 4th and emits cascade-abort', () => {
  const s = wd.createState();
  const now = Date.now();
  // Stuff 3 prior restarts inside the cascade window
  s.restartTimestamps = [now - 60_000, now - 30_000, now - 10_000];
  // Simulate 3 wedge-candidates → would normally restart, but cascade should block
  let last;
  for (let i = 0; i < 3; i += 1) {
    last = wd.applyClassification(s, 'wedge-candidate', baseOpts, now + i * baseOpts.pollIntervalMs, noLogActivity());
  }
  assert.equal(last.action, 'cascade-abort');
  // No new timestamp should have been added
  assert.equal(s.restartTimestamps.length, 3);
});

test('cascade window expires, fresh restarts allowed again', () => {
  const s = wd.createState();
  const now = Date.now();
  // Old restarts outside the window — should be filtered out
  s.restartTimestamps = [
    now - (baseOpts.cascadeWindowMs + 10_000),
    now - (baseOpts.cascadeWindowMs + 20_000),
    now - (baseOpts.cascadeWindowMs + 30_000),
  ];
  let last;
  for (let i = 0; i < 3; i += 1) {
    last = wd.applyClassification(s, 'wedge-candidate', baseOpts, now + i * baseOpts.pollIntervalMs, noLogActivity());
  }
  assert.equal(last.action, 'restart');
});

test('cert-error: 5 consecutive triggers cert-expired-alarm, NOT restart', () => {
  const s = wd.createState();
  let last;
  for (let i = 0; i < 5; i += 1) {
    last = wd.applyClassification(s, 'cert-error', baseOpts, Date.now(), noLogActivity());
  }
  assert.equal(last.action, 'cert-expired-alarm');
  assert.equal(s.restartTimestamps.length, 0);
});

test('cert-error counter resets on healthy poll', () => {
  const s = wd.createState();
  for (let i = 0; i < 3; i += 1) {
    wd.applyClassification(s, 'cert-error', baseOpts, Date.now(), noLogActivity());
  }
  assert.equal(s.consecutiveCertErrorCount, 3);
  wd.applyClassification(s, 'healthy', baseOpts, Date.now(), noLogActivity());
  assert.equal(s.consecutiveCertErrorCount, 0);
});

test('healthy after wedge resets postRestartWedgeCount and fatalEmitted', () => {
  const s = wd.createState();
  s.postRestartWedgeCount = 4;
  s.fatalEmitted = true;
  wd.applyClassification(s, 'healthy', baseOpts, Date.now(), noLogActivity());
  assert.equal(s.postRestartWedgeCount, 0);
  assert.equal(s.fatalEmitted, false);
});

test('persistent wedges escalate from restart → cascade-abort within ≤4 cycles', () => {
  const s = wd.createState();
  const now = Date.now();
  // Drive consecutive 3-poll wedge cycles. Each cycle of 3 wedge-candidates
  // crosses the threshold once. With cascadeMaxRestarts=3, the 4th cycle
  // must emit cascade-abort instead of a 4th restart.
  const seen = new Set();
  for (let cycle = 0; cycle < 4; cycle += 1) {
    let decision;
    for (let i = 0; i < 3; i += 1) {
      decision = wd.applyClassification(
        s,
        'wedge-candidate',
        baseOpts,
        now + cycle * 60_000 + i * baseOpts.pollIntervalMs,
        noLogActivity(),
      );
    }
    seen.add(decision.action);
  }
  assert.ok(seen.has('restart'), `expected at least one restart, saw ${[...seen].join(',')}`);
  assert.ok(seen.has('cascade-abort'), `expected cascade-abort by cycle 4, saw ${[...seen].join(',')}`);
  assert.equal(s.restartTimestamps.length, 3, 'cascade should block 4th restart');
  assert.equal(s.fatalEmitted, true);
});

// ─── Reporting ─────────────────────────────────────────────────────────────

console.log('');
console.log(`${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log('');
  console.log('Failures:');
  for (const { name, err } of failures) {
    console.log(`  ${name}`);
    console.log(`    ${err.stack || err.message}`);
  }
  process.exit(1);
}
process.exit(0);
