import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Lightbulb, Plus, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type { CartItem, ProductCartItem } from './types';

/**
 * Upsell prompts (audit §43.9).
 *
 * "Customer bought a screen → suggest a case". A lightweight, dismissible
 * banner that appears when the cart contains a "screen repair" or "screen"
 * product but no case. Uses the same Top-Five endpoint as a heuristic for
 * "popular cases today" so we don't need a new server endpoint for phase
 * one. Honors the `pos_upsell_enabled` store_config flag via the settings
 * hook — if disabled, the component renders nothing.
 */

interface SettingsResponse {
  data: Record<string, string | null>;
}

interface TopFiveItem {
  inventory_item_id: number;
  name: string;
  sku: string | null;
  retail_price: number;
  category: string | null;
}

interface TopFiveResponse {
  data: { items: TopFiveItem[] };
}

function cartContainsScreenRepair(cart: CartItem[]): boolean {
  return cart.some((ci) => {
    if (ci.type === 'repair') {
      return /screen|lcd|glass|display/i.test(ci.serviceName);
    }
    if (ci.type === 'product') {
      return /screen|lcd|glass|display/i.test(ci.name);
    }
    return false;
  });
}

function cartContainsCase(cart: CartItem[]): boolean {
  return cart.some(
    (ci) => ci.type === 'product' && /case|cover|bumper/i.test((ci as ProductCartItem).name),
  );
}

export function UpsellPrompt() {
  const cartItems = useUnifiedPosStore((s) => s.cartItems);
  const addProduct = useUnifiedPosStore((s) => s.addProduct);
  const [dismissed, setDismissed] = useState(false);

  // Server-side enable flag. Stored in store_config as '1' / '0'.
  const { data: settings } = useQuery({
    queryKey: ['settings', 'pos_upsell_enabled'],
    queryFn: async () => {
      const res = await api.get<SettingsResponse>('/settings');
      return res.data.data;
    },
    staleTime: 60 * 60 * 1000,
  });

  const enabled = (settings?.pos_upsell_enabled ?? '1') === '1';

  const shouldSuggest = useMemo(
    () => enabled && !dismissed && cartContainsScreenRepair(cartItems) && !cartContainsCase(cartItems),
    [enabled, dismissed, cartItems],
  );

  const { data: topFive } = useQuery({
    queryKey: ['pos-enrich', 'top-five'],
    queryFn: async () => {
      const res = await api.get<TopFiveResponse>('/pos-enrich/top-five');
      return res.data.data.items;
    },
    enabled: shouldSuggest,
    staleTime: 2 * 60 * 1000,
  });

  if (!shouldSuggest) return null;

  // Pick the first top-five item that looks like a case, or fall back to the
  // first top-five product if none is case-shaped.
  const suggestion =
    topFive?.find((i) => /case|cover|bumper/i.test(i.name)) ?? topFive?.[0];
  if (!suggestion) return null;

  const addSuggestion = () => {
    const cartItem: ProductCartItem = {
      type: 'product',
      id: genId(),
      inventoryItemId: suggestion.inventory_item_id,
      name: suggestion.name,
      sku: suggestion.sku,
      quantity: 1,
      unitPrice: suggestion.retail_price,
      taxable: true,
      taxInclusive: false,
    };
    addProduct(cartItem);
    toast.success(`Added ${suggestion.name}`);
    setDismissed(true);
  };

  return (
    <div className="flex items-center gap-3 border-b border-amber-200 bg-amber-50 px-4 py-2 text-sm dark:border-amber-500/30 dark:bg-amber-500/10">
      <Lightbulb className="h-4 w-4 flex-shrink-0 text-amber-600 dark:text-amber-400" />
      <div className="flex-1 text-amber-800 dark:text-amber-300">
        Suggest <strong>{suggestion.name}</strong> · {formatCurrency(suggestion.retail_price)}
      </div>
      <button
        onClick={addSuggestion}
        className="flex items-center gap-1 rounded-md bg-amber-600 px-2 py-1 text-xs font-semibold text-white hover:bg-amber-700"
      >
        <Plus className="h-3 w-3" />
        Add
      </button>
      <button
        onClick={() => setDismissed(true)}
        aria-label="Dismiss"
        className="rounded p-1 text-amber-600 hover:bg-amber-100 dark:text-amber-400 dark:hover:bg-amber-500/20"
      >
        <X className="h-3 w-3" />
      </button>
    </div>
  );
}
