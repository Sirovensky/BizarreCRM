import { describe, expect, it } from 'vitest';
import {
  GENERAL_IMAGE_UPLOAD_MAX_BYTES,
  IMAGE_UPLOAD_FORMAT_ERROR,
  imageExtensionForMime,
  isSupportedImageMime,
} from './imageUploadPolicy.js';

describe('imageUploadPolicy', () => {
  it('allows only browser-renderable CRM image formats', () => {
    expect(isSupportedImageMime('image/jpeg')).toBe(true);
    expect(isSupportedImageMime('image/png')).toBe(true);
    expect(isSupportedImageMime('image/webp')).toBe(true);
    expect(isSupportedImageMime('image/gif')).toBe(true);

    expect(isSupportedImageMime('image/heic')).toBe(false);
    expect(isSupportedImageMime('image/heif')).toBe(false);
    expect(isSupportedImageMime('image/tiff')).toBe(false);
    expect(isSupportedImageMime('image/x-adobe-dng')).toBe(false);
    expect(IMAGE_UPLOAD_FORMAT_ERROR).toContain('convert to JPEG');
  });

  it('derives storage extensions from MIME, not user filenames', () => {
    expect(imageExtensionForMime('image/jpeg')).toBe('.jpg');
    expect(imageExtensionForMime('image/png')).toBe('.png');
    expect(imageExtensionForMime('image/webp')).toBe('.webp');
    expect(imageExtensionForMime('image/gif')).toBe('.gif');
    expect(imageExtensionForMime('image/heic')).toBeNull();
  });

  it('keeps the general photo cap at 10 MB', () => {
    expect(GENERAL_IMAGE_UPLOAD_MAX_BYTES).toBe(10 * 1024 * 1024);
  });
});
