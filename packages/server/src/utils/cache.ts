/**
 * Simple in-memory LRU cache with TTL expiration.
 * Use for expensive aggregation queries (dashboard KPIs, reports).
 * NOT a distributed cache — single-process only.
 *
 * Single-flight (promise deduplication) is built into `getCached`:
 * concurrent misses on the same key share a single loader invocation.
 */

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export class LRUCache<T = unknown> {
  private readonly maxSize: number;
  private readonly defaultTtlMs: number;
  private readonly store = new Map<string, CacheEntry<T>>();

  /**
   * Inflight loader promises keyed by cache key.
   * When a miss occurs and a loader is already running for that key, new
   * callers await the existing promise instead of starting a second loader.
   * The entry is always removed when the loader settles (resolve OR reject)
   * so subsequent misses after TTL expiry can trigger a fresh load.
   */
  private readonly inflight = new Map<string, Promise<T>>();

  /**
   * @param maxSize   Maximum number of entries (default 100)
   * @param ttlMs     Default TTL in milliseconds (default 60_000 = 60s)
   */
  constructor(maxSize = 100, ttlMs = 60_000) {
    this.maxSize = maxSize;
    this.defaultTtlMs = ttlMs;
  }

  /** Get a cached value. Returns undefined if missing or expired. */
  get(key: string): T | undefined {
    const entry = this.store.get(key);
    if (!entry) return undefined;

    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return undefined;
    }

    // Move to end (most recently used)
    this.store.delete(key);
    this.store.set(key, entry);
    return entry.value;
  }

  /** Store a value with optional custom TTL (in ms). */
  set(key: string, value: T, ttlMs?: number): void {
    // Delete first so re-insert goes to end of Map iteration order
    this.store.delete(key);

    // @audit-fixed: Before LRU eviction, drop any expired entries so a stale
    // entry never preempts a live one. Without this the oldest entry may be
    // live while several expired entries hog the cap.
    if (this.store.size >= this.maxSize) {
      const now = Date.now();
      for (const [k, entry] of this.store) {
        if (entry.expiresAt <= now) this.store.delete(k);
      }
    }

    // Evict oldest if still at capacity
    if (this.store.size >= this.maxSize) {
      const oldestKey = this.store.keys().next().value;
      if (oldestKey !== undefined) {
        this.store.delete(oldestKey);
      }
    }

    // @audit-fixed: Guard against non-numeric / non-positive TTL from callers
    // so `ttlMs: NaN` doesn't silently produce an immediately-expired entry.
    const effectiveTtl = typeof ttlMs === 'number' && Number.isFinite(ttlMs) && ttlMs > 0
      ? ttlMs
      : this.defaultTtlMs;

    this.store.set(key, {
      value,
      expiresAt: Date.now() + effectiveTtl,
    });
  }

  /**
   * Return the cached value for `key`, or run `loader` once to populate it.
   *
   * Single-flight guarantee: if N concurrent callers miss the same key
   * simultaneously, only ONE loader invocation is started. All N callers
   * await the same promise and receive the same resolved value.
   *
   * On loader rejection:
   *   - The inflight entry is removed so future callers can retry.
   *   - The error is NOT stored in the cache.
   *   - The rejection is propagated to every waiter.
   *
   * @param key     Cache key (same key space used by `get`/`set`).
   * @param loader  Async factory called on a cache miss.
   * @param ttlMs   Optional per-call TTL override (passed through to `set`).
   */
  async getCached(key: string, loader: () => Promise<T>, ttlMs?: number): Promise<T> {
    // Fast path: valid cached value present.
    const hit = this.get(key);
    if (hit !== undefined) return hit;

    // Single-flight: reuse an inflight loader if one is already running.
    const existing = this.inflight.get(key);
    if (existing !== undefined) return existing;

    // Start a new loader and register it before the first await so that
    // any synchronous continuations in the same microtask queue see it.
    const promise: Promise<T> = loader().then(
      (value) => {
        this.inflight.delete(key);
        this.set(key, value, ttlMs);
        return value;
      },
      (err: unknown) => {
        // Always clean up so future misses can retry. Never cache the error.
        this.inflight.delete(key);
        throw err;
      },
    );

    this.inflight.set(key, promise);
    return promise;
  }

  /** Remove a specific key. */
  delete(key: string): boolean {
    return this.store.delete(key);
  }

  /** Remove all entries. */
  clear(): void {
    this.store.clear();
  }

  /** Current number of (possibly expired) entries. */
  get size(): number {
    return this.store.size;
  }
}

/**
 * Shared cache instance for dashboard/report KPIs.
 * 60-second TTL, max 50 entries.
 */
export const dashboardCache = new LRUCache(50, 60_000);
