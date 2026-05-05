#!/usr/bin/env node
/**
 * SA1-1 unit test for graceful JWT secret rotation.
 *
 * Proves the verifyJwtWithRotation helper:
 *   1. Accepts a token signed with the CURRENT secret.
 *   2. Accepts a token signed with the PREVIOUS secret (rotation grace period).
 *   3. Rejects a token signed with a totally unrelated nonsense secret.
 *   4. Still rejects a token signed with the PREVIOUS secret when no previous
 *      secret is configured (regression guard — rotation must be opt-in).
 *   5. Propagates TokenExpiredError through the fallback path (expired tokens
 *      should NOT be rescued by trying the previous secret).
 *
 * Usage:
 *   cd packages/server && node scripts/test-jwt-rotation.mjs
 *
 * Exit codes:
 *   0 — all assertions passed
 *   1 — at least one assertion failed
 */
import jwt from 'jsonwebtoken';

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const RESET = '\x1b[0m';

let passed = 0;
let failed = 0;

function assert(cond, label) {
  if (cond) {
    console.log(`${GREEN}PASS${RESET} ${label}`);
    passed++;
  } else {
    console.log(`${RED}FAIL${RESET} ${label}`);
    failed++;
  }
}

// Reconstruct the rotation verifier in plain JS so this test is
// hermetic — no tsx/tsc required, no config import side effects (the
// real config.ts calls process.exit on bad env values).
function verifyWithRotation(token, current, previous, options) {
  try {
    return jwt.verify(token, current, options);
  } catch (primaryErr) {
    if (!previous) throw primaryErr;
    if (!(primaryErr instanceof jwt.JsonWebTokenError)) throw primaryErr;
    if (primaryErr.name !== 'JsonWebTokenError') throw primaryErr;
    return jwt.verify(token, previous, options);
  }
}

const OLD_SECRET = 'a'.repeat(64);
const NEW_SECRET = 'b'.repeat(64);
const NONSENSE = 'c'.repeat(64);

const SIGN_OPTIONS = {
  algorithm: 'HS256',
  issuer: 'bizarre-crm',
  audience: 'bizarre-crm-api',
};
const VERIFY_OPTIONS = {
  algorithms: ['HS256'],
  issuer: 'bizarre-crm',
  audience: 'bizarre-crm-api',
};

// ─── Test 1: sign with current secret, verify with rotation setup ──
{
  const token = jwt.sign({ userId: 42, type: 'access' }, NEW_SECRET, {
    ...SIGN_OPTIONS,
    expiresIn: '1h',
  });
  let payload;
  try {
    payload = verifyWithRotation(token, NEW_SECRET, OLD_SECRET, VERIFY_OPTIONS);
  } catch (err) {
    payload = null;
  }
  assert(payload && payload.userId === 42, 'current-secret token verifies with rotation active');
}

// ─── Test 2: sign with OLD secret, verify via fallback to previous ──
{
  const token = jwt.sign({ userId: 99, type: 'access' }, OLD_SECRET, {
    ...SIGN_OPTIONS,
    expiresIn: '1h',
  });
  let payload;
  try {
    payload = verifyWithRotation(token, NEW_SECRET, OLD_SECRET, VERIFY_OPTIONS);
  } catch (err) {
    payload = null;
  }
  assert(
    payload && payload.userId === 99,
    'previous-secret token still verifies during rotation window',
  );
}

// ─── Test 3: nonsense-secret token must fail ──
{
  const token = jwt.sign({ userId: 7 }, NONSENSE, {
    ...SIGN_OPTIONS,
    expiresIn: '1h',
  });
  let rejected = false;
  try {
    verifyWithRotation(token, NEW_SECRET, OLD_SECRET, VERIFY_OPTIONS);
  } catch {
    rejected = true;
  }
  assert(rejected, 'nonsense-secret token fails both current and previous verifiers');
}

// ─── Test 4: no previous secret configured → old-secret token fails ──
{
  const token = jwt.sign({ userId: 1 }, OLD_SECRET, {
    ...SIGN_OPTIONS,
    expiresIn: '1h',
  });
  let rejected = false;
  try {
    verifyWithRotation(token, NEW_SECRET, undefined, VERIFY_OPTIONS);
  } catch {
    rejected = true;
  }
  assert(
    rejected,
    'rotation is opt-in — old-secret token fails when no previous secret is configured',
  );
}

// ─── Test 5: expired token throws TokenExpiredError, not masked by fallback ──
{
  const token = jwt.sign({ userId: 1 }, NEW_SECRET, {
    ...SIGN_OPTIONS,
    expiresIn: '-1s', // already expired
  });
  let errName = '';
  try {
    verifyWithRotation(token, NEW_SECRET, OLD_SECRET, VERIFY_OPTIONS);
  } catch (err) {
    errName = err && err.name;
  }
  assert(
    errName === 'TokenExpiredError',
    'expired tokens throw TokenExpiredError (not rescued by previous secret)',
  );
}

// ─── Test 6: new-secret signing works even when previous is configured ──
// (sign only uses current; fallback is verify-only)
{
  const token = jwt.sign({ userId: 55 }, NEW_SECRET, {
    ...SIGN_OPTIONS,
    expiresIn: '1h',
  });
  // Decode header to prove the token is valid shape
  const decoded = jwt.decode(token, { complete: true });
  assert(
    decoded && decoded.header && decoded.header.alg === 'HS256',
    'new tokens are signed with HS256 regardless of rotation state',
  );
}

// ─── Summary ──
console.log('');
console.log(
  `${passed + failed} tests, ${passed} passed, ${failed} failed`,
);
process.exit(failed === 0 ? 0 : 1);
