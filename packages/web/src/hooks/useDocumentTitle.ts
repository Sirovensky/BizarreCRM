import { useEffect, useRef } from 'react';

/**
 * Set `document.title` for the current route and restore the previous title on
 * unmount. Enables per-route page titles without a global router integration.
 *
 * Usage:
 *
 *   // In any page component:
 *   useDocumentTitle('Dashboard');        // → "Dashboard – BizarreCRM"
 *   useDocumentTitle('Customers');        // → "Customers – BizarreCRM"
 *   useDocumentTitle('Edit Invoice #42'); // → "Edit Invoice #42 – BizarreCRM"
 *
 * Options:
 *   suffix   – appended after " – " (default: "BizarreCRM").
 *   restore  – when true (default) the previous title is restored on unmount.
 *              Set to false in root-level layouts that should never restore.
 *
 * WEB-UIUX-212: canonical hook — pages adopt incrementally by calling this
 * once at the top of their component.
 */
export interface UseDocumentTitleOptions {
  /** String appended after " – ". Default: "BizarreCRM". */
  suffix?: string;
  /** Restore the previous title when the component unmounts. Default: true. */
  restore?: boolean;
}

export function useDocumentTitle(
  title: string,
  options: UseDocumentTitleOptions = {},
): void {
  const { suffix = 'BizarreCRM', restore = true } = options;
  const previousTitle = useRef<string>(document.title);

  useEffect(() => {
    // Capture the title that was set before this component mounted, so nested
    // routes and modals each restore to whatever was active before them.
    previousTitle.current = document.title;

    const fullTitle = title ? `${title} – ${suffix}` : suffix;
    document.title = fullTitle;

    return () => {
      if (restore) {
        document.title = previousTitle.current;
      }
    };
    // BUGHUNT-2026-05-16: previously `suffix` and `restore` were excluded with
    // an eslint-disable, which silently dropped runtime changes to either. The
    // common call site passes a literal, so re-running on suffix/restore
    // change is harmless and correct.
  }, [title, suffix, restore]);
}
