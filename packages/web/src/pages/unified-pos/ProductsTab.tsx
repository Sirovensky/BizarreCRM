import { useState, useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, ShoppingCart, Loader2 } from 'lucide-react';
import { posApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type { ProductCartItem } from './types';

// ─── Constants ──────────────────────────────────────────────────────

const inputCls = 'w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500';

// ─── ProductsTab ────────────────────────────────────────────────────

export function ProductsTab() {
  const { addProduct } = useUnifiedPosStore();

  const [keyword, setKeyword] = useState('');
  const [debouncedKeyword, setDebouncedKeyword] = useState('');
  const [category, setCategory] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedKeyword(keyword), 300);
    return () => clearTimeout(debounceRef.current);
  }, [keyword]);

  const { data: productsData, isLoading } = useQuery({
    queryKey: ['pos-products', debouncedKeyword, category],
    queryFn: () => posApi.products({
      keyword: debouncedKeyword || undefined,
      category: category || undefined,
    }),
    staleTime: 30000,
  });

  const products: any[] = productsData?.data?.data?.items || [];
  const categories: string[] = productsData?.data?.data?.categories || [];

  const handleAdd = (product: any) => {
    const item: ProductCartItem = {
      type: 'product',
      id: genId(),
      inventoryItemId: product.id,
      name: product.name,
      sku: product.sku || null,
      quantity: 1,
      unitPrice: product.retail_price ?? product.price ?? 0,
      taxable: true,
      taxInclusive: !!product.tax_inclusive,
    };
    addProduct(item);
  };

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Search + filters */}
      <div className="flex-shrink-0 space-y-2 px-4 pt-3 pb-2">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
          <input
            type="text"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            placeholder="Search products..."
            aria-label="Search products"
            className={cn(inputCls, 'pl-9')}
          />
          {isLoading && <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />}
        </div>

        {/* Category filter pills */}
        {categories.length > 0 && (
          <div className="flex gap-1 overflow-x-auto pb-1 scrollbar-hide">
            <button
              onClick={() => setCategory('')}
              className={cn(
                'flex-shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors',
                !category
                  ? 'bg-primary-600 text-white'
                  : 'bg-surface-100 text-surface-600 hover:bg-surface-200 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700',
              )}
            >
              All
            </button>
            {categories.map((cat) => (
              <button
                key={cat}
                onClick={() => setCategory(cat === category ? '' : cat)}
                className={cn(
                  'flex-shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors',
                  category === cat
                    ? 'bg-primary-600 text-white'
                    : 'bg-surface-100 text-surface-600 hover:bg-surface-200 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700',
                )}
              >
                {cat}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Product grid */}
      <div className="flex-1 overflow-y-auto px-4 pb-4">
        {products.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 text-surface-400">
            <ShoppingCart className="h-10 w-10 mb-2" />
            <p className="text-sm">{isLoading ? 'Loading...' : 'No products found'}</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {products.map((p: any) => {
              const isService = p.item_type === 'service';
              const outOfStock = !isService && p.in_stock === 0;

              return (
                <button
                  key={p.id}
                  onClick={() => handleAdd(p)}
                  disabled={outOfStock}
                  className={cn(
                    'relative flex flex-col items-start rounded-xl border p-3 text-left transition-all',
                    outOfStock
                      ? 'cursor-not-allowed border-surface-200 opacity-50 dark:border-surface-700'
                      : 'border-surface-200 bg-white hover:border-primary-400 hover:shadow-md hover:-translate-y-0.5 active:translate-y-0 dark:border-surface-700 dark:bg-surface-800 dark:hover:border-primary-500',
                  )}
                >
                  {/* Type badge */}
                  <div className="mb-2 flex h-8 w-full items-center justify-center rounded-lg bg-surface-100 dark:bg-surface-700">
                    <span className={cn(
                      'text-xs font-bold uppercase tracking-wide',
                      isService ? 'text-green-600 dark:text-green-400' : 'text-blue-600 dark:text-blue-400',
                    )}>
                      {isService ? 'SVC' : 'PRD'}
                    </span>
                  </div>

                  {/* Name */}
                  <p className="w-full text-xs font-medium leading-tight text-surface-800 line-clamp-2 dark:text-surface-200">
                    {p.name}
                  </p>

                  {/* SKU */}
                  {p.sku && (
                    <p className="mt-0.5 w-full truncate font-mono text-[10px] text-surface-400">{p.sku}</p>
                  )}

                  {/* Price */}
                  <p className="mt-1 text-sm font-bold text-surface-900 dark:text-surface-100">
                    {formatCurrency(Number(p.retail_price ?? p.price ?? 0))}
                  </p>

                  {/* Stock */}
                  {!isService && (
                    <p className={cn('mt-0.5 text-xs', p.in_stock <= 2 ? 'text-amber-500' : 'text-surface-400')}>
                      {p.in_stock} left
                    </p>
                  )}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
