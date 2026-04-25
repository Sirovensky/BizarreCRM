/**
 * FaqTooltip — inline "What does that mean?" hover/click tooltip.
 *
 * Wraps any child element with an accessible popover (role="tooltip",
 * aria-describedby) and exposes a small ? glyph beside the trigger. Tap
 * or keyboard-focus reveals the explanation. Mobile-friendly via click.
 */
import React, { useEffect, useId, useRef, useState } from 'react';

interface FaqTooltipProps {
  text: string;
  children: React.ReactNode;
}

export function FaqTooltip({ text, children }: FaqTooltipProps): React.ReactElement {
  const [open, setOpen] = useState(false);
  const tooltipId = useId();
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (event: MouseEvent): void => {
      if (ref.current && !ref.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  return (
    <span ref={ref} className="relative inline-flex items-center gap-1">
      {children}
      <button
        type="button"
        aria-describedby={open ? tooltipId : undefined}
        aria-expanded={open}
        onClick={() => setOpen((prev) => !prev)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') setOpen(false);
        }}
        className="inline-flex items-center justify-center w-4 h-4 rounded-full bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 text-[10px] font-bold hover:bg-primary-200 dark:hover:bg-primary-900 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400"
      >
        ?
      </button>
      {open ? (
        <span
          id={tooltipId}
          role="tooltip"
          className="absolute top-full left-0 mt-1 z-10 w-56 rounded-md bg-gray-900 dark:bg-gray-700 text-white text-xs p-2 shadow-lg"
        >
          {text}
        </span>
      ) : null}
    </span>
  );
}
