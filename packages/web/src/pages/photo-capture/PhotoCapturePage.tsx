import { useState, useRef, useEffect } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { Camera, Upload, CheckCircle2, X, Loader2, ImageIcon, AlertCircle } from 'lucide-react';
import { api } from '@/api/client';
import toast from 'react-hot-toast';
import {
  IMAGE_UPLOAD_ACCEPT,
  validateImageFile,
} from '@/utils/imageUploadPolicy';
import { formatTicketId } from '@/utils/format';

/**
 * WEB-UIUX-510: Re-encode image via canvas to bake EXIF orientation into pixel
 * data and strip all metadata before upload. Modern browsers honour the EXIF
 * orientation tag when drawImage() is called, so the resulting blob is always
 * upright and carries no rotation tag.
 *
 * WEB-UIUX-514: Also resize images whose long side exceeds MAX_DIMENSION to
 * MAX_DIMENSION px, re-encoding at JPEG_QUALITY. Modern phone cameras produce
 * 4-8 MB files easily; the resize brings them well under the server limit
 * before the file is even staged for upload.
 */
const MAX_DIMENSION = 2048;
const JPEG_QUALITY = 0.85;

/**
 * WEB-UIUX-517: Format a Date as a human-readable timestamp suitable for
 * burning into the photo overlay. Example: "2026-05-06  14:32:07"
 */
function formatTimestamp(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  );
}

async function normalizeOrientation(file: File): Promise<Blob> {
  return new Promise((resolve) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(url);
      const { naturalWidth: w, naturalHeight: h } = img;
      const longSide = Math.max(w, h);
      const scale = longSide > MAX_DIMENSION ? MAX_DIMENSION / longSide : 1;
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
      const ctx = canvas.getContext('2d')!;
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

      // WEB-UIUX-517: Burn capture timestamp into the bottom-right corner so
      // repair evidence photos carry a visible chain-of-custody timestamp even
      // after EXIF is stripped by the canvas re-encode above.
      // Font scales with image size so it remains legible on both thumbnails
      // and full-res exports (floor at 14px, cap at 36px).
      const fontSize = Math.min(36, Math.max(14, Math.round(canvas.width * 0.022)));
      const label = formatTimestamp(new Date());
      const padding = Math.round(fontSize * 0.6);
      ctx.font = `bold ${fontSize}px monospace`;
      const textWidth = ctx.measureText(label).width;
      const boxW = textWidth + padding * 2;
      const boxH = fontSize + padding * 1.2;
      const boxX = canvas.width - boxW - padding;
      const boxY = canvas.height - boxH - padding;

      // Semi-transparent dark background for legibility over any image content
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.beginPath();
      ctx.roundRect(boxX, boxY, boxW, boxH, Math.round(fontSize * 0.25));
      ctx.fill();

      // White text
      ctx.fillStyle = '#ffffff';
      ctx.textBaseline = 'middle';
      ctx.fillText(label, boxX + padding, boxY + boxH / 2);

      canvas.toBlob(
        (blob) => resolve(blob ?? file),
        'image/jpeg',
        JPEG_QUALITY,
      );
    };
    img.onerror = () => { URL.revokeObjectURL(url); resolve(file); };
    img.src = url;
  });
}

export function PhotoCapturePage() {
  const { ticketId, deviceId } = useParams<{ ticketId: string; deviceId: string }>();
  const [searchParams] = useSearchParams();

  // WEB-UIUX-268: new QR URLs carry the scoped token in the fragment
  // (`#t=...`) so the browser never sends it to the server as part of the
  // initial navigation or as a Referer while the lazy chunk loads. Query `?t=`
  // remains a backward-compatible fallback for older printed QR codes and is
  // replaced immediately after mount.
  const [token] = useState<string | null>(() => {
    const hashParams =
      typeof window === 'undefined'
        ? new URLSearchParams()
        : new URLSearchParams(window.location.hash.replace(/^#/, ''));
    return hashParams.get('t') || searchParams.get('t') || null;
  });
  useEffect(() => {
    const hasHashToken = window.location.hash.replace(/^#/, '').split('&').some((part) => part.startsWith('t='));
    if (searchParams.has('t') || hasHashToken) {
      // Replace the URL in-place without a new history entry
      const next = new URLSearchParams(searchParams);
      next.delete('t');
      const nextSearch = next.toString();
      const nextUrl = `${window.location.pathname}${nextSearch ? `?${nextSearch}` : ''}`;
      window.history.replaceState(window.history.state, '', nextUrl);
    }
    // Run once on mount only
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [photos, setPhotos] = useState<{ file: File; preview: string }[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploaded, setUploaded] = useState(false);
  const [error, setError] = useState('');
  const [tokenExpired, setTokenExpired] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const photosRef = useRef(photos);
  photosRef.current = photos;

  // Revoke all object URLs on unmount to prevent memory leaks
  useEffect(() => {
    return () => {
      photosRef.current.forEach((p) => URL.revokeObjectURL(p.preview));
    };
  }, []); // mount-only

  const MAX_PHOTOS = 20; // WEB-S4-029: cap at 20 to bound upload + storage cost.

  const handleCapture = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (!files.length) return;

    const remaining = Math.max(0, MAX_PHOTOS - photos.length);
    if (remaining === 0) {
      toast.error(`Maximum ${MAX_PHOTOS} photos per ticket reached`);
      if (fileInputRef.current) fileInputRef.current.value = '';
      return;
    }

    const valid: File[] = [];
    // WEB-UIUX-514: validate against a generous pre-resize ceiling (25 MB).
    // normalizeOrientation() will resize any image > 2048 px long side down to
    // 2048 px at JPEG 0.85 before upload, so the server never sees the raw file.
    const PRE_RESIZE_MAX_BYTES = 25 * 1024 * 1024;
    for (const file of files) {
      const error = await validateImageFile(file, {
        maxBytes: PRE_RESIZE_MAX_BYTES,
        label: `"${file.name}"`,
        sniff: true,
      });
      if (error) {
        toast.error(error);
        continue;
      }
      valid.push(file);
    }
    if (!valid.length) { if (fileInputRef.current) fileInputRef.current.value = ''; return; }

    // Trim to remaining capacity so a multi-select past the cap is bounded.
    const trimmed = valid.slice(0, remaining);
    if (trimmed.length < valid.length) {
      toast.error(`Only ${remaining} of ${valid.length} photos added (max ${MAX_PHOTOS})`);
    }

    const newPhotos = trimmed.map((file) => ({
      file,
      preview: URL.createObjectURL(file),
    }));
    setPhotos((prev) => [...prev, ...newPhotos]);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const removePhoto = (index: number) => {
    setPhotos((prev) => {
      URL.revokeObjectURL(prev[index].preview);
      return prev.filter((_, i) => i !== index);
    });
  };

  const handleUpload = async () => {
    if (!photos.length || !ticketId || !deviceId || !token) return;
    setUploading(true);
    setError('');
    try {
      // WEB-UIUX-510: normalise orientation + strip EXIF before upload.
      const blobs = await Promise.all(photos.map((p) => normalizeOrientation(p.file)));
      const formData = new FormData();
      blobs.forEach((blob, i) => {
        const name = photos[i].file.name.replace(/\.[^.]+$/, '.jpg');
        formData.append('photos', blob, name);
      });
      formData.append('ticket_device_id', deviceId);
      formData.append('type', 'pre');
      await api.post(`/tickets/${ticketId}/photos`, formData, {
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'multipart/form-data' },
      });
      setUploaded(true);
    } catch (e: unknown) {
      const err = e as { response?: { status?: number; data?: { message?: string } } } | undefined;
      const status = err?.response?.status;
      // WEB-S4-028: distinguish expired/invalid link from generic upload failure
      if (status === 401 || status === 403) {
        setTokenExpired(true);
        return;
      }
      const msg = err?.response?.data?.message || 'Upload failed. Please try again.';
      setError(msg);
      // Mobile users often don't see the inline error banner — a toast makes
      // the failure impossible to miss even if the page is scrolled.
      toast.error(msg);
    } finally {
      setUploading(false);
    }
  };

  if (!token) {
    return (
      <div className="min-h-screen bg-surface-900 flex flex-col items-center justify-center p-6 text-center">
        <AlertCircle className="h-16 w-16 text-red-400 mb-4" />
        <h1 className="text-xl font-bold text-surface-50 mb-2">Invalid Link</h1>
        <p className="text-surface-400 text-sm">This photo link is missing authentication. Please scan the QR code again from the check-in screen.</p>
      </div>
    );
  }

  // WEB-S4-028: show a clear "link expired" message instead of a generic error
  if (tokenExpired) {
    return (
      <div className="min-h-screen bg-surface-900 flex flex-col items-center justify-center p-6 text-center">
        <AlertCircle className="h-16 w-16 text-amber-400 mb-4" />
        <h1 className="text-xl font-bold text-surface-50 mb-2">Link Expired</h1>
        <p className="text-surface-400 text-sm">This photo link has expired or is no longer valid. Please ask a staff member to generate a new QR code for your ticket.</p>
      </div>
    );
  }

  if (uploaded) {
    return (
      <div className="min-h-screen bg-surface-900 flex flex-col items-center justify-center p-6 text-center">
        <div className="h-28 w-28 rounded-full bg-green-500/20 flex items-center justify-center mb-6">
          <CheckCircle2 className="h-14 w-14 text-green-400" />
        </div>
        <h1 className="text-2xl font-bold text-surface-50 mb-2">Photos Saved!</h1>
        <p className="text-surface-400 mb-1">
          {photos.length} photo{photos.length !== 1 ? 's' : ''} added to ticket {formatTicketId(ticketId!)}
        </p>
        <p className="text-surface-600 text-sm mt-4">You can close this page now.</p>
        <button
          onClick={() => {
            // WEB-FK-002: revoke blob URLs from the just-uploaded batch BEFORE
            // clearing photos so they don't leak. The unmount cleanup reads
            // photosRef which has already been reset to [] by then.
            photosRef.current.forEach((p) => URL.revokeObjectURL(p.preview));
            setUploaded(false);
            setPhotos([]);
            // WEB-S4-030: clear any lingering upload error so a fresh session
            // doesn't show stale failure banners.
            setError('');
          }}
          className="mt-6 px-6 py-3 bg-primary-600 text-primary-950 rounded-2xl font-semibold text-sm"
        >
          Add More Photos
        </button>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-surface-900 flex flex-col">
      {/* Header */}
      <div className="bg-surface-800 px-4 py-4 flex items-center gap-3 border-b border-surface-700 safe-area-top">
        <div className="h-10 w-10 rounded-xl bg-primary-600/20 flex items-center justify-center">
          <Camera className="h-5 w-5 text-primary-400" />
        </div>
        <div>
          <h1 className="text-surface-50 font-semibold leading-tight">Device Photos</h1>
          <p className="text-surface-400 text-xs">Ticket {formatTicketId(ticketId!)} — Pre-condition</p>
        </div>
      </div>

      {/* Instructions */}
      <div className="px-4 py-3 bg-primary-900/20 border-b border-primary-800/30">
        <p className="text-primary-300 text-sm text-center leading-relaxed">
          📸 Take photos of the device <strong>before repair</strong> — screen, damage, cosmetic condition
        </p>
      </div>

      {/* Photo grid */}
      {photos.length > 0 ? (
        <div className="p-4 grid grid-cols-2 gap-3">
          {photos.map((photo, i) => (
            <div key={i} className="relative aspect-square rounded-2xl overflow-hidden bg-surface-800 shadow-lg">
              <img src={photo.preview} alt={`Photo ${i + 1}`} className="w-full h-full object-cover" />
              <button
                onClick={() => removePhoto(i)}
                className="absolute top-2 right-2 h-8 w-8 rounded-full bg-black/70 flex items-center justify-center active:scale-95"
              >
                <X className="h-4 w-4 text-white" />
              </button>
              <div className="absolute bottom-2 left-2 bg-black/60 rounded-lg px-2 py-0.5">
                <span className="text-white text-xs font-medium">#{i + 1}</span>
              </div>
            </div>
          ))}
          {/* Add more tile — WEB-S4-029: hide when 20-photo cap reached. */}
          {photos.length < MAX_PHOTOS && (
            <label className="aspect-square rounded-2xl border-2 border-dashed border-surface-600 flex flex-col items-center justify-center cursor-pointer active:bg-surface-800 transition-colors">
              <Camera className="h-8 w-8 text-surface-500 mb-1" />
              <span className="text-surface-500 text-xs">Add more</span>
              <input
                type="file"
                accept={IMAGE_UPLOAD_ACCEPT}
                capture="environment"
                multiple
                className="sr-only"
                onChange={handleCapture}
              />
            </label>
          )}
        </div>
      ) : (
        /* Empty state */
        <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
          <div className="h-24 w-24 rounded-full bg-surface-800 flex items-center justify-center mb-5">
            <ImageIcon className="h-12 w-12 text-surface-600" />
          </div>
          <p className="text-surface-300 font-medium mb-1">No photos yet</p>
          <p className="text-surface-600 text-sm">Tap the camera button below to photograph the device</p>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="mx-4 mb-2 px-4 py-3 bg-red-900/30 border border-red-700/50 rounded-2xl text-red-300 text-sm text-center flex items-center gap-2">
          <AlertCircle className="h-4 w-4 flex-shrink-0" />
          {error}
        </div>
      )}

      {/* Bottom actions */}
      <div className="mt-auto p-4 space-y-3 border-t border-surface-700/50 safe-area-bottom">
        {/* Camera button */}
        <label className="flex items-center justify-center gap-3 w-full py-5 bg-primary-600 active:bg-primary-700 text-primary-950 rounded-2xl font-semibold text-lg cursor-pointer transition-colors select-none shadow-lg">
          <Camera className="h-6 w-6" />
          {photos.length > 0 ? 'Take Another Photo' : 'Take Photo'}
          <input
            ref={fileInputRef}
            type="file"
            accept={IMAGE_UPLOAD_ACCEPT}
            capture="environment"
            multiple
            className="sr-only"
            onChange={handleCapture}
          />
        </label>

        {/* Upload */}
        {photos.length > 0 && (
          <button
            onClick={handleUpload}
            disabled={uploading}
            className="flex items-center justify-center gap-3 w-full py-5 bg-green-600 active:bg-green-700 text-white rounded-2xl font-semibold text-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none shadow-lg"
          >
            {uploading ? (
              <><Loader2 className="h-6 w-6 animate-spin" /> Uploading...</>
            ) : (
              <><Upload className="h-6 w-6" /> Save {photos.length} Photo{photos.length !== 1 ? 's' : ''}</>
            )}
          </button>
        )}

        <p className="text-surface-600 text-xs text-center">
          {photos.length}/20 photos · Saved directly to the repair ticket
        </p>
      </div>
    </div>
  );
}
