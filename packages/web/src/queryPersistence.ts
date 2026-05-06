import type { Query, QueryClient } from '@tanstack/react-query';
import { defaultShouldDehydrateQuery } from '@tanstack/react-query';
import {
  persistQueryClient,
  removeOldestQuery,
} from '@tanstack/react-query-persist-client';
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister';
import type { User } from '@bizarre-crm/shared';
import { createStore, del, delMany, get, keys, set } from 'idb-keyval';

const DB_NAME = 'bizarre-crm-web';
const STORE_NAME = 'react-query-cache';
const CACHE_KEY_PREFIX = 'bizarrecrm:rq:v1';
const CACHE_BUSTER = 'safe-read-cache-v1';
const MAX_CACHE_AGE_MS = 1000 * 60 * 60 * 6;

const SAFE_READ_QUERY_ROOTS = new Set([
  'auth-setup-status',
  'blockchyp',
  'device-templates',
  'onboarding',
  'onboarding-state',
  'qc-checklist',
  'repair-pricing',
  'settings',
  'setup-status',
  'sms-templates',
  'tax-classes',
  'ticket-statuses',
]);

const idbStore = createStore(DB_NAME, STORE_NAME);

function canUseIndexedDb(): boolean {
  return typeof window !== 'undefined' && 'indexedDB' in window;
}

function originScope(): string {
  const origin = typeof window !== 'undefined' ? window.location.origin : 'server';
  return encodeURIComponent(origin);
}

function cacheKeyForUser(user: User): string {
  return `${CACHE_KEY_PREFIX}:${originScope()}:u:${user.id}`;
}

function cacheKeyPrefixForOrigin(): string {
  return `${CACHE_KEY_PREFIX}:${originScope()}:`;
}

function isSafeReadQuery(query: Query): boolean {
  const [root] = query.queryKey;
  if (typeof root !== 'string' || !SAFE_READ_QUERY_ROOTS.has(root)) return false;
  if (query.state.status !== 'success' || query.state.data === undefined) return false;
  if (Date.now() - query.state.dataUpdatedAt > MAX_CACHE_AGE_MS) return false;
  return true;
}

async function removePersistedCachesForOrigin(): Promise<void> {
  if (!canUseIndexedDb()) return;
  const prefix = cacheKeyPrefixForOrigin();
  const allKeys = await keys<IDBValidKey>(idbStore);
  const matching = allKeys.filter((key): key is string => (
    typeof key === 'string' && key.startsWith(prefix)
  ));
  if (matching.length > 0) {
    await delMany(matching, idbStore);
  }
}

export interface ReactQueryPersistenceController {
  clearPersistedCache: () => void;
  destroy: () => void;
}

export function setupReactQueryIndexedDbPersistence(
  queryClient: QueryClient,
  getUser: () => User | null,
  authReadyEventName: string,
): ReactQueryPersistenceController {
  if (!canUseIndexedDb()) {
    return {
      clearPersistedCache: () => {},
      destroy: () => {},
    };
  }

  let activeKey: string | null = null;
  let unsubscribePersistence: (() => void) | null = null;
  let pendingClear: Promise<void> = Promise.resolve();
  let startNonce = 0;

  const stopPersistence = () => {
    startNonce += 1;
    unsubscribePersistence?.();
    unsubscribePersistence = null;
    activeKey = null;
  };

  const startForCurrentUser = () => {
    const user = getUser();
    if (!user) {
      stopPersistence();
      return;
    }

    const key = cacheKeyForUser(user);
    if (activeKey === key) return;

    stopPersistence();
    activeKey = key;
    const nonce = startNonce;

    pendingClear.then(() => {
      if (startNonce !== nonce || activeKey !== key) return;

      const persister = createAsyncStoragePersister({
        key,
        throttleTime: 2000,
        retry: removeOldestQuery,
        storage: {
          getItem: (storageKey) => get<string>(storageKey, idbStore),
          setItem: (storageKey, value) => set(storageKey, value, idbStore),
          removeItem: (storageKey) => del(storageKey, idbStore),
        },
      });

      const [unsubscribe, restorePromise] = persistQueryClient({
        queryClient,
        persister,
        maxAge: MAX_CACHE_AGE_MS,
        buster: CACHE_BUSTER,
        dehydrateOptions: {
          shouldDehydrateMutation: () => false,
          shouldDehydrateQuery: (query) => (
            defaultShouldDehydrateQuery(query) && isSafeReadQuery(query)
          ),
        },
      });

      unsubscribePersistence = unsubscribe;
      restorePromise.catch(() => {
        if (activeKey === key) {
          void persister.removeClient();
        }
      });
    });
  };

  window.addEventListener(authReadyEventName, startForCurrentUser);
  startForCurrentUser();

  return {
    clearPersistedCache: () => {
      stopPersistence();
      pendingClear = removePersistedCachesForOrigin().catch(() => {});
    },
    destroy: () => {
      window.removeEventListener(authReadyEventName, startForCurrentUser);
      stopPersistence();
    },
  };
}
