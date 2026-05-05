// WEB-FV-011 (Fixer-C11 2026-04-25): unify the 30+ ad-hoc try/catch trees
// guarding best-effort side effects (localStorage writes, BroadcastChannel
// fan-out, document.execCommand fallbacks, etc.). Each call site previously
// invented its own /* ignore */ / /* swallow */ / /* non-fatal */ comment
// with no Sentry breadcrumb, so flaky storage / missing globals were silent
// in prod. Standardise on this helper so we get one consistent breadcrumb
// shape and one place to wire ops visibility later.
//
// Intentionally provider-agnostic: this module does NOT import Sentry. If
// `window.Sentry?.addBreadcrumb` is present (loaded by Sentry init in
// `main.tsx`), we record there; otherwise we fall back to console.debug
// behind a dev guard so prod stays silent.

type SafeRunOptions = {
  /** Short label for the operation (`"localStorage:write"`, `"clipboard:fallback"`). */
  tag?: string;
  /** Extra structured fields to attach to the breadcrumb. */
  data?: Record<string, unknown>;
  /** Override the default breadcrumb level. Defaults to `"warning"` on throw. */
  level?: 'debug' | 'info' | 'warning' | 'error';
};

type SentryLike = {
  addBreadcrumb?: (b: {
    category?: string;
    message?: string;
    level?: string;
    data?: Record<string, unknown>;
  }) => void;
};

function record(err: unknown, opts: SafeRunOptions | undefined): void {
  const tag = opts?.tag ?? 'safeRun';
  const message = err instanceof Error ? err.message : String(err);
  const sentry = (typeof window !== 'undefined' ? (window as unknown as { Sentry?: SentryLike }).Sentry : undefined);
  if (sentry?.addBreadcrumb) {
    sentry.addBreadcrumb({
      category: 'safeRun',
      message: `${tag}: ${message}`,
      level: opts?.level ?? 'warning',
      data: opts?.data,
    });
    return;
  }
  if (import.meta.env?.DEV) {
    // eslint-disable-next-line no-console
    console.debug(`[safeRun:${tag}]`, message, opts?.data ?? '');
  }
}

/**
 * Run a synchronous best-effort side effect. Swallows any throw and records
 * a breadcrumb so the failure is auditable. Returns the function's result on
 * success, or `undefined` on throw.
 *
 * @example
 *   safeRun(() => localStorage.setItem('foo', 'bar'), { tag: 'storage:foo' });
 */
export function safeRun<T>(fn: () => T, opts?: SafeRunOptions): T | undefined {
  try {
    return fn();
  } catch (err) {
    record(err, opts);
    return undefined;
  }
}

/**
 * Async variant. Awaits and swallows rejections the same way as the sync
 * variant. Use for fire-and-forget background work where you don't want to
 * block the UI and don't want to escalate to the global onunhandledrejection
 * handler.
 */
export async function safeRunAsync<T>(fn: () => Promise<T>, opts?: SafeRunOptions): Promise<T | undefined> {
  try {
    return await fn();
  } catch (err) {
    record(err, opts);
    return undefined;
  }
}
