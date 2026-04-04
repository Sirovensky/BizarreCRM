import { useQuery } from '@tanstack/react-query';
import { settingsApi } from '@/api/endpoints';

export function useSettings() {
  const { data, isLoading } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 5 * 60 * 1000,
  });

  const getSetting = (key: string, defaultValue = ''): string => {
    return data?.[key] ?? defaultValue;
  };

  return { settings: data ?? {}, isLoading, getSetting };
}
