/**
 * Request Rate Counter
 *
 * In-memory circular buffer tracking request counts per second.
 * Used by the management dashboard to display requests/sec and requests/min.
 */

const WINDOW_SECONDS = 60;
const buckets: number[] = new Array(WINDOW_SECONDS).fill(0);
let currentBucketIndex = 0;
let lastBucketTime = Math.floor(Date.now() / 1000);

function advanceBuckets(): void {
  const now = Math.floor(Date.now() / 1000);
  const elapsed = now - lastBucketTime;

  if (elapsed <= 0) return;

  // Clear buckets that have been passed
  const toClear = Math.min(elapsed, WINDOW_SECONDS);
  for (let i = 0; i < toClear; i++) {
    currentBucketIndex = (currentBucketIndex + 1) % WINDOW_SECONDS;
    buckets[currentBucketIndex] = 0;
  }
  lastBucketTime = now;
}

export function recordRequest(): void {
  advanceBuckets();
  buckets[currentBucketIndex]++;
}

export function getRequestsPerMinute(): number {
  advanceBuckets();
  let total = 0;
  for (let i = 0; i < WINDOW_SECONDS; i++) {
    total += buckets[i];
  }
  return total;
}

export function getRequestsPerSecond(): number {
  return Math.round((getRequestsPerMinute() / WINDOW_SECONDS) * 100) / 100;
}
