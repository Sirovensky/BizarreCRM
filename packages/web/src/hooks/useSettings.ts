import { useQuery } from '@tanstack/react-query';
import { createContext, createElement, useCallback, useContext, useMemo, type ReactNode } from 'react';
import { settingsApi } from '@/api/endpoints';

type SettingsMap = Record<string, string>;
const EMPTY_SETTINGS: SettingsMap = {};
const SETTINGS_QUERY_KEY = ['settings', 'config'] as const;
const SETTINGS_STALE_TIME_MS = 30 * 1000; // 30 s — edits in other tabs become visible quickly

// Runtime narrowing for the server's settings payload. The endpoint is
// documented to return `Record<string, string>`, but we never trust external
// data without a shape check — a missing object or nested values would
// otherwise silently become `settings["foo"] = undefined` at call sites.
function coerceSettings(raw: unknown): SettingsMap {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out: SettingsMap = {};
  for (const [key, val] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof key !== 'string') continue;
    if (typeof val === 'string') {
      out[key] = val;
    } else if (typeof val === 'number' || typeof val === 'boolean') {
      out[key] = String(val);
    }
    // Skip objects/arrays/null — caller sees defaultValue fallback.
  }
  return out;
}

interface UseSettingsReturn {
  settings: SettingsMap;
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  getSetting: (key: string, defaultValue?: string) => string;
}

const SettingsContext = createContext<UseSettingsReturn | null>(null);

function useSettingsQueryValue(): UseSettingsReturn {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: SETTINGS_QUERY_KEY,
    queryFn: async (): Promise<SettingsMap> => {
      const res = await settingsApi.getConfig();
      return coerceSettings(res.data?.data);
    },
    staleTime: SETTINGS_STALE_TIME_MS,
    refetchOnWindowFocus: true,
  });
  const settings = data ?? EMPTY_SETTINGS;

  // SCAN-1087: previously `getSetting` was recreated on every render, so
  // downstream consumers that pass it as a useEffect/useMemo dependency
  // re-ran on every unrelated render. Memoize with `useCallback` keyed on
  // `data` so the identity only changes when settings actually change.
  const getSetting = useCallback(
    (key: string, defaultValue = ''): string => settings[key] ?? defaultValue,
    [settings],
  );

  return useMemo(
    () => ({ settings, isLoading, isError, error, getSetting }),
    [settings, isLoading, isError, error, getSetting],
  );
}

export function SettingsProvider({ children }: { children: ReactNode }) {
  const value = useSettingsQueryValue();
  return createElement(SettingsContext.Provider, { value }, children);
}

export function useSettings(): UseSettingsReturn {
  const context = useContext(SettingsContext);
  if (!context) {
    throw new Error('useSettings must be used within a SettingsProvider');
  }
  return context;
}
