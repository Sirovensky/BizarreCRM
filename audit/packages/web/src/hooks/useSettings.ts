import { useQuery } from '@tanstack/react-query';
import { useCallback } from 'react';
import { settingsApi } from '@/api/endpoints';

type SettingsMap = Record<string, string>;

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

export function useSettings(): UseSettingsReturn {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async (): Promise<SettingsMap> => {
      const res = await settingsApi.getConfig();
      return coerceSettings(res.data?.data);
    },
    staleTime: 5 * 60 * 1000,
  });

  // SCAN-1087: previously `getSetting` was recreated on every render, so
  // downstream consumers that pass it as a useEffect/useMemo dependency
  // re-ran on every unrelated render. Memoize with `useCallback` keyed on
  // `data` so the identity only changes when settings actually change.
  const getSetting = useCallback(
    (key: string, defaultValue = ''): string => data?.[key] ?? defaultValue,
    [data],
  );

  return { settings: data ?? {}, isLoading, isError, error, getSetting };
}
