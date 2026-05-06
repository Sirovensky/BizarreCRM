export const IMAGE_UPLOAD_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] as const;
export type ImageUploadMimeType = (typeof IMAGE_UPLOAD_MIME_TYPES)[number];

export const IMAGE_UPLOAD_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.gif']);

export const IMAGE_UPLOAD_FORMAT_LABEL = 'JPEG, PNG, WebP, or GIF';
export const IMAGE_UPLOAD_UNSUPPORTED_ADVANCED_FORMATS = 'HEIC/HEIF, TIFF, and DNG/RAW';
export const IMAGE_UPLOAD_FORMAT_ERROR =
  `Only ${IMAGE_UPLOAD_FORMAT_LABEL} images are supported. ` +
  `${IMAGE_UPLOAD_UNSUPPORTED_ADVANCED_FORMATS} uploads need server-side conversion first; convert to JPEG before uploading.`;

export const GENERAL_IMAGE_UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
export const SMALL_IMAGE_UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
export const INLINE_LOGO_MAX_BYTES = 500_000;

const MIME_TO_EXTENSION: Record<ImageUploadMimeType, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
};

export function isSupportedImageMime(mime: string | undefined | null): mime is ImageUploadMimeType {
  return IMAGE_UPLOAD_MIME_TYPES.includes((mime || '').trim().toLowerCase() as ImageUploadMimeType);
}

export function imageExtensionForMime(mime: string | undefined | null): string | null {
  const normalized = (mime || '').trim().toLowerCase();
  if (!isSupportedImageMime(normalized)) return null;
  return MIME_TO_EXTENSION[normalized];
}

export function sanitizedImageExtension(originalName: string): string | null {
  const ext = originalName ? originalName.toLowerCase().match(/\.[a-z0-9]+$/)?.[0] : null;
  return ext && IMAGE_UPLOAD_EXTENSIONS.has(ext) ? ext : null;
}

export function formatUploadSize(bytes: number): string {
  if (bytes % (1024 * 1024) === 0) return `${bytes / (1024 * 1024)} MB`;
  if (bytes % 1024 === 0) return `${bytes / 1024} KB`;
  return `${bytes} bytes`;
}

export function imageUploadSizeError(maxBytes: number): string {
  return `Image exceeds the ${formatUploadSize(maxBytes)} size limit`;
}
