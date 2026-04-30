import { useState } from 'react';
import type { JSX } from 'react';
import { Image as ImageIcon, Upload, ArrowLeft, ArrowRight } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { validateHexColor } from '@/services/validationService';
import { api } from '@/api/client';

/**
 * Step 13 — Logo & color.
 *
 * Linear-flow rewrite (Agent W5-15). Mirrors `#screen-13` in
 * `mockups/web-setup-wizard.html`:
 *
 *   - Pill breadcrumb (Step 12 · Receipts → Step 13 · Logo → Step 14 · Payment terminal)
 *   - Logo upload card (PNG/JPG/WebP/GIF, ≤ 2 MB, MIME + magic-byte sniff)
 *   - Accent color: 5 Tailwind primary-scale presets + freeform `#RRGGBB` text input
 *     validated by `validateHexColor` (WEB-S4-012). Default cream `#fdeed0`.
 *   - Back / Skip / Continue footer wired to the shell's StepProps callbacks.
 *
 * Persists `store_logo` and `theme_primary_color` via `onUpdate(...)`. The
 * wizard shell flushes everything to `PUT /settings/config` at the end.
 *
 * Logo upload is optional — the user can skip and configure later from
 * Settings → Branding.
 */

const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] as const;
type AllowedMime = (typeof ALLOWED_MIME)[number];

// WEB-FG-014: the `accept=` attr is a hint, not a guard. A `.svg` (XSS via
// inline <script>) or a renamed `evil.exe` will still post through. Match
// the server-side allow-list (jpeg/png/webp/gif) by both `file.type` AND a
// magic-byte sniff so a renamed binary that claims `image/png` via the OS
// shell is rejected before we POST it.
const sniffImageMime = async (file: File): Promise<AllowedMime | null> => {
  const head = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47) return 'image/png';
  // JPEG: FF D8 FF
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'image/jpeg';
  // GIF: "GIF87a" or "GIF89a"
  if (head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return 'image/gif';
  // WEBP: "RIFF" .... "WEBP"
  if (
    head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50
  ) return 'image/webp';
  return null;
};

interface ColorPreset {
  id: string;
  label: string;
  value: string;
}

// Tailwind primary-scale presets. Cream is the brand default.
const COLOR_PRESETS: ReadonlyArray<ColorPreset> = [
  { id: 'cream', label: 'Cream (brand)', value: '#fdeed0' },
  { id: 'blue', label: 'Blue', value: '#3b82f6' },
  { id: 'green', label: 'Green', value: '#10b981' },
  { id: 'red', label: 'Red', value: '#ef4444' },
  { id: 'purple', label: 'Purple', value: '#8b5cf6' },
];

const DEFAULT_COLOR = '#fdeed0';

export function StepLogo({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [logoUrl, setLogoUrl] = useState<string>(pending.store_logo ?? '');
  const [color, setColor] = useState<string>(pending.theme_primary_color ?? DEFAULT_COLOR);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string>('');
  const [colorError, setColorError] = useState<string | null>(null);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      setError('Logo must be under 2 MB.');
      return;
    }
    if (!ALLOWED_MIME.includes(file.type as AllowedMime)) {
      setError('Logo must be a PNG, JPEG, WebP, or GIF image.');
      return;
    }
    const sniffed = await sniffImageMime(file);
    if (!sniffed || sniffed !== file.type) {
      setError('File contents do not match the image type. Please upload a real PNG, JPEG, WebP, or GIF.');
      return;
    }
    setUploading(true);
    setError('');
    try {
      const formData = new FormData();
      formData.append('logo', file);
      // POST /settings/logo returns { success, data: { store_logo } } where
      // store_logo is a "/uploads/{slug}/{filename}" path. The server already
      // writes it into store_config.store_logo; we also stash it in pending so
      // the review step can preview it and the wizard's final flush is
      // idempotent (writing the same value is a no-op).
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

  const commitColor = (next: string) => {
    setColor(next);
    const validationError = validateHexColor(next);
    setColorError(validationError);
    if (!validationError) {
      onUpdate({ theme_primary_color: next });
    }
  };

  const handlePresetClick = (preset: ColorPreset) => {
    commitColor(preset.value);
  };

  const handleHexInput = (raw: string) => {
    // Normalize: strip whitespace, lowercase. Always set local state so the
    // user can type freely; only persist when it validates.
    const next = raw.trim().toLowerCase();
    commitColor(next);
  };

  const handleNativePicker = (raw: string) => {
    // <input type="color"> always emits #rrggbb lowercase already.
    commitColor(raw);
  };

  const handleContinue = () => {
    // Block advance on invalid hex — but only if the user typed something.
    if (validateHexColor(color)) {
      setColorError('Use #RRGGBB hex format');
      return;
    }
    // Belt-and-suspenders: ensure latest values are pushed to pending before
    // the shell snapshots state for the next step.
    onUpdate({
      theme_primary_color: color,
      ...(logoUrl ? { store_logo: logoUrl } : {}),
    });
    onNext();
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const isPresetActive = (presetValue: string) =>
    color.toLowerCase() === presetValue.toLowerCase();

  return (
    <div className="mx-auto max-w-xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300">
          <ImageIcon className="h-6 w-6" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Logo & branding
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Upload your shop logo and pick an accent color for receipts and the customer portal.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {/* ── Logo upload ───────────────────────────────────────────── */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Logo (PNG, JPG, WebP, GIF — max 2 MB)
          </label>
          {logoUrl ? (
            <div className="flex items-center gap-4 rounded-xl border border-surface-200 bg-surface-50 p-4 dark:border-surface-700 dark:bg-surface-700/30">
              <img
                src={logoUrl}
                alt="Logo preview"
                className="h-16 w-16 rounded-xl border border-surface-200 bg-white object-contain dark:border-surface-600"
              />
              <div className="flex-1 min-w-0">
                <p className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
                  Uploaded
                </p>
                <p className="text-xs text-surface-500 dark:text-surface-400">
                  Click Replace to swap.
                </p>
              </div>
              <label className="cursor-pointer rounded-lg border border-surface-300 px-3 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-100 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-700">
                Replace
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp,image/gif"
                  onChange={handleFileChange}
                  className="hidden"
                  disabled={uploading}
                />
              </label>
            </div>
          ) : (
            <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-surface-300 bg-surface-50 p-6 text-sm text-surface-500 hover:border-primary-400 hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-700/30 dark:text-surface-400 dark:hover:border-primary-500/60">
              <Upload className="h-5 w-5" />
              {uploading ? 'Uploading…' : 'Click to upload logo'}
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp,image/gif"
                onChange={handleFileChange}
                className="hidden"
                disabled={uploading}
              />
            </label>
          )}
          {error ? (
            <p role="alert" aria-live="polite" className="mt-2 text-sm text-red-500">
              {error}
            </p>
          ) : null}
        </div>

        {/* ── Accent color ──────────────────────────────────────────── */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Accent color
          </label>

          {/* Preset swatches (Tailwind primary scale) */}
          <div className="mb-3 flex flex-wrap gap-2">
            {COLOR_PRESETS.map((preset) => {
              const active = isPresetActive(preset.value);
              return (
                <button
                  key={preset.id}
                  type="button"
                  onClick={() => handlePresetClick(preset)}
                  aria-pressed={active}
                  aria-label={preset.label}
                  title={`${preset.label} (${preset.value})`}
                  className={
                    active
                      ? 'flex h-10 w-10 items-center justify-center rounded-full border-2 border-primary-700 ring-2 ring-primary-300 ring-offset-2 ring-offset-white dark:ring-offset-surface-800'
                      : 'flex h-10 w-10 items-center justify-center rounded-full border border-surface-300 transition-transform hover:scale-105 dark:border-surface-600'
                  }
                  style={{ backgroundColor: preset.value }}
                />
              );
            })}
          </div>

          {/* Native color picker + hex text input */}
          <div className="flex items-center gap-3">
            <input
              type="color"
              value={validateHexColor(color) ? DEFAULT_COLOR : color}
              onChange={(e) => handleNativePicker(e.target.value)}
              aria-label="Pick custom color"
              className="h-10 w-14 cursor-pointer rounded-lg border border-surface-300 dark:border-surface-600"
            />
            <input
              type="text"
              value={color}
              onChange={(e) => handleHexInput(e.target.value)}
              placeholder="#fdeed0"
              spellCheck={false}
              maxLength={7}
              aria-invalid={colorError ? true : undefined}
              className="flex-1 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 font-mono text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
          <p className="mt-1.5 text-xs text-surface-500 dark:text-surface-400">
            Default cream <span className="font-mono">#fdeed0</span> — used on buttons and receipts.
          </p>
          {colorError ? (
            <p role="alert" aria-live="polite" className="mt-1 text-sm text-red-500">
              {colorError}
            </p>
          ) : null}
        </div>

        {/* ── Footer: Back / Skip / Continue ───────────────────────── */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={handleContinue}
              disabled={uploading}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Continue
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepLogo;
