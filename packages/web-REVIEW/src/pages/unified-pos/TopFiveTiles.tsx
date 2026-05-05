import { useQuery } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { Flame } from 'lucide-react';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type { ProductCartItem } from './types';

/**
 * Today's Top 5 quick-add tiles (audit §43.1).
 *
 * Renders the 5 most-sold products today as one-tap tiles above the
 * products grid. Eliminates the "cashier searches 'case' 30x a day" tax.
 * Data comes from /api/v1/pos-enrich/top-five which aggregates today's
 * invoice_line_items so it includes both POS cash sales and ticket
 * checkouts.
 */

interface TopFiveItem {
  inventory_item_id: number;
  name: string;
  sku: string | null;
  retail_price: number;
  category: string | null;
  units_sold: number;
}

interface TopFiveResponse {
  data: { items: TopFiveItem[] };
}

export function TopFiveTiles() {
  const addProduct = useUnifiedPosStore((s) => s.addProduct);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['pos-enrich', 'top-five'],
    queryFn: async () => {
      const res = await api.get<TopFiveResponse>('/pos-enrich/top-five');
      return res.data.data.items;
    },
    // 2 min freshness — the "top 5 today" list doesn't churn minute-by-minute.
    staleTime: 2 * 60 * 1000,
  });

  if (isLoading || isError || !data || data.length === 0) {
    return null;
  }

  const handleAdd = (item: TopFiveItem) => {
    const cartItem: ProductCartItem = {
      type: 'product',
      id: genId(),
      inventoryItemId: item.inventory_item_id,
      name: item.name,
      sku: item.sku,
      quantity: 1,
      unitPrice: item.retail_price,
      taxable: true,
      taxInclusive: false,
    };
    addProduct(cartItem);
    toast.success(`Added ${item.name}`);
  };

  return (
    <div className="border-b border-surface-200 bg-orange-50/50 p-3 dark:border-surface-700 dark:bg-orange-500/5">
      <div className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-orange-700 dark:text-orange-400">
        <Flame className="h-3.5 w-3.5" />
        Today's Top 5
      </div>
      <div className="grid grid-cols-5 gap-2">
        {data.map((item) => (
          <button
            key={item.inventory_item_id}
            onClick={() => handleAdd(item)}
            className="flex flex-col items-start justify-between gap-1 rounded-lg border border-orange-200 bg-white px-3 py-2 text-left transition-colors hover:border-orange-400 hover:bg-orange-50 dark:border-orange-500/30 dark:bg-surface-800 dark:hover:border-orange-400 dark:hover:bg-orange-500/10"
            title={`${item.units_sold} sold today — ${formatCurrency(item.retail_price)}`}
          >
            <div className="line-clamp-2 text-xs font-medium text-surface-900 dark:text-surface-50">
              {item.name}
            </div>
            <div className="flex w-full items-center justify-between">
              <span className="text-xs font-semibold text-orange-600 dark:text-orange-400">
                {formatCurrency(item.retail_price)}
              </span>
              <span className="rounded-full bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-700 dark:bg-orange-500/20 dark:text-orange-300">
                {item.units_sold}x
              </span>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
