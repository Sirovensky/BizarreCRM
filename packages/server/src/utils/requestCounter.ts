/**
 * Request Rate Counter + Response Time Tracker
 *
 * In-memory circular buffer tracking request counts and response times per second.
 * Used by the management dashboard to display real-time metrics.
 */

const WINDOW_SECONDS = 60;
const buckets: number[] = new Array(WINDOW_SECONDS).fill(0);
let currentBucketIndex = 0;
let lastBucketTime = Math.floor(Date.now() / 1000);

// Response time tracking (rolling window)
const RT_WINDOW = 100; // Track last 100 response times
const responseTimes: number[] = [];

function advanceBuckets(): void {
  const now = Math.floor(Date.now() / 1000);
  const elapsed = now - lastBucketTime;

  if (elapsed <= 0) return;

  // @audit-fixed: If elapsed >= WINDOW_SECONDS the ring is fully stale, so
  // wipe every bucket in one pass rather than doing modulo arithmetic that
  // still leaves old data when elapsed == WINDOW_SECONDS exactly.
  if (elapsed >= WINDOW_SECONDS) {
    for (let i = 0; i < WINDOW_SECONDS; i++) buckets[i] = 0;
    currentBucketIndex = 0;
  } else {
    for (let i = 0; i < elapsed; i++) {
      currentBucketIndex = (currentBucketIndex + 1) % WINDOW_SECONDS;
      buckets[currentBucketIndex] = 0;
    }
  }
  lastBucketTime = now;
}

export function recordRequest(): void {
  advanceBuckets();
  buckets[currentBucketIndex]++;
}

export function recordResponseTime(ms: number): void {
  responseTimes.push(ms);
  if (responseTimes.length > RT_WINDOW) responseTimes.shift();
}

export function getRequestsPerMinute(): number {
  advanceBuckets();
  let total = 0;
  for (let i = 0; i < WINDOW_SECONDS; i++) {
    total += buckets[i];
  }
  return total;
}

/** Average req/s over the last 60 seconds */
export function getRequestsPerSecond(): number {
  return Math.round((getRequestsPerMinute() / WINDOW_SECONDS) * 100) / 100;
}

// Track all-time peak since server start (doesn't reset with the 60s window)
let allTimePeak = 0;

/** Peak req/s — highest single-second bucket since server start */
export function getRequestsPerSecondPeak(): number {
  advanceBuckets();
  // Update all-time peak from current window
  for (let i = 0; i < WINDOW_SECONDS; i++) {
    if (buckets[i] > allTimePeak) allTimePeak = buckets[i];
  }
  return allTimePeak;
}

/** Current second's request count (real-time) */
export function getRequestsPerSecondCurrent(): number {
  advanceBuckets();
  return buckets[currentBucketIndex];
}

/** Average response time in ms (last 100 requests) */
export function getAvgResponseTime(): number {
  if (responseTimes.length === 0) return 0;
  const sum = responseTimes.reduce((a, b) => a + b, 0);
  return Math.round((sum / responseTimes.length) * 100) / 100;
}

/** P95 response time in ms */
export function getP95ResponseTime(): number {
  if (responseTimes.length === 0) return 0;
  const sorted = [...responseTimes].sort((a, b) => a - b);
  const idx = Math.floor(sorted.length * 0.95);
  return sorted[idx] ?? 0;
}
