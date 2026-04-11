import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Camera, ImageOff } from 'lucide-react';
import { crmApi } from '@/api/endpoints';

/**
 * PhotoMementosWallet — horizontally scrolling gallery of this customer's
 * repair photos from the last 12 months. Clicking a photo jumps to the
 * ticket detail page.
 *
 * Pulls from GET /crm/customers/:id/photo-mementos. The server already
 * joins ticket_devices and tickets so each row includes device name +
 * order_id for a useful caption.
 */

interface PhotoMementosWalletProps {
  customerId: number;
}

interface MementoRow {
  photo_id: number;
  file_path: string;
  caption: string | null;
  created_at: string;
  ticket_id: number;
  order_id: string;
  device_name: string | null;
}

interface MementoResponse {
  success: boolean;
  data: MementoRow[];
}

export function PhotoMementosWallet({ customerId }: PhotoMementosWalletProps) {
  const { data, isLoading, error } = useQuery<MementoResponse>({
    queryKey: ['crm', 'photo-mementos', customerId],
    queryFn: async () => {
      const res = await crmApi.photoMementos(customerId);
      return res.data as MementoResponse;
    },
    enabled: !!customerId,
    staleTime: 60_000,
  });

  const photos = data?.data ?? [];

  if (isLoading) {
    return (
      <section className="mt-6 rounded-2xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
        <header className="flex items-center gap-2 mb-3 text-surface-700 dark:text-surface-200">
          <Camera className="h-4 w-4" />
          <h3 className="text-sm font-semibold">Photo Mementos</h3>
        </header>
        <div className="flex gap-3 overflow-hidden">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="w-32 h-32 rounded-lg bg-surface-100 dark:bg-surface-800 animate-pulse" />
          ))}
        </div>
      </section>
    );
  }

  if (error) {
    return (
      <section className="mt-6 rounded-2xl border border-red-200 dark:border-red-800 bg-red-50/50 dark:bg-red-900/20 p-4">
        <div className="text-sm text-red-600 dark:text-red-400">
          Failed to load repair photos.
        </div>
      </section>
    );
  }

  if (photos.length === 0) {
    return (
      <section className="mt-6 rounded-2xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
        <header className="flex items-center gap-2 mb-2 text-surface-700 dark:text-surface-200">
          <Camera className="h-4 w-4" />
          <h3 className="text-sm font-semibold">Photo Mementos</h3>
        </header>
        <div className="flex items-center gap-2 py-4 text-sm text-surface-500 dark:text-surface-400">
          <ImageOff className="h-4 w-4" />
          No repair photos in the last 12 months.
        </div>
      </section>
    );
  }

  return (
    <section className="mt-6 rounded-2xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
      <header className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2 text-surface-700 dark:text-surface-200">
          <Camera className="h-4 w-4" />
          <h3 className="text-sm font-semibold">Photo Mementos</h3>
          <span className="text-xs text-surface-500">{photos.length} photos</span>
        </div>
      </header>
      <div className="flex gap-3 overflow-x-auto pb-2">
        {photos.map((photo) => (
          <Link
            key={photo.photo_id}
            to={`/tickets/${photo.ticket_id}`}
            className="group flex-shrink-0 w-32"
            title={photo.caption ?? `${photo.device_name ?? 'Device'} — ${photo.order_id}`}
          >
            <div className="w-32 h-32 rounded-lg overflow-hidden bg-surface-100 dark:bg-surface-800 border border-surface-200 dark:border-surface-700 group-hover:border-primary-400 transition-colors">
              <img
                src={photo.file_path.startsWith('/') ? photo.file_path : `/uploads/${photo.file_path}`}
                alt={photo.caption ?? 'Repair photo'}
                className="w-full h-full object-cover"
                loading="lazy"
                onError={(e) => {
                  (e.currentTarget as HTMLImageElement).style.display = 'none';
                }}
              />
            </div>
            <div className="mt-1 truncate text-[11px] text-surface-600 dark:text-surface-400">
              {photo.device_name ?? photo.order_id}
            </div>
            <div className="truncate text-[10px] text-surface-400 dark:text-surface-500">
              {new Date(photo.created_at).toLocaleDateString()}
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}
