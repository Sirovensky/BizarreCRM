import { useMemo, useEffect } from 'react';
import { Wrench, ShoppingBag, MoreHorizontal } from 'lucide-react';
import { cn } from '@/utils/cn';
import { useUnifiedPosStore } from './store';
import { useSettings } from '@/hooks/useSettings';
import { RepairsTab } from './RepairsTab';
import { ProductsTab } from './ProductsTab';
import { MiscTab } from './MiscTab';

// ─── Tab definition ─────────────────────────────────────────────────

const ALL_TABS = [
  { key: 'repairs' as const,  label: 'Repairs',  icon: Wrench,        settingKey: 'pos_show_repairs' },
  { key: 'products' as const, label: 'Products', icon: ShoppingBag,   settingKey: 'pos_show_products' },
  { key: 'misc' as const,     label: 'Misc',     icon: MoreHorizontal, settingKey: 'pos_show_miscellaneous' },
] as const;

// ─── RightPanel ─────────────────────────────────────────────────────

export function RightPanel() {
  const { activeTab, setActiveTab } = useUnifiedPosStore();
  const { getSetting } = useSettings();

  // F22: pos_show_* toggles — hide tabs when set to '0'
  const visibleTabs = useMemo(
    () => ALL_TABS.filter(t => getSetting(t.settingKey, '1') !== '0'),
    [getSetting],
  );

  // If active tab is hidden, switch to first visible tab
  useEffect(() => {
    if (visibleTabs.length > 0 && !visibleTabs.some(t => t.key === activeTab)) {
      setActiveTab(visibleTabs[0].key);
    }
  }, [visibleTabs, activeTab, setActiveTab]);

  return (
    <div className="flex h-full flex-col overflow-hidden bg-white dark:bg-surface-900">
      {/* Tab buttons */}
      <div className="flex flex-shrink-0 border-b border-surface-200 dark:border-surface-700">
        {visibleTabs.map(({ key, label, icon: Icon }) => {
          const isActive = activeTab === key;
          return (
            <button
              key={key}
              onClick={() => setActiveTab(key)}
              className={cn(
                'flex flex-1 items-center justify-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors',
                isActive
                  ? 'border-b-2 border-teal-500 text-teal-600 dark:border-teal-400 dark:text-teal-400'
                  : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
              )}
            >
              <Icon className="h-4 w-4" />
              {label}
            </button>
          );
        })}
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'repairs' && <RepairsTab />}
        {activeTab === 'products' && <ProductsTab />}
        {activeTab === 'misc' && <MiscTab />}
      </div>
    </div>
  );
}
