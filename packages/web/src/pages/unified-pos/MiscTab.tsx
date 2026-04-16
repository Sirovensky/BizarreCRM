import { useState } from 'react';
import { Plus, Package } from 'lucide-react';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type { MiscCartItem } from './types';

// ─── Constants ──────────────────────────────────────────────────────

const inputCls = 'w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500';

// ─── MiscTab ────────────────────────────────────────────────────────

export function MiscTab() {
  const { addMisc, cartItems } = useUnifiedPosStore();

  const [name, setName] = useState('');
  const [price, setPrice] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [taxable, setTaxable] = useState(true);

  const miscItems = cartItems.filter((c): c is MiscCartItem => c.type === 'misc');

  const handleAdd = () => {
    const trimmedName = name.trim();
    if (!trimmedName) return;

    const parsedPrice = parseFloat(price);
    if (isNaN(parsedPrice) || parsedPrice < 0) return;

    const parsedQty = parseInt(quantity, 10);
    if (isNaN(parsedQty) || parsedQty < 1) return;

    const item: MiscCartItem = {
      type: 'misc',
      id: genId(),
      name: trimmedName,
      unitPrice: parsedPrice,
      quantity: parsedQty,
      taxable,
    };

    addMisc(item);

    // Reset form
    setName('');
    setPrice('');
    setQuantity('1');
    setTaxable(true);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleAdd();
    }
  };

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <div className="flex-shrink-0 space-y-3 px-4 pt-3 pb-4">
        {/* Item name */}
        <div>
          <label className="mb-1 block text-xs font-medium text-surface-500">Item Name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="e.g. Screen protector application"
            className={inputCls}
            autoFocus
          />
        </div>

        {/* Price + Quantity row */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-500">Price ($)</label>
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="0.00"
              className={inputCls}
              step="0.01"
              min="0"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-500">Quantity</label>
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              onKeyDown={handleKeyDown}
              className={inputCls}
              min="1"
            />
          </div>
        </div>

        {/* Taxable */}
        <label className="flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
          <input
            type="checkbox"
            checked={taxable}
            onChange={(e) => setTaxable(e.target.checked)}
            className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
          />
          Taxable
        </label>

        {/* Add button */}
        <button
          onClick={handleAdd}
          disabled={!name.trim() || !price}
          className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Plus className="mr-1.5 inline h-4 w-4" />
          Add to Cart
        </button>
      </div>

      {/* Recent misc items in cart */}
      {miscItems.length > 0 && (
        <div className="flex-1 overflow-y-auto border-t border-surface-200 px-4 pt-3 dark:border-surface-700">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-surface-400">
            Misc items in cart
          </p>
          <div className="space-y-1.5">
            {miscItems.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between rounded-lg border border-surface-100 px-3 py-2 dark:border-surface-700"
              >
                <div className="flex items-center gap-2">
                  <Package className="h-4 w-4 text-surface-400" />
                  <span className="text-sm text-surface-700 dark:text-surface-300">{item.name}</span>
                  {item.quantity > 1 && (
                    <span className="text-xs text-surface-400">x{item.quantity}</span>
                  )}
                </div>
                <span className="text-sm font-medium text-surface-800 dark:text-surface-200">
                  {formatCurrency(item.unitPrice * item.quantity)}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
