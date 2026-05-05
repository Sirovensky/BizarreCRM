import { useState, useCallback } from 'react';
import { Copy, Check } from 'lucide-react';
import toast from 'react-hot-toast';

interface CopyButtonProps {
  text: string;
  className?: string;
}

export function CopyButton({ text, className }: CopyButtonProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      e.preventDefault();

      // WEB-FV-007 (Fixer-B19 2026-04-25): fall back to execCommand on
      // non-secure contexts (HTTP, iOS Safari without HTTPS, sandboxed
      // iframes) where navigator.clipboard is undefined or rejects.
      const fallbackCopy = (value: string): boolean => {
        try {
          const ta = document.createElement('textarea');
          ta.value = value;
          ta.setAttribute('readonly', '');
          ta.style.position = 'fixed';
          ta.style.top = '-9999px';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          const ok = document.execCommand('copy');
          document.body.removeChild(ta);
          return ok;
        } catch {
          return false;
        }
      };

      const onSuccess = () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      };

      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(onSuccess).catch(() => {
          if (fallbackCopy(text)) onSuccess();
          else toast.error("Couldn't copy — copy manually");
        });
      } else if (fallbackCopy(text)) {
        onSuccess();
      } else {
        toast.error("Couldn't copy — copy manually");
      }
    },
    [text],
  );

  return (
    <button
      type="button"
      onClick={handleCopy}
      className={
        className ??
        'inline-flex items-center justify-center rounded p-0.5 text-surface-400 transition-colors hover:text-surface-600 dark:hover:text-surface-300'
      }
      aria-label={copied ? 'Copied to clipboard' : 'Copy to clipboard'}
      title="Copy to clipboard"
    >
      {copied ? (
        <Check aria-hidden="true" className="h-3.5 w-3.5 text-green-500" />
      ) : (
        <Copy aria-hidden="true" className="h-3.5 w-3.5" />
      )}
    </button>
  );
}
