/**
 * SettingsTooltip — a small info icon that expands a help bubble on hover
 * or click. Resolves tooltip text from settingsMetadata by key (or takes an
 * explicit text prop). Addresses the critical-audit finding that many obscure
 * toggles had zero documentation.
 *
 * Click-to-open is intentional so touch users on mobile can read the tip.
 */

import { useState, useRef, useEffect } from 'react';
import { HelpCircle } from 'lucide-react';
import { cn } from '@/utils/cn';
import { getSettingMeta } from '../settingsMetadata';

export interface SettingsTooltipProps {
  /** If provided, looks up the tooltip text from settingsMetadata */
  settingKey?: string;
  /** Or provide explicit text — useful for ad-hoc helpers */
  text?: string;
  /** Optional className for positioning the icon */
  className?: string;
  /** Where to anchor the bubble relative to the icon */
  position?: 'top' | 'bottom' | 'left' | 'right';
}

export function SettingsTooltip({ settingKey, text, className, position = 'top' }: SettingsTooltipProps) {
  const [open, setOpen] = useState(false);
  const wrapperRef = useRef<HTMLSpanElement>(null);

  const resolvedText = text ?? (settingKey ? getSettingMeta(settingKey)?.tooltip ?? '' : '');

  // Close on click outside
  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [open]);

  if (!resolvedText) return null;

  const positionClasses: Record<string, string> = {
    top: 'bottom-full left-1/2 -translate-x-1/2 mb-2',
    bottom: 'top-full left-1/2 -translate-x-1/2 mt-2',
    left: 'right-full top-1/2 -translate-y-1/2 mr-2',
    right: 'left-full top-1/2 -translate-y-1/2 ml-2',
  };

  return (
    <span ref={wrapperRef} className={cn('relative inline-flex items-center', className)}>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen((o) => !o);
        }}
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        aria-label="Help"
        className="inline-flex h-4 w-4 items-center justify-center rounded-full text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-300 transition-colors"
      >
        <HelpCircle className="h-3.5 w-3.5" />
      </button>
      {open && (
        <span
          role="tooltip"
          className={cn(
            'absolute z-50 w-64 rounded-lg border border-surface-200 bg-white px-3 py-2 text-xs text-surface-700 shadow-lg dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200',
            positionClasses[position],
          )}
        >
          {resolvedText}
        </span>
      )}
    </span>
  );
}
