import { useQuery } from '@tanstack/react-query';
import { settingsApi } from '@/api/endpoints';

interface TaxClass {
  id: number;
  name: string;
  rate: number;
  is_default?: boolean;
}

/**
 * Fetches the configured tax classes and returns the rate (0–1) for the
 * default class.  Falls back to 0 only when the query fails OR there are no
 * tax classes defined — never uses a hard-coded constant.
 */
export function useDefaultTaxRate(): number {
  const { data } = useQuery({
    queryKey: ['tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
    staleTime: 5 * 60 * 1000, // 5 min — tax rates rarely change mid-session
    retry: 1,
  });

  // SCAN-1089: `data.data.data.tax_classes` was a dead triple-envelope fallback
  // — no current route returns that shape. `settingsApi.getTaxClasses()`
  // resolves to `AxiosResponse<{success:true; data: TaxClass[]}>`, so the only
  // correct unwrap is `data.data.data`. Drop the fallback and narrow via a
  // runtime `Array.isArray` so malformed responses don't silently widen.
  const payload = data?.data?.data;
  const taxClasses: TaxClass[] = Array.isArray(payload) ? payload : [];

  const defaultClass =
    taxClasses.find((tc) => tc.is_default) ?? taxClasses[0] ?? null;

  return defaultClass ? defaultClass.rate / 100 : 0;
}
