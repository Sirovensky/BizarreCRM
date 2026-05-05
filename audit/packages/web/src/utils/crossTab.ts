/**
 * crossTab — small wrapper around BroadcastChannel for cross-tab signals.
 *
 * WEB-FO-018 (Fixer-C15 2026-04-25): the codebase signals events between
 * components via per-tab `window.dispatchEvent(new CustomEvent(...))`, which
 * never reaches sibling tabs. The few cross-tab paths we have (impersonation
 * banner, training banner) ride on `storage` events, which only fire on
 * different tabs and require a localStorage write per signal.
 *
 * BroadcastChannel is the right tool for "this user just logged out / changed
 * theme / upgraded plan" → notify every other tab in the same origin.
 *
 * Channels we expect to use (callers own the names; this helper is generic):
 *   - "bizarre-crm:auth"    → { type: 'logout' | 'login' | 'token-refreshed' }
 *   - "bizarre-crm:theme"   → { type: 'theme-changed', theme: 'light'|'dark' }
 *   - "bizarre-crm:plan"    → { type: 'plan-upgraded' | 'plan-downgraded' }
 *   - "bizarre-pos:cart"    → { type: 'cart-cleared' | 'sale-completed' }
 *   - "bizarre-crm:kiosk"   → { type: 'switch-user', user_id: number }
 *
 * Browser support: BroadcastChannel ships in every modern browser including
 * Safari ≥ 15.4 (2022-03). We fall back to a `storage` event ping for older
 * Safari so the receive side fires; the message body is JSON-serialized and
 * the localStorage key is removed immediately so we don't waste quota.
 */

type Listener<T> = (msg: T) => void;

interface ChannelHandle<T> {
  /** Send a message to every OTHER tab on this origin. The current tab does NOT receive its own messages. */
  post: (msg: T) => void;
  /** Subscribe to messages from other tabs. Returns an unsubscribe function. */
  subscribe: (fn: Listener<T>) => () => void;
  /** Tear down all listeners and close the channel. Idempotent. */
  close: () => void;
}

/**
 * Open (or reuse) a cross-tab channel by name. Each call returns a new handle
 * but underlying BroadcastChannel instances are not deduped — callers should
 * keep their handle for the lifetime of the consumer (typically a `useEffect`).
 */
export function openCrossTabChannel<T = unknown>(name: string): ChannelHandle<T> {
  // Feature-detect. Some embedded webviews (Safari < 15.4 in particular)
  // expose `window` but not BroadcastChannel.
  const supported = typeof BroadcastChannel !== 'undefined';

  if (supported) {
    const bc = new BroadcastChannel(name);
    const listeners = new Set<Listener<T>>();
    const onMessage = (ev: MessageEvent) => {
      for (const fn of listeners) {
        try {
          fn(ev.data as T);
        } catch {
          // Listener errors must not break sibling listeners — swallow.
        }
      }
    };
    bc.addEventListener('message', onMessage);
    return {
      post: (msg) => {
        try {
          bc.postMessage(msg);
        } catch {
          // postMessage on a closed channel throws — ignore.
        }
      },
      subscribe: (fn) => {
        listeners.add(fn);
        return () => listeners.delete(fn);
      },
      close: () => {
        listeners.clear();
        bc.removeEventListener('message', onMessage);
        try {
          bc.close();
        } catch {
          /* noop */
        }
      },
    };
  }

  // Fallback path (Safari < 15.4, some kiosk webviews): emulate cross-tab
  // signal via a transient localStorage key. We write the message JSON-encoded
  // with a timestamp suffix to force `storage` event subscribers to see a
  // distinct value even when the same payload is sent twice in a row.
  const storageKey = `__crossTab__:${name}`;
  const listeners = new Set<Listener<T>>();
  const onStorage = (ev: StorageEvent) => {
    if (ev.key !== storageKey || !ev.newValue) return;
    try {
      const parsed = JSON.parse(ev.newValue) as { msg: T };
      for (const fn of listeners) {
        try {
          fn(parsed.msg);
        } catch {
          /* swallow — see above */
        }
      }
    } catch {
      /* malformed payload — drop */
    }
  };
  if (typeof window !== 'undefined') {
    window.addEventListener('storage', onStorage);
  }
  return {
    post: (msg) => {
      try {
        const payload = JSON.stringify({ msg, t: Date.now() });
        localStorage.setItem(storageKey, payload);
        // Remove on the next tick so the key doesn't linger in localStorage
        // (would survive reloads and look like a fresh signal).
        setTimeout(() => {
          try {
            localStorage.removeItem(storageKey);
          } catch {
            /* quota / private mode — ignore */
          }
        }, 0);
      } catch {
        /* private mode quota / SSR — ignore */
      }
    },
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    close: () => {
      listeners.clear();
      if (typeof window !== 'undefined') {
        window.removeEventListener('storage', onStorage);
      }
    },
  };
}
