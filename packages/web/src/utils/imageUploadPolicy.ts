export const IMAGE_UPLOAD_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] as const;
export type ImageUploadMimeType = (typeof IMAGE_UPLOAD_MIME_TYPES)[number];

// WEB-UIUX-1090: surface HEIC/HEIF in the picker so iPhone Safari users see
// their camera-roll photos un-greyed; maybeConvertHeicToJpeg transcodes them
// to JPEG before validateImageFile runs, so the validated set stays
// IMAGE_UPLOAD_MIME_TYPES (HEIC is never persisted to the server).
export const IMAGE_UPLOAD_ACCEPT = [...IMAGE_UPLOAD_MIME_TYPES, 'image/heic', 'image/heif'].join(',');
export const IMAGE_UPLOAD_FORMAT_LABEL = 'JPEG, PNG, WebP, or GIF';
export const IMAGE_UPLOAD_FORMAT_ERROR =
  `Use ${IMAGE_UPLOAD_FORMAT_LABEL}. HEIC/HEIF, TIFF, and DNG/RAW are not supported yet; convert to JPEG before uploading.`;

// Receipt uploads additionally allow PDF documents.
export const RECEIPT_UPLOAD_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'] as const;
export type ReceiptUploadMimeType = (typeof RECEIPT_UPLOAD_MIME_TYPES)[number];
export const RECEIPT_UPLOAD_ACCEPT = RECEIPT_UPLOAD_MIME_TYPES.join(',');
export const RECEIPT_UPLOAD_FORMAT_LABEL = 'JPEG, PNG, WebP, or PDF';
export const RECEIPT_UPLOAD_FORMAT_ERROR =
  `Use ${RECEIPT_UPLOAD_FORMAT_LABEL}. Other formats are not supported.`;
export const RECEIPT_UPLOAD_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

export function isSupportedReceiptMime(mime: string | undefined | null): mime is ReceiptUploadMimeType {
  return RECEIPT_UPLOAD_MIME_TYPES.includes((mime || '').trim().toLowerCase() as ReceiptUploadMimeType);
}

export async function validateReceiptFile(file: File, label?: string): Promise<string | null> {
  const tag = label || `"${file.name}"` || 'Receipt';
  const declaredMime = file.type.trim().toLowerCase();
  if (!isSupportedReceiptMime(declaredMime)) {
    return `${tag}: ${RECEIPT_UPLOAD_FORMAT_ERROR}`;
  }
  if (file.size <= 0) return `${tag}: file is empty`;
  if (file.size > RECEIPT_UPLOAD_MAX_BYTES) {
    return `${tag}: file exceeds the 10 MB size limit`;
  }
  // Magic-byte sniff to guard against mismatched extensions/MIME declarations.
  const head = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  if (declaredMime === 'application/pdf') {
    // PDF magic: %PDF (25 50 44 46)
    if (!(head[0] === 0x25 && head[1] === 0x50 && head[2] === 0x44 && head[3] === 0x46)) {
      return `${tag}: file does not appear to be a valid PDF`;
    }
  } else {
    // Reuse existing image sniff logic for image/* types.
    const sniffed = await sniffImageMime(file);
    if (!sniffed || sniffed !== declaredMime) {
      return `${tag}: file contents do not match the declared image type`;
    }
  }
  return null;
}

export const GENERAL_IMAGE_UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
export const SMALL_IMAGE_UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
export const INLINE_LOGO_MAX_BYTES = 500_000;

const MIME_LABELS: Record<ImageUploadMimeType, string> = {
  'image/jpeg': 'JPEG',
  'image/png': 'PNG',
  'image/webp': 'WebP',
  'image/gif': 'GIF',
};

export function formatUploadSize(bytes: number): string {
  if (bytes % (1024 * 1024) === 0) return `${bytes / (1024 * 1024)} MB`;
  if (bytes % 1024 === 0) return `${bytes / 1024} KB`;
  return `${bytes} bytes`;
}

export function isSupportedImageMime(mime: string | undefined | null): mime is ImageUploadMimeType {
  return IMAGE_UPLOAD_MIME_TYPES.includes((mime || '').trim().toLowerCase() as ImageUploadMimeType);
}

export async function sniffImageMime(file: File): Promise<ImageUploadMimeType | null> {
  const head = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  if (head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47) return 'image/png';
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'image/jpeg';
  if (head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return 'image/gif';
  if (
    head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50
  ) return 'image/webp';
  return null;
}

export interface ValidateImageFileOptions {
  maxBytes: number;
  label?: string;
  sniff?: boolean;
}

// WEB-UIUX-1090: best-effort client-side HEIC/HEIF → JPEG via the browser's
// native image decoder + canvas re-encode. Returns the original file unchanged
// when the platform cannot decode HEIC (e.g. Linux Chrome with no codec) or
// when the file is not HEIC; validateImageFile then surfaces the existing
// "convert to JPEG before uploading" error. iOS Safari + macOS browsers (where
// HEIC originates) can decode natively, so the common case converts inline.
export async function maybeConvertHeicToJpeg(file: File): Promise<File> {
  const mime = file.type.trim().toLowerCase();
  if (mime !== 'image/heic' && mime !== 'image/heif') return file;
  const objectUrl = URL.createObjectURL(file);
  try {
    const img = new Image();
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error('heic decode failed'));
      img.src = objectUrl;
    });
    if (!img.naturalWidth || !img.naturalHeight) return file;
    const canvas = document.createElement('canvas');
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return file;
    ctx.drawImage(img, 0, 0);
    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.92);
    });
    if (!blob || blob.size <= 0) return file;
    const baseName = (file.name || 'photo').replace(/\.(heic|heif)$/i, '');
    return new File([blob], `${baseName || 'photo'}.jpg`, {
      type: 'image/jpeg',
      lastModified: file.lastModified,
    });
  } catch {
    return file;
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

export async function validateImageFile(file: File, options: ValidateImageFileOptions): Promise<string | null> {
  const label = options.label || file.name || 'Image';
  const declaredMime = file.type.trim().toLowerCase();
  if (!isSupportedImageMime(declaredMime)) return `${label}: ${IMAGE_UPLOAD_FORMAT_ERROR}`;
  if (file.size <= 0) return `${label}: image is empty`;
  if (file.size > options.maxBytes) {
    return `${label}: image exceeds the ${formatUploadSize(options.maxBytes)} size limit`;
  }
  if (options.sniff) {
    const sniffed = await sniffImageMime(file);
    if (!sniffed || sniffed !== declaredMime) {
      const declared = MIME_LABELS[declaredMime];
      return `${label}: file contents do not match the ${declared} image type.`;
    }
  }
  return null;
}
