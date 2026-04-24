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
      navigator.clipboard.writeText(text).then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }).catch(() => {
        toast.error('Failed to copy to clipboard');
      });
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
