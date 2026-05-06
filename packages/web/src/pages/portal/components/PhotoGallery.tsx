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
import React, { useCallback, useEffect, useRef, useState } from 'react';
import toast from 'react-hot-toast';
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

/** Lightbox: full-size overlay with prev/next navigation and Esc/click-outside close. */
interface LightboxState {
  photos: PortalPhoto[];
  index: number;
}

function Lightbox({
  state,
  onClose,
  onPrev,
  onNext,
}: {
  state: LightboxState;
  onClose: () => void;
  onPrev: () => void;
  onNext: () => void;
}): React.ReactElement {
  const backdropRef = useRef<HTMLDivElement>(null);
  const photo = state.photos[state.index];
  const hasPrev = state.index > 0;
  const hasNext = state.index < state.photos.length - 1;

  // Esc key closes the lightbox
  useEffect(() => {
    const handler = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowLeft' && hasPrev) onPrev();
      if (e.key === 'ArrowRight' && hasNext) onNext();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose, onPrev, onNext, hasPrev, hasNext]);

  // Prevent body scroll while open
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = prev; };
  }, []);

  const handleBackdropClick = (e: React.MouseEvent<HTMLDivElement>): void => {
    if (e.target === backdropRef.current) onClose();
  };

  return (
    <div
      ref={backdropRef}
      role="dialog"
      aria-modal="true"
      aria-label="Photo lightbox"
      onClick={handleBackdropClick}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm"
    >
      {/* Close button */}
      <button
        type="button"
        onClick={onClose}
        aria-label="Close lightbox"
        className="absolute top-4 right-4 w-10 h-10 rounded-full bg-white/10 text-white flex items-center justify-center hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>

      {/* Prev chevron */}
      {hasPrev && (
        <button
          type="button"
          onClick={onPrev}
          aria-label="Previous photo"
          className="absolute left-4 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/10 text-white flex items-center justify-center hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
      )}

      {/* Image */}
      <div className="max-w-[90vw] max-h-[90vh] flex flex-col items-center gap-3">
        <img
          src={photo.path}
          alt="Repair photo full size"
          className="max-w-full max-h-[80vh] object-contain rounded-lg shadow-2xl"
        />
        {/* Counter */}
        <span className="text-white/60 text-sm select-none">
          {state.index + 1} / {state.photos.length}
        </span>
      </div>

      {/* Next chevron */}
      {hasNext && (
        <button
          type="button"
          onClick={onNext}
          aria-label="Next photo"
          className="absolute right-4 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-white/10 text-white flex items-center justify-center hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
          </svg>
        </button>
      )}
    </div>
  );
}

export function PhotoGallery({ ticketId }: PhotoGalleryProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [photos, setPhotos] = useState<PortalPhoto[] | null>(null);
  const [deleteWindowHours, setDeleteWindowHours] = useState<number>(0);
  const [hidingPath, setHidingPath] = useState<string | null>(null);
  const [lightbox, setLightbox] = useState<LightboxState | null>(null);

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
      } catch (err) {
        // WEB-FC-013 (Fixer-B10 2026-04-25): surface the failure so the
        // customer doesn't think the photo was deleted when it wasn't.
        // Reload from server so the gallery reflects truth, and toast the
        // operator so they know to retry.
        toast.error(t('photos.delete_failed') || 'Could not remove photo');
        load().catch(() => { /* best-effort reconciliation */ });
        if (import.meta.env.DEV) console.warn('[PhotoGallery] hide failed', err);
      } finally {
        setHidingPath(null);
      }
    },
    [ticketId, t, load],
  );

  const handleOpenLightbox = useCallback((allPhotos: PortalPhoto[], index: number): void => {
    setLightbox({ photos: allPhotos, index });
  }, []);

  const handleCloseLightbox = useCallback((): void => setLightbox(null), []);

  const handleLightboxPrev = useCallback((): void => {
    setLightbox((lb) => lb && lb.index > 0 ? { ...lb, index: lb.index - 1 } : lb);
  }, []);

  const handleLightboxNext = useCallback((): void => {
    setLightbox((lb) => lb && lb.index < lb.photos.length - 1 ? { ...lb, index: lb.index + 1 } : lb);
  }, []);

  if (photos === null || photos.length === 0) return null;

  const beforePhotos = photos.filter((p) => p.is_before);
  const afterPhotos = photos.filter((p) => !p.is_before);

  return (
    <>
      <section
        aria-label={t('photos.title')}
        className="rounded-lg bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 p-4"
      >
        <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">
          {t('photos.title')}
        </h3>

        {beforePhotos.length > 0 ? (
          <div className="mb-3">
            <div className="text-xs font-medium text-surface-500 dark:text-surface-400 uppercase tracking-wide mb-2">
              {t('photos.before')}
            </div>
            <PhotoRow photos={beforePhotos} onOpen={(idx) => handleOpenLightbox(beforePhotos, idx)} />
          </div>
        ) : null}

        {afterPhotos.length > 0 ? (
          <div>
            <div className="text-xs font-medium text-surface-500 dark:text-surface-400 uppercase tracking-wide mb-2">
              {t('photos.after')}
            </div>
            <PhotoRow
              photos={afterPhotos}
              onOpen={(idx) => handleOpenLightbox(afterPhotos, idx)}
              onHide={handleHide}
              hidingPath={hidingPath}
              deleteLabel={t('photos.delete')}
            />
            {deleteWindowHours > 0 ? (
              <div className="text-[11px] text-surface-400 dark:text-surface-500 mt-2">
                {t('photos.delete_window', { hours: deleteWindowHours })}
              </div>
            ) : null}
          </div>
        ) : null}
      </section>

      {lightbox !== null ? (
        <Lightbox
          state={lightbox}
          onClose={handleCloseLightbox}
          onPrev={handleLightboxPrev}
          onNext={handleLightboxNext}
        />
      ) : null}
    </>
  );
}

interface PhotoRowProps {
  photos: PortalPhoto[];
  /** Called with the index of the photo that was clicked, to open the lightbox. */
  onOpen: (index: number) => void;
  onHide?: (path: string) => void;
  hidingPath?: string | null;
  deleteLabel?: string;
}

function isSafePhotoPath(path: string): boolean {
  return /^https?:\/\//.test(path) || path.startsWith('/uploads/');
}

function PhotoRow({
  photos,
  onOpen,
  onHide,
  hidingPath,
  deleteLabel,
}: PhotoRowProps): React.ReactElement {
  return (
    <div className="flex gap-2 overflow-x-auto pb-2" role="list">
      {photos.map((photo, idx) => (
        <div
          key={photo.path}
          role="listitem"
          className="relative flex-shrink-0 w-24 h-24 rounded-md overflow-hidden border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900"
        >
          {isSafePhotoPath(photo.path) ? (
            <button
              type="button"
              onClick={() => onOpen(idx)}
              aria-label="View full-size photo"
              className="w-full h-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-400 focus-visible:ring-inset"
            >
              <img
                src={photo.path}
                alt="Repair photo"
                loading="lazy"
                className="w-full h-full object-cover"
              />
            </button>
          ) : (
            <div className="w-full h-full flex items-center justify-center text-surface-400 dark:text-surface-600">
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
              className="absolute top-1 right-1 w-6 h-6 rounded-full bg-red-600 text-white text-xs font-bold flex items-center justify-center hover:bg-red-700 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              &times;
            </button>
          ) : null}
        </div>
      ))}
    </div>
  );
}
