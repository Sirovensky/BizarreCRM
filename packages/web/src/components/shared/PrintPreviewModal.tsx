import { useRef, useCallback, useEffect } from 'react';
import { X, FileText, Printer, Settings2 } from 'lucide-react';
import { useSettings } from '@/hooks/useSettings';
import { useNavigate } from 'react-router-dom';

interface PrintModalProps {
  ticketId: number;
  invoiceId?: number | null;
  onClose: () => void;
}

export function PrintPreviewModal({ ticketId, invoiceId, onClose }: PrintModalProps) {
  const { getSetting } = useSettings();
  const navigate = useNavigate();
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const defaultSize = getSetting('receipt_default_size', 'receipt80');

  const handlePrint = useCallback((type: 'workorder' | 'receipt') => {
    const typeParam = type === 'receipt' ? '&type=receipt' : '';
    const size = type === 'workorder' ? 'letter' : defaultSize;
    const url = `/print/ticket/${ticketId}?size=${size}${typeParam}&embed=1`;

    const iframe = iframeRef.current;
    if (!iframe) return;

    iframe.src = url;
    iframe.onload = () => {
      // Guard prevents double-fire when the iframe's onload triggers more than
      // once (e.g. print dialog causes an extra load event on some browsers).
      let done = false;
      const firePrint = () => {
        if (done) return;
        done = true;
        try { iframe.contentWindow?.print(); } catch {
          window.open(url.replace('&embed=1', ''), '_blank', 'noopener,noreferrer');
        }
      };
      // Poll until the receipt content is rendered (check for a data attribute)
      const maxWait = 8000;
      const start = Date.now();
      const check = () => {
        try {
          const doc = iframe.contentDocument || iframe.contentWindow?.document;
          const hasContent = doc?.querySelector('[data-print-ready]') || doc?.querySelector('.receipt-content');
          if (hasContent || Date.now() - start > maxWait) {
            // Extra 200ms for images/fonts after content is in DOM
            setTimeout(firePrint, 200);
          } else {
            setTimeout(check, 200);
          }
        } catch {
          // Fallback after timeout
          setTimeout(firePrint, 2000);
        }
      };
      check();
    };
  }, [ticketId, defaultSize]);

  const sizeLabel = defaultSize === 'receipt80' ? '80mm' : defaultSize === 'receipt58' ? '58mm' : 'Letter';

  // Close on Escape key
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  return (
    <>
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="print-preview-title"
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 dark:border-surface-700 px-5 py-4">
          <h2 id="print-preview-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">Print</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="p-5 space-y-3">
          {/* Work Order */}
          <button
            onClick={() => handlePrint('workorder')}
            className="flex w-full items-center gap-4 rounded-xl border-2 border-surface-200 dark:border-surface-700 p-4 text-left transition-all hover:border-blue-400 hover:bg-blue-50 dark:hover:border-blue-500 dark:hover:bg-blue-900/10"
          >
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-blue-100 dark:bg-blue-900/30">
              <FileText className="h-6 w-6 text-blue-600 dark:text-blue-400" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">Work Order</p>
              <p className="text-xs text-surface-500 dark:text-surface-400">Full page — device details, notes, conditions</p>
            </div>
            <span className="text-[10px] font-medium text-surface-400 bg-surface-100 dark:bg-surface-800 rounded px-2 py-0.5">Letter</span>
          </button>

          {/* Receipt — always available (shows as check-in receipt when unpaid) */}
          <button
            onClick={() => handlePrint('receipt')}
            className="flex w-full items-center gap-4 rounded-xl border-2 border-surface-200 dark:border-surface-700 p-4 text-left transition-all hover:border-green-400 hover:bg-green-50 dark:hover:border-green-500 dark:hover:bg-green-900/10"
          >
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-green-100 dark:bg-green-900/30">
              <Printer className="h-6 w-6 text-green-600 dark:text-green-400" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">
                {invoiceId ? 'Receipt' : 'Check-in Receipt'}
              </p>
              <p className="text-xs text-surface-500 dark:text-surface-400">
                {invoiceId ? 'Payment receipt with totals & tax' : 'Customer copy with device info & estimate'}
              </p>
            </div>
            <span className="text-[10px] font-medium text-surface-400 bg-surface-100 dark:bg-surface-800 rounded px-2 py-0.5">{sizeLabel}</span>
          </button>

          {/* Settings link */}
          <button
            onClick={() => { onClose(); navigate('/settings/receipts'); }}
            className="flex w-full items-center justify-center gap-1.5 pt-2 text-xs text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
          >
            <Settings2 className="h-3 w-3" /> Paper size & receipt settings
          </button>
        </div>
      </div>

    </div>
    {/* Hidden iframe for printing — outside backdrop to not block clicks */}
    <iframe
      ref={iframeRef}
      style={{ position: 'fixed', left: '-9999px', top: '-9999px', width: 0, height: 0 }}
      title="Print Frame"
    />
    </>
  );
}
