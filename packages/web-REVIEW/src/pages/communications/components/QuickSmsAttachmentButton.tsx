import { useRef, type ChangeEvent } from 'react';
import { Paperclip, X, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

/**
 * Quick SMS attachment button — audit §51.15.
 *
 * The MMS upload backend already works (sms.routes.ts POST /sms/upload-media).
 * This component exposes it in the Quick SMS compose area: a paperclip
 * button → file input → multipart POST → returns a media URL that the
 * parent stores in state to be sent alongside the SMS body.
 */

interface AttachedMedia {
  url: string;
  contentType: string;
  preview: string;
}

interface QuickSmsAttachmentButtonProps {
  value: AttachedMedia | null;
  onChange: (media: AttachedMedia | null) => void;
  uploading: boolean;
  setUploading: (v: boolean) => void;
  className?: string;
  /** Disable when the compose area is locked (e.g. mid-send) */
  disabled?: boolean;
}

const MAX_MMS_BYTES = 5 * 1024 * 1024; // 5MB — backend hard cap
const ALLOWED = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

export function QuickSmsAttachmentButton({
  value,
  onChange,
  uploading,
  setUploading,
  className,
  disabled,
}: QuickSmsAttachmentButtonProps) {
  const fileRef = useRef<HTMLInputElement>(null);

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!ALLOWED.includes(file.type)) {
      toast.error('Only JPEG / PNG / GIF / WebP allowed');
      return;
    }
    if (file.size > MAX_MMS_BYTES) {
      toast.error('Max 5MB per attachment');
      return;
    }

    setUploading(true);
    try {
      const res = await smsApi.uploadMedia(file);
      const data = (res.data as any)?.data || {};
      const preview = URL.createObjectURL(file);
      onChange({
        url: data.url || data.path || '',
        contentType: file.type,
        preview,
      });
    } catch (err: any) {
      toast.error(err?.response?.data?.error || 'Upload failed');
    } finally {
      setUploading(false);
      // Reset input so the same file can be picked again
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  function clear() {
    if (value?.preview) URL.revokeObjectURL(value.preview);
    onChange(null);
  }

  return (
    <div className={cn('inline-flex items-center gap-1', className)}>
      <input
        ref={fileRef}
        type="file"
        accept={ALLOWED.join(',')}
        onChange={onPick}
        className="hidden"
      />
      {!value ? (
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          disabled={disabled || uploading}
          title="Attach photo"
          className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 hover:text-primary-600 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:hover:bg-surface-700"
        >
          {uploading ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Paperclip className="h-4 w-4" />
          )}
        </button>
      ) : (
        <div className="inline-flex items-center gap-1 rounded-lg border border-surface-200 bg-surface-50 p-1 dark:border-surface-600 dark:bg-surface-700">
          <img
            src={value.preview}
            alt="preview"
            className="h-6 w-6 rounded object-cover"
          />
          <button
            type="button"
            onClick={clear}
            aria-label="Remove attachment"
            className="rounded p-0.5 text-surface-500 hover:bg-surface-200 dark:hover:bg-surface-600"
          >
            <X className="h-3 w-3" />
          </button>
        </div>
      )}
    </div>
  );
}
