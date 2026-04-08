/**
 * Simple in-memory LRU cache with TTL expiration.
 * Use for expensive aggregation queries (dashboard KPIs, reports).
 * NOT a distributed cache — single-process only.
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

    // Evict oldest if at capacity
    if (this.store.size >= this.maxSize) {
      const oldestKey = this.store.keys().next().value;
      if (oldestKey !== undefined) {
        this.store.delete(oldestKey);
      }
    }

    this.store.set(key, {
      value,
      expiresAt: Date.now() + (ttlMs ?? this.defaultTtlMs),
    });
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
