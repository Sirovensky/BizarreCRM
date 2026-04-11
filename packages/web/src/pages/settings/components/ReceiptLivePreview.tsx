/**
 * ReceiptLivePreview — renders a scaled-down, pixel-approximate thermal/letter
 * receipt that updates as the user edits header / footer / title / terms in
 * the Receipts tab. Resolves the critical-audit complaint that users had no
 * way to see what their receipt actually looked like without printing a test.
 *
 * The rendering is intentionally simple — we mirror the structure of the
 * server-side receipt renderer, not its exact pixel output, so designers can
 * preview copy without waiting for a round-trip to the printer endpoint.
 */

import { useMemo } from 'react';
import { cn } from '@/utils/cn';

export interface ReceiptLivePreviewProps {
  /** The store name to print at the top */
  storeName?: string;
  /** The store address to show under the name */
  storeAddress?: string;
  /** Large receipt title (overrides store name if set) */
  title?: string;
  /** Header message printed above the line items */
  header?: string;
  /** Terms printed under the totals */
  terms?: string;
  /** Friendly footer message at the very bottom */
  footer?: string;
  /** Receipt size: letter, thermal_58, thermal_80 */
  size?: 'letter' | 'thermal_58' | 'thermal_80';
  /** Optional logo URL (rendered as tiny thumbnail) */
  logoUrl?: string;
  /** Extra className */
  className?: string;
}

/** Mocked line items so the preview always has content even before save */
const DEMO_ITEMS: { label: string; qty: number; price: number }[] = [
  { label: 'iPhone 14 Screen Repair', qty: 1, price: 189.0 },
  { label: 'Tempered Glass Protector', qty: 1, price: 19.95 },
];

export function ReceiptLivePreview({
  storeName = 'Your Shop',
  storeAddress,
  title,
  header,
  terms,
  footer,
  size = 'thermal_80',
  logoUrl,
  className,
}: ReceiptLivePreviewProps) {
  const displayTitle = title?.trim() || storeName;

  const { subtotal, tax, total } = useMemo(() => {
    const sub = DEMO_ITEMS.reduce((acc, it) => acc + it.qty * it.price, 0);
    const t = Math.round(sub * 0.08 * 100) / 100;
    return { subtotal: sub, tax: t, total: sub + t };
  }, []);

  const widthClass =
    size === 'letter'
      ? 'w-[340px]'
      : size === 'thermal_58'
        ? 'w-[180px] text-[10px]'
        : 'w-[240px] text-[11px]';

  return (
    <div
      className={cn(
        'sticky top-20 rounded-xl border border-surface-200 bg-surface-50 p-4 shadow-sm dark:border-surface-700 dark:bg-surface-800/50',
        className
      )}
    >
      <div className="mb-2 flex items-center justify-between">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500">
          Live Preview
        </h4>
        <span className="rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-semibold text-green-700 dark:bg-green-500/20 dark:text-green-300">
          Updates as you type
        </span>
      </div>

      {/* Receipt itself */}
      <div
        className={cn(
          'mx-auto rounded-sm bg-white p-3 font-mono text-[11px] leading-tight text-black shadow-inner',
          widthClass
        )}
      >
        {logoUrl && (
          <div className="mb-2 flex justify-center">
            <img
              src={logoUrl}
              alt="Store logo"
              className="h-10 w-auto object-contain"
              onError={(e) => {
                (e.currentTarget as HTMLImageElement).style.display = 'none';
              }}
            />
          </div>
        )}

        <div className="mb-1 text-center text-[13px] font-bold uppercase">{displayTitle}</div>
        {storeAddress && (
          <div className="mb-2 text-center text-[10px] text-gray-600">{storeAddress}</div>
        )}

        {header && (
          <div className="mb-2 border-b border-dashed border-gray-400 pb-1 text-center">
            {header}
          </div>
        )}

        <div className="mb-1 flex justify-between border-b border-dashed border-gray-400 pb-0.5">
          <span>Item</span>
          <span>Total</span>
        </div>

        {DEMO_ITEMS.map((it, i) => (
          <div key={i} className="flex justify-between">
            <span className="max-w-[60%] truncate">
              {it.qty}x {it.label}
            </span>
            <span>${(it.qty * it.price).toFixed(2)}</span>
          </div>
        ))}

        <div className="mt-2 border-t border-dashed border-gray-400 pt-1">
          <div className="flex justify-between">
            <span>Subtotal</span>
            <span>${subtotal.toFixed(2)}</span>
          </div>
          <div className="flex justify-between">
            <span>Tax (8%)</span>
            <span>${tax.toFixed(2)}</span>
          </div>
          <div className="mt-0.5 flex justify-between border-t border-gray-500 pt-0.5 font-bold">
            <span>TOTAL</span>
            <span>${total.toFixed(2)}</span>
          </div>
        </div>

        {terms && (
          <div className="mt-3 border-t border-dashed border-gray-400 pt-1 text-center text-[9px] italic text-gray-700">
            {terms}
          </div>
        )}

        {footer && (
          <div className="mt-2 text-center text-[10px] font-semibold">{footer}</div>
        )}

        <div className="mt-2 text-center text-[9px] text-gray-400">[BARCODE] #12345</div>
      </div>

      <p className="mt-3 text-center text-[10px] text-surface-400">
        Demo data — your real receipts show actual customer items.
      </p>
    </div>
  );
}
