/**
 * PhotoGallery — shows before/after photos from ticket_photos_visibility.
 *
 * Customers can remove accidentally-uploaded "after" photos from their
 * view if still inside the `portal_after_photo_delete_hours` window.
 * "Before" photos are never deletable by the customer.
 *
 * All photo deletes are soft: the backend flips customer_visible to 0
 * rather than dropping the row, so the tech audit trail is preserved.
 */
import React, { useCallback, useEffect, useState } from 'react';
import {
  getPortalPhotos,
  hidePortalPhoto,
  type PortalPhoto,
} from './enrichApi';
import { usePortalI18n } from '../i18n';
import { confirm } from '@/stores/confirmStore';

interface PhotoGalleryProps {
  ticketId: number;
}

export function PhotoGallery({ ticketId }: PhotoGalleryProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [photos, setPhotos] = useState<PortalPhoto[] | null>(null);
  const [deleteWindowHours, setDeleteWindowHours] = useState<number>(0);
  const [hidingPath, setHidingPath] = useState<string | null>(null);

  const load = useCallback(async (): Promise<void> => {
    const data = await getPortalPhotos(ticketId);
    setPhotos(data.photos);
    setDeleteWindowHours(data.delete_window_hours);
  }, [ticketId]);

  useEffect(() => {
    load().catch(() => setPhotos([]));
  }, [load]);

  const handleHide = useCallback(
    async (path: string): Promise<void> => {
      // WEB-FV-001: replaced native window.confirm with confirmStore (async modal)
      const confirmed = await confirm(t('photos.delete_confirm'), { danger: true });
      if (!confirmed) return;
      setHidingPath(path);
      try {
        await hidePortalPhoto(ticketId, path);
        setPhotos((prev) => (prev ? prev.filter((p) => p.path !== path) : prev));
      } catch {
        /* swallow — UI already shows the photo; next load will reconcile */
      } finally {
        setHidingPath(null);
      }
    },
    [ticketId, t],
  );

  if (photos === null || photos.length === 0) return null;

  const beforePhotos = photos.filter((p) => p.is_before);
  const afterPhotos = photos.filter((p) => !p.is_before);

  return (
    <section
      aria-label={t('photos.title')}
      className="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4"
    >
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
        {t('photos.title')}
      </h3>

      {beforePhotos.length > 0 ? (
        <div className="mb-3">
          <div className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            {t('photos.before')}
          </div>
          <PhotoRow photos={beforePhotos} />
        </div>
      ) : null}

      {afterPhotos.length > 0 ? (
        <div>
          <div className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            {t('photos.after')}
          </div>
          <PhotoRow
            photos={afterPhotos}
            onHide={handleHide}
            hidingPath={hidingPath}
            deleteLabel={t('photos.delete')}
          />
          {deleteWindowHours > 0 ? (
            <div className="text-[11px] text-gray-400 dark:text-gray-500 mt-2">
              {t('photos.delete_window', { hours: deleteWindowHours })}
            </div>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

interface PhotoRowProps {
  photos: PortalPhoto[];
  onHide?: (path: string) => void;
  hidingPath?: string | null;
  deleteLabel?: string;
}

function isSafePhotoPath(path: string): boolean {
  return /^https?:\/\//.test(path) || path.startsWith('/uploads/');
}

function PhotoRow({
  photos,
  onHide,
  hidingPath,
  deleteLabel,
}: PhotoRowProps): React.ReactElement {
  return (
    <div className="flex gap-2 overflow-x-auto pb-2" role="list">
      {photos.map((photo) => (
        <div
          key={photo.path}
          role="listitem"
          className="relative flex-shrink-0 w-24 h-24 rounded-md overflow-hidden border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900"
        >
          {isSafePhotoPath(photo.path) ? (
            <img
              src={photo.path}
              alt="Repair photo"
              loading="lazy"
              className="w-full h-full object-cover"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-gray-400 dark:text-gray-600">
              <svg xmlns="http://www.w3.org/2000/svg" className="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-label="Photo unavailable">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
          )}
          {onHide && photo.deletable ? (
            <button
              type="button"
              onClick={() => onHide(photo.path)}
              disabled={hidingPath === photo.path}
              aria-label={deleteLabel || 'Remove'}
              className="absolute top-1 right-1 w-6 h-6 rounded-full bg-red-600 text-white text-xs font-bold flex items-center justify-center hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-400 disabled:opacity-50"
            >
              &times;
            </button>
          ) : null}
        </div>
      ))}
    </div>
  );
}
