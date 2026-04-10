import { useState } from 'react';
import { Image as ImageIcon, Upload } from 'lucide-react';
import type { SubStepProps } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';
import { api } from '@/api/client';

/**
 * Sub-step — Logo & Branding.
 *
 * Uploads a logo file via POST /settings/logo (existing endpoint used by the
 * Settings page) and stores the returned URL in store_logo. Also offers a
 * primary color picker that writes to theme_primary_color.
 *
 * Logo upload is optional — user can skip and add later from Settings.
 */
export function StepLogo({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const [logoUrl, setLogoUrl] = useState(pending.store_logo || '');
  const [color, setColor] = useState(pending.theme_primary_color || '#0E7490');
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      setError('Logo must be under 2 MB.');
      return;
    }
    setUploading(true);
    setError('');
    try {
      const formData = new FormData();
      formData.append('logo', file);
      // Matches the existing settingsApi.uploadLogo pattern (see endpoints.ts:297).
      // The server route at POST /settings/logo returns { success, data: { store_logo } }
      // where store_logo is a "/uploads/{slug}/{filename}" path relative to the tenant's
      // subdomain. The server already writes it into store_config.store_logo, but we
      // also stash it in pending so the review step can show the uploaded logo and the
      // wizard's final flush is idempotent (writing the same value is a no-op).
      const res = await api.post('/settings/logo', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      const body = res?.data as { success?: boolean; data?: { store_logo?: string } } | undefined;
      const url = body?.data?.store_logo;
      if (!url) throw new Error('Upload succeeded but server did not return a URL.');
      setLogoUrl(url);
      onUpdate({ store_logo: url });
    } catch (err: any) {
      setError(err?.response?.data?.message || err?.message || 'Upload failed.');
    } finally {
      setUploading(false);
    }
  };

  const handleColorChange = (c: string) => {
    setColor(c);
    onUpdate({ theme_primary_color: c });
  };

  return (
    <div className="mx-auto max-w-xl">
      <SubStepHeader
        title="Logo & Branding"
        subtitle="Upload your shop logo and pick an accent color for receipts and the customer portal."
        icon={<ImageIcon className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
      />

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Logo image (PNG, JPG, SVG, max 2 MB)
          </label>
          {logoUrl ? (
            <div className="flex items-center gap-4 rounded-lg border border-surface-200 bg-surface-50 p-4 dark:border-surface-700 dark:bg-surface-700/30">
              <img src={logoUrl} alt="Logo preview" className="h-16 w-16 rounded-lg object-contain" />
              <div className="flex-1">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100">Uploaded</p>
                <p className="text-xs text-surface-500 dark:text-surface-400">Click below to replace.</p>
              </div>
              <label className="cursor-pointer rounded-lg border border-surface-300 px-3 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-100 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-700">
                Replace
                <input type="file" accept="image/*" onChange={handleFileChange} className="hidden" />
              </label>
            </div>
          ) : (
            <label className="flex cursor-pointer items-center justify-center gap-2 rounded-lg border-2 border-dashed border-surface-300 bg-surface-50 p-6 text-sm text-surface-500 hover:border-primary-400 hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-700/30 dark:text-surface-400 dark:hover:border-primary-500/60">
              <Upload className="h-5 w-5" />
              {uploading ? 'Uploading...' : 'Click to upload logo'}
              <input type="file" accept="image/*" onChange={handleFileChange} className="hidden" disabled={uploading} />
            </label>
          )}
        </div>

        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Accent color (optional)
          </label>
          <div className="flex items-center gap-3">
            <input
              type="color"
              value={color}
              onChange={(e) => handleColorChange(e.target.value)}
              className="h-10 w-14 cursor-pointer rounded-lg border border-surface-300"
            />
            <input
              type="text"
              value={color}
              onChange={(e) => handleColorChange(e.target.value)}
              placeholder="#0E7490"
              className="flex-1 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm text-surface-900 focus:border-primary-500 focus:outline-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
        </div>

        {error && <p className="text-sm text-red-500">{error}</p>}
      </div>

      <SubStepFooter onCancel={onCancel} onComplete={onComplete} completeLabel="Save branding" />
    </div>
  );
}
