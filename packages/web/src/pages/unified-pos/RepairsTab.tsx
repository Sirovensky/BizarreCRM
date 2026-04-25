import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  Smartphone, Laptop, Tv, Monitor, Tablet, Gamepad2, HardDrive, Zap,
  HelpCircle, Search, ChevronRight, Plus, Check, ArrowLeft, Loader2,
  Wrench, DollarSign, User, FileText, Camera,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { catalogApi, repairPricingApi, settingsApi, customerApi, reportApi, ticketApi } from '@/api/endpoints';
import { useSettings } from '@/hooks/useSettings';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { formatPhoneAsYouType, stripPhone } from '@/utils/phoneFormat';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type { RepairDrillState, PartEntry, DeviceData } from './types';

// ─── Constants ──────────────────────────────────────────────────────

const CATEGORY_TILES = [
  { value: 'phone',    label: 'Mobile',        icon: Smartphone },
  { value: 'tablet',   label: 'Tablet',        icon: Tablet },
  { value: 'laptop',   label: 'Laptop / Mac',  icon: Laptop },
  { value: 'tv',       label: 'TV',            icon: Tv },
  { value: 'desktop',  label: 'Desktop',       icon: Monitor },
  { value: 'console',  label: 'Game Console',  icon: Gamepad2 },
  { value: 'data_recovery', label: 'Data Recovery', icon: HardDrive },
  { value: 'other',    label: 'Other',         icon: HelpCircle },
  { value: 'quick',    label: 'Quick Check-in', icon: Zap },
] as const;

const STEP_ORDER = ['CATEGORY', 'DEVICE', 'SERVICE', 'DETAILS'] as const;
const STEP_LABELS = ['Customer', 'Category', 'Device', 'Service', 'Details'] as const;

const DEVICE_PLACEHOLDER: Record<string, string> = {
  phone: 'e.g. Samsung Galaxy A15',
  tablet: 'e.g. iPad Air 5th Gen',
  laptop: 'e.g. Dell Latitude 5540',
  tv: 'e.g. Samsung UN55TU7000',
  console: 'e.g. PlayStation 5 Slim',
  desktop: 'e.g. Dell OptiPlex 7080',
  other: 'e.g. DJI Mavic 3',
  data_recovery: 'e.g. WD My Passport 2TB',
  quick: 'e.g. Samsung Galaxy A15',
};

const COLOR_OPTIONS = ['Black', 'White', 'Silver', 'Gold', 'Blue', 'Red', 'Green', 'Purple', 'Pink', 'Other'];
const NETWORK_OPTIONS = ['AT&T', 'T-Mobile', 'Verizon', 'Sprint', 'US Cellular', 'Cricket', 'Metro', 'Boost', 'Unlocked', 'Other'];

const ISSUE_MACROS: Record<string, string[]> = {
  phone: ['Cracked screen', 'Battery replacement', 'Charging port', 'Water damage', 'Camera not working', 'Speaker issues', "Won't turn on"],
  tablet: ['Cracked screen', 'Battery replacement', 'Charging port', 'Water damage', "Won't turn on", 'Slow performance'],
  laptop: ["Won't turn on", 'Slow performance', 'Screen replacement', 'Keyboard', 'Battery replacement', 'Fan noise', 'No Wi-Fi'],
  tv: ['No picture', 'Cracked screen', 'No sound', "Won't turn on", 'Backlight issue', 'HDMI port'],
  console: ['HDMI port', 'Disc drive', 'Overheating', 'Controller port', "Won't turn on", 'Blue light of death'],
  desktop: ["Won't turn on", 'Slow performance', 'No display', 'Blue screen', 'Fan noise', 'No Wi-Fi'],
  other: ["Won't turn on", 'Physical damage', 'Not charging', 'Other issue'],
  data_recovery: ['Deleted files', 'Drive not recognized', 'Water damage', 'Clicking noise'],
  quick: ['Quick diagnostic', 'Data transfer', 'Software issue'],
};

const inputCls = 'w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-primary-500';

// Breadcrumb removed — using dot progress bar with back button instead

// ─── Step: CATEGORY ─────────────────────────────────────────────────

function CategoryStep({ onSelect }: { onSelect: (category: string) => void }) {
  // Fetch device model counts per category to show badges and dim empty categories
  const { data: modelsData } = useQuery({
    queryKey: ['device-models-all'],
    queryFn: () => catalogApi.searchDevices({ limit: 1000 }),
    staleTime: 300_000,
  });
  const models: any[] = (modelsData?.data as any)?.data ?? [];
  const countByCategory = models.reduce<Record<string, number>>((acc, m) => {
    const cat = m.category || 'other';
    acc[cat] = (acc[cat] || 0) + 1;
    return acc;
  }, {});

  return (
    <div className="grid grid-cols-3 gap-4 py-2" data-tutorial-target="ticket:device-template-button">
      {CATEGORY_TILES.map(({ value, label, icon: Icon }) => {
        const count = value === 'quick' ? null : (countByCategory[value] ?? 0);
        const isEmpty = count === 0;
        return (
          <button
            key={value}
            onClick={() => onSelect(value)}
            className={cn(
              'flex flex-col items-center justify-center gap-3 rounded-xl border bg-white py-6 px-4 text-center transition-all hover:shadow-md hover:-translate-y-0.5 active:translate-y-0 dark:bg-surface-800',
              isEmpty
                ? 'border-surface-100 opacity-50 dark:border-surface-800'
                : 'border-surface-200 hover:border-primary-400 dark:border-surface-700 dark:hover:border-primary-500',
            )}
          >
            <div className="relative">
              <Icon className={cn('h-10 w-10', isEmpty ? 'text-surface-300 dark:text-surface-600' : 'text-primary-500 dark:text-primary-400')} />
              {count != null && count > 0 && (
                <span className="absolute -right-3 -top-2 inline-flex h-5 min-w-[20px] items-center justify-center rounded-full bg-primary-100 px-1 text-[10px] font-bold text-primary-700 dark:bg-primary-900/40 dark:text-primary-300">
                  {count}
                </span>
              )}
            </div>
            <span className={cn('text-sm font-medium', isEmpty ? 'text-surface-400 dark:text-surface-500' : 'text-surface-700 dark:text-surface-300')}>{label}</span>
            {value === 'quick' && (
              <span className="text-[11px] text-surface-400 dark:text-surface-500 -mt-2">Skip device selection</span>
            )}
          </button>
        );
      })}
    </div>
  );
}

// ─── Step: DEVICE ───────────────────────────────────────────────────

const MANUFACTURER_SHORTCUTS: Record<string, { label: string; names: string[] }[]> = {
  phone: [
    { label: 'Apple', names: ['Apple'] },
    { label: 'Samsung', names: ['Samsung'] },
    { label: 'Google', names: ['Google'] },
    { label: 'Motorola', names: ['Motorola'] },
    { label: 'LG', names: ['LG'] },
    { label: 'OnePlus', names: ['OnePlus'] },
  ],
  tablet: [
    { label: 'Apple iPad', names: ['Apple'] },
    { label: 'Samsung', names: ['Samsung'] },
    { label: 'Lenovo', names: ['Lenovo'] },
    { label: 'Microsoft', names: ['Microsoft'] },
  ],
  laptop: [
    { label: 'Apple', names: ['Apple'] },
    { label: 'Dell', names: ['Dell'] },
    { label: 'HP', names: ['HP'] },
    { label: 'Lenovo', names: ['Lenovo'] },
    { label: 'Asus', names: ['Asus'] },
    { label: 'Acer', names: ['Acer'] },
  ],
  console: [
    { label: 'Nintendo', names: ['Nintendo'] },
    { label: 'PlayStation', names: ['Sony PlayStation'] },
    { label: 'Xbox', names: ['Xbox'] },
    { label: 'Steam', names: ['Steam'] },
  ],
  tv: [
    { label: 'Samsung', names: ['Samsung'] },
    { label: 'LG', names: ['LG'] },
    { label: 'Sony', names: ['Sony'] },
    { label: 'TCL', names: ['TCL'] },
    { label: 'Vizio', names: ['Vizio'] },
    { label: 'Hisense', names: ['Hisense'] },
    { label: 'Insignia', names: ['Insignia'] },
    { label: 'Toshiba', names: ['Toshiba'] },
    { label: 'Sharp', names: ['Sharp'] },
    { label: 'Philips', names: ['Philips'] },
    { label: 'Roku', names: ['Roku'] },
  ],
};

function DeviceStep({ category, onSelect }: {
  category: string;
  onSelect: (id: number, name: string) => void;
}) {
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [otherName, setOtherName] = useState('');
  const [mfgFilter, setMfgFilter] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedQuery(query), 300);
    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const { data: popularData } = useQuery({
    queryKey: ['popular-devices', category],
    queryFn: () => catalogApi.searchDevices({ popular: true, category, limit: 12 }),
  });
  const popularDevices: any[] = popularData?.data?.data || [];

  // When manufacturer filter is active, search by manufacturer name (show all)
  const effectiveQuery = mfgFilter || debouncedQuery;
  const searchEnabled = effectiveQuery.length >= 2;
  const isMfgFilter = !!mfgFilter;

  const { data: searchData, isLoading: searching } = useQuery({
    queryKey: ['device-search', effectiveQuery, category, isMfgFilter],
    queryFn: () => catalogApi.searchDevices({ q: effectiveQuery, category, limit: isMfgFilter ? 100 : 20 }),
    enabled: searchEnabled,
  });
  const searchResults: any[] = searchData?.data?.data || [];

  const showSearch = searchEnabled;
  const shortcuts = MANUFACTURER_SHORTCUTS[category] || [];

  return (
    <div className="space-y-3">
      {/* Manufacturer quick-filter buttons */}
      {shortcuts.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {shortcuts.map((s) => (
            <button
              key={s.label}
              onClick={() => {
                const name = s.names[0];
                if (mfgFilter === name) {
                  setMfgFilter('');
                } else {
                  setMfgFilter(name);
                  setQuery('');
                }
              }}
              className={cn(
                'rounded-lg border px-3 py-2 text-sm font-medium transition-all',
                mfgFilter === s.names[0]
                  ? 'border-primary-500 bg-primary-50 text-primary-700 shadow-sm dark:border-primary-600 dark:bg-primary-900/30 dark:text-primary-300'
                  : 'border-surface-200 text-surface-600 hover:border-primary-300 hover:text-primary-600 dark:border-surface-600 dark:text-surface-300 dark:hover:border-primary-500',
              )}
            >
              {s.label}
            </button>
          ))}
        </div>
      )}

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
        <input
          type="text"
          value={query}
          onChange={(e) => { setQuery(e.target.value); if (e.target.value) setMfgFilter(''); }}
          placeholder="e.g. Samsung Galaxy A15"
          className={cn(inputCls, 'pl-9')}
          autoFocus
        />
        {searching && <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />}
      </div>

      {/* Search results */}
      {showSearch && (
        <div className="max-h-64 overflow-y-auto rounded-lg border border-surface-200 dark:border-surface-700">
          {searchResults.length === 0 && !searching ? (
            <p className="p-3 text-sm text-surface-400">No devices found</p>
          ) : (
            searchResults.map((d: any) => {
              const displayName = mfgFilter && d.name.startsWith(mfgFilter)
                ? d.name.slice(mfgFilter.length).trim()
                : d.name;
              return (
                <button
                  key={d.id}
                  data-tutorial-target="ticket:device-picker-option"
                  onClick={() => onSelect(d.id, `${d.manufacturer_name ?? ''} ${d.name}`.trim())}
                  className="flex w-full items-center gap-3 border-b border-surface-100 px-3 py-2.5 text-left transition-colors last:border-0 hover:bg-surface-50 dark:border-surface-800 dark:hover:bg-surface-800/50"
                >
                  <span className="text-sm font-medium text-surface-800 dark:text-surface-200">
                    {d.manufacturer_name && !mfgFilter && (
                      <span className="text-surface-400 dark:text-surface-500">{d.manufacturer_name} </span>
                    )}
                    {displayName}
                  </span>
                  <ChevronRight className="ml-auto h-4 w-4 text-surface-300" />
                </button>
              );
            })
          )}
        </div>
      )}

      {/* Popular devices - compact list */}
      {!showSearch && popularDevices.length > 0 && (
        <>
          <p className="text-xs font-semibold uppercase tracking-wide text-surface-400">Popular</p>
          <div className="flex flex-wrap gap-1.5">
            {popularDevices.map((d: any) => {
              const displayName = mfgFilter && d.name.startsWith(mfgFilter)
                ? d.name.slice(mfgFilter.length).trim()
                : d.name;
              return (
                <button
                  key={d.id}
                  onClick={() => onSelect(d.id, `${d.manufacturer_name ?? ''} ${d.name}`.trim())}
                  className="rounded-full border border-surface-200 bg-white px-2.5 py-1 text-xs font-medium text-surface-700 transition-all hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-300 dark:hover:border-primary-500 dark:hover:text-primary-400"
                >
                  {d.manufacturer_name && !mfgFilter && <span className="text-surface-400">{d.manufacturer_name} </span>}
                  {displayName}
                </button>
              );
            })}
          </div>
        </>
      )}

      {/* Guidance when nothing is showing */}
      {!showSearch && popularDevices.length === 0 && (
        <p className="text-sm text-surface-400 text-center py-3">Click a manufacturer above or type to search</p>
      )}

      {/* Other device free text */}
      <div className="rounded-lg border border-dashed border-surface-200 dark:border-surface-700 p-3">
        <p className="mb-2 text-xs font-medium text-surface-500">Other device (not in list)</p>
        <div className="flex gap-2">
          <input
            type="text"
            value={otherName}
            onChange={(e) => setOtherName(e.target.value)}
            placeholder={DEVICE_PLACEHOLDER[category] || 'e.g. Samsung Galaxy A15'}
            className={cn(inputCls, 'flex-1')}
          />
          <button
            onClick={() => {
              if (!otherName.trim()) return;
              onSelect(0, otherName.trim());
              setOtherName('');
            }}
            disabled={!otherName.trim()}
            className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-700 disabled:opacity-50"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Step: SERVICE ──────────────────────────────────────────────────

function ServiceStep({ category, deviceModelId, deviceName, onSelect }: {
  category: string;
  deviceModelId: number;
  deviceName: string;
  onSelect: (serviceId: number, serviceName: string, laborPrice: number, gradeId: number | null, gradeParts: PartEntry[]) => void;
}) {
  const [selectedServiceId, setSelectedServiceId] = useState<number | null>(null);
  const [manualPrice, setManualPrice] = useState('');
  const [selectedGradeId, setSelectedGradeId] = useState<number | null>(null);

  const { data: servicesData, isLoading: loadingServices } = useQuery({
    queryKey: ['repair-services', category],
    queryFn: () => repairPricingApi.getServices({ category }),
  });
  const services: any[] = servicesData?.data?.data || [];

  // Price map for quick preview
  const { data: allPricesData } = useQuery({
    queryKey: ['repair-prices-for-device', deviceModelId],
    queryFn: () => repairPricingApi.getPrices({ device_model_id: deviceModelId }),
    enabled: !!deviceModelId,
  });
  const priceMap = new Map<number, number>();
  if (allPricesData?.data?.data) {
    for (const p of allPricesData.data.data as any[]) {
      priceMap.set(p.repair_service_id, p.labor_price);
    }
  }

  // Lookup pricing when service is selected
  const { data: lookupData, isLoading: loadingLookup } = useQuery({
    queryKey: ['repair-pricing-lookup', deviceModelId, selectedServiceId],
    queryFn: () => repairPricingApi.lookup({
      device_model_id: deviceModelId,
      repair_service_id: selectedServiceId!,
    }),
    enabled: !!deviceModelId && !!selectedServiceId,
  });
  const pricingData = lookupData?.data?.data;
  const grades: any[] = pricingData?.grades || [];

  // Auto-select default grade
  useEffect(() => {
    if (!pricingData || selectedGradeId) return;
    if (grades.length > 0) {
      const defaultGrade = grades.find((g: any) => g.is_default) || grades[0];
      setSelectedGradeId(defaultGrade.id);
    }
  }, [pricingData]); // intentional: auto-select default grade only when pricing data arrives

  const handleAdd = () => {
    if (!selectedServiceId) return;
    const service = services.find((s: any) => s.id === selectedServiceId);
    if (!service) return;

    let laborPrice = 0;
    let gradeId: number | null = null;
    const gradeParts: PartEntry[] = [];

    if (pricingData && grades.length > 0 && selectedGradeId) {
      const grade = grades.find((g: any) => g.id === selectedGradeId);
      if (grade) {
        gradeId = grade.id;
        laborPrice = grade.effective_labor_price ?? pricingData.labor_price ?? 0;
        if (grade.part_inventory_item_id) {
          gradeParts.push({
            _key: genId(),
            inventory_item_id: grade.part_inventory_item_id,
            name: grade.inventory_item_name || grade.grade_label,
            sku: null,
            quantity: 1,
            price: grade.part_price ?? 0,
            taxable: true,
            status: grade.inventory_in_stock > 0 ? 'available' : 'missing',
          });
        }
      }
    } else if (pricingData) {
      laborPrice = pricingData.labor_price ?? 0;
    } else {
      // WEB-FB-024: parseFloat coercing typos like "12o.50" silently to 0
      // means the cashier walks out the door charging $0 for labor with no
      // visual feedback. Reject obviously-non-numeric input and abort the
      // add so the cashier sees a toast instead.
      const parsed = parseFloat(manualPrice);
      if (manualPrice.trim() !== '' && (Number.isNaN(parsed) || !/^\d*\.?\d+$/.test(manualPrice.trim()))) {
        toast.error('Invalid manual price — enter a number like 75.00');
        return;
      }
      laborPrice = Number.isFinite(parsed) ? parsed : 0;
    }

    onSelect(selectedServiceId, service.name, laborPrice, gradeId, gradeParts);
    // Advance the ticket tutorial when a service/template is applied.
    window.dispatchEvent(new CustomEvent('pos:template-applied'));
  };

  if (loadingServices) {
    return (
      <div className="flex items-center gap-2 p-4 text-sm text-surface-400">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading repair services...
      </div>
    );
  }

  const selectedGrade = grades.find((g: any) => g.id === selectedGradeId);
  const hasPricing = !!pricingData;
  const showManualPrice = selectedServiceId && !loadingLookup && !hasPricing && deviceModelId > 0;

  return (
    <div className="space-y-4">
      {/* Service pills */}
      <div>
        <div className="mb-2 flex items-center gap-2">
          <Wrench className="h-4 w-4 text-surface-500" />
          <span className="text-sm font-semibold text-surface-700 dark:text-surface-300">Select Service</span>
        </div>
        <div className="flex flex-wrap gap-2">
          {services.filter((s: any) => s.is_active).map((service: any) => {
            const isSelected = selectedServiceId === service.id;
            const previewPrice = priceMap.get(service.id);
            const hasPriceForDevice = previewPrice !== undefined;
            return (
              <button
                key={service.id}
                onClick={() => {
                  setSelectedServiceId(isSelected ? null : service.id);
                  setSelectedGradeId(null);
                  setManualPrice('');
                }}
                className={cn(
                  'inline-flex items-center gap-1.5 rounded-lg border font-medium transition-all',
                  hasPriceForDevice ? 'px-3.5 py-2.5 text-sm shadow-sm' : 'px-3 py-2 text-xs opacity-80',
                  isSelected
                    ? 'border-primary-500 bg-primary-50 text-primary-700 shadow-sm dark:border-primary-600 dark:bg-primary-900/30 dark:text-primary-300'
                    : hasPriceForDevice
                      ? 'border-primary-200 bg-primary-50/50 text-surface-700 hover:border-primary-400 hover:text-primary-600 dark:border-primary-800 dark:bg-primary-900/10 dark:text-surface-200 dark:hover:border-primary-500 dark:hover:text-primary-400'
                      : 'border-surface-200 text-surface-600 hover:border-primary-300 hover:text-primary-600 dark:border-surface-600 dark:text-surface-300 dark:hover:border-primary-500 dark:hover:text-primary-400',
                )}
              >
                {service.name}
                {previewPrice !== undefined && (
                  <span className="text-xs opacity-70"> — ${previewPrice.toFixed(2)}</span>
                )}
                {previewPrice === undefined && (
                  <span className="text-xs opacity-50"> — Custom</span>
                )}
                {isSelected && <Check className="h-3.5 w-3.5" />}
              </button>
            );
          })}
        </div>
      </div>

      {/* Loading lookup */}
      {selectedServiceId && loadingLookup && (
        <div className="flex items-center gap-2 text-sm text-surface-400">
          <Loader2 className="h-3.5 w-3.5 animate-spin" /> Looking up pricing...
        </div>
      )}

      {/* Grade selector */}
      {selectedServiceId && !loadingLookup && grades.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-semibold uppercase text-surface-400">Select Grade</p>
          <div className="space-y-1.5">
            {grades.map((grade: any) => {
              const isGradeSelected = selectedGradeId === grade.id;
              const effectiveLabor = grade.effective_labor_price ?? pricingData?.labor_price ?? 0;
              return (
                <button
                  key={grade.id}
                  onClick={() => setSelectedGradeId(grade.id)}
                  className={cn(
                    'flex w-full items-center gap-3 rounded-lg border px-3 py-2.5 text-left transition-all',
                    isGradeSelected
                      ? 'border-primary-500 bg-primary-50 dark:border-primary-600 dark:bg-primary-900/20'
                      : 'border-surface-200 hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600',
                  )}
                >
                  <span className={cn(
                    'flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full border-2',
                    isGradeSelected ? 'border-primary-600 dark:border-primary-400' : 'border-surface-300 dark:border-surface-600',
                  )}>
                    {isGradeSelected && <span className="h-2 w-2 rounded-full bg-primary-600 dark:bg-primary-400" />}
                  </span>
                  <span className={cn(
                    'flex-1 text-sm font-medium',
                    isGradeSelected ? 'text-primary-700 dark:text-primary-300' : 'text-surface-700 dark:text-surface-300',
                  )}>
                    {grade.grade_label}
                  </span>
                  <span className="text-sm font-semibold text-surface-700 dark:text-surface-200">
                    {formatCurrency(effectiveLabor)}
                  </span>
                  {grade.part_price > 0 && (
                    <span className="text-xs text-surface-400">
                      +Part: {formatCurrency(grade.part_price)}
                    </span>
                  )}
                  {grade.part_inventory_item_id && (
                    <span className={cn(
                      'rounded-full px-2 py-0.5 text-xs font-medium',
                      grade.inventory_in_stock > 0
                        ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                        : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
                    )}>
                      {grade.inventory_in_stock > 0 ? 'In Stock' : 'Out of Stock'}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* No pricing — manual input */}
      {showManualPrice && (
        <div>
          <p className="mb-2 text-sm text-amber-600 dark:text-amber-400">
            No preset price for this device + service. Enter price manually:
          </p>
          <div className="relative" data-tutorial-target="ticket:repair-price-input">
            <DollarSign className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              value={manualPrice}
              onChange={(e) => setManualPrice(e.target.value)}
              placeholder="0.00"
              className={cn(inputCls, 'pl-9')}
              step="0.01"
              min="0"
            />
          </div>
        </div>
      )}

      {/* No pricing, no model (free-text device) */}
      {selectedServiceId && !loadingLookup && deviceModelId === 0 && (
        <div>
          <p className="mb-2 text-sm text-surface-400">
            Custom device - enter price manually:
          </p>
          <div className="relative">
            <DollarSign className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              value={manualPrice}
              onChange={(e) => setManualPrice(e.target.value)}
              placeholder="0.00"
              className={cn(inputCls, 'pl-9')}
              step="0.01"
              min="0"
            />
          </div>
        </div>
      )}

      {/* Add to Ticket button */}
      {selectedServiceId && !loadingLookup && (
        <button
          onClick={handleAdd}
          disabled={!hasPricing && !manualPrice && deviceModelId > 0}
          className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Continue to Details
        </button>
      )}
    </div>
  );
}

// ─── Step: DETAILS ──────────────────────────────────────────────────

function DetailsStep({ drillState, onDone }: {
  drillState: Extract<RepairDrillState, { step: 'DETAILS' }>;
  onDone: () => void;
}) {
  const { addRepair } = useUnifiedPosStore();
  const { getSetting } = useSettings();

  const [imei, setImei] = useState('');
  const [serial, setSerial] = useState('');
  const [passcode, setPasscode] = useState('');
  const [color, setColor] = useState('');
  const [colorOther, setColorOther] = useState('');
  const [network, setNetwork] = useState('');
  const [networkOther, setNetworkOther] = useState('');
  const [preConditions, setPreConditions] = useState<string[]>([]);
  const [deviceLocation, setDeviceLocation] = useState('');
  const [notes, setNotes] = useState('');
  const [warranty, setWarranty] = useState(false);
  const [warrantyDays, setWarrantyDays] = useState(90);

  // Calculate default due date from settings
  const [dueDate, setDueDate] = useState(() => {
    const dueValue = parseInt(getSetting('repair_default_due_value', '3')) || 3;
    const dueUnit = getSetting('repair_default_due_unit', 'days');
    const d = new Date();
    if (dueUnit === 'hours') {
      d.setHours(d.getHours() + dueValue);
    } else {
      d.setDate(d.getDate() + dueValue);
    }
    return d.toISOString().slice(0, 10);
  });

  // Load condition checks for category
  const { data: checksData } = useQuery({
    queryKey: ['condition-checks', drillState.category],
    queryFn: () => settingsApi.getConditionChecks(drillState.category),
  });
  const conditionChecks: any[] = checksData?.data?.data || [];

  // Fallback conditions if no templates configured
  const fallbackConditions = [
    'Screen cracked', 'LCD damage', 'Water damage', 'Battery issues',
    'Charging port broken', 'Camera not working', 'Speaker issues',
    'Buttons not working', 'Overheating', "Won't turn on",
  ];
  const conditions = conditionChecks.length > 0
    ? conditionChecks.map((c: any) => c.label)
    : fallbackConditions;

  // CK19: Auto-populate notes with issue macro matching the selected service
  useEffect(() => {
    const macros = ISSUE_MACROS[drillState.category] || ISSUE_MACROS.other;
    const serviceWords = drillState.serviceName.toLowerCase().split(/\s+/);
    const matched = macros.find((macro) => {
      const macroWords = macro.toLowerCase().split(/\s+/);
      return macroWords.some((w) => serviceWords.some((sw) => sw.length > 3 && w.length > 3 && (sw.includes(w) || w.includes(sw))));
    });
    if (matched) {
      setNotes(matched);
    }
  }, [drillState.serviceName, drillState.category]);

  const toggleCondition = (label: string) => {
    setPreConditions((prev) =>
      prev.includes(label) ? prev.filter((c) => c !== label) : [...prev, label]
    );
  };

  const handleAddToCart = () => {
    const device: DeviceData = {
      device_type: drillState.category,
      device_name: drillState.deviceName,
      device_model_id: drillState.deviceModelId || null,
      imei,
      serial,
      security_code: passcode,
      color: color === 'Other' ? colorOther : color,
      network: network === 'Other' ? networkOther : network,
      pre_conditions: preConditions,
      additional_notes: notes,
      device_location: deviceLocation,
      warranty,
      warranty_days: warranty ? warrantyDays : 0,
      due_date: dueDate,
    };

    addRepair({
      type: 'repair',
      id: genId(),
      device,
      serviceName: drillState.serviceName,
      repairServiceId: drillState.serviceId,
      selectedGradeId: drillState.gradeId,
      laborPrice: drillState.laborPrice,
      lineDiscount: 0,
      parts: [...drillState.gradeParts],
      taxable: false, // labor is tax-free
    });

    toast.success('Added to cart! Select another device or Create Ticket when ready.');
    onDone();
  };

  return (
    <div className="space-y-4">
      {/* Summary banner */}
      <div className="rounded-lg bg-primary-50 px-3 py-2 dark:bg-primary-900/20">
        <p className="text-sm font-medium text-primary-700 dark:text-primary-300">
          {drillState.deviceName} - {drillState.serviceName}
        </p>
        <p className="text-xs text-primary-500">
          {formatCurrency(drillState.laborPrice)} labor
          {drillState.gradeParts.length > 0 && (
            <> + {formatCurrency(drillState.gradeParts.reduce((s, p) => s + p.price * p.quantity, 0))} parts</>
          )}
        </p>
      </div>

      {/* IMEI / Serial row — IMEI only for phones/tablets */}
      {(() => {
        const isMobile = drillState.category === 'phone' || drillState.category === 'tablet';
        return (
          <div className={cn('grid gap-3', isMobile ? 'grid-cols-2' : 'grid-cols-1')}>
            {isMobile && (
              <div>
                <label className="mb-1 block text-xs font-medium text-surface-500">IMEI</label>
                <input type="text" value={imei} onChange={(e) => setImei(e.target.value)} placeholder="IMEI number" className={inputCls} />
              </div>
            )}
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">Serial Number</label>
              <input type="text" value={serial} onChange={(e) => setSerial(e.target.value)} placeholder="Serial number" className={inputCls} />
            </div>
          </div>
        );
      })()}

      {/* Passcode / Color / Network — Network only for phones/tablets */}
      {(() => {
        const isMobile = drillState.category === 'phone' || drillState.category === 'tablet';
        return (
          <div className={cn('grid gap-3', isMobile ? 'grid-cols-3' : 'grid-cols-2')}>
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">
                {drillState.category === 'phone' || drillState.category === 'tablet' ? 'Passcode' : drillState.category === 'laptop' || drillState.category === 'desktop' ? 'Login Password' : 'Security Code'}
              </label>
              <input type="text" value={passcode} onChange={(e) => setPasscode(e.target.value)} placeholder={drillState.category === 'phone' || drillState.category === 'tablet' ? 'e.g. 1234 or pattern' : drillState.category === 'laptop' || drillState.category === 'desktop' ? 'e.g. Windows PIN or password' : 'e.g. access code'} className={inputCls} />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">Color</label>
              <select value={color} onChange={(e) => setColor(e.target.value)} className={inputCls}>
                <option value="">Select color...</option>
                {COLOR_OPTIONS.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
              {color === 'Other' && (
                <input type="text" value={colorOther} onChange={(e) => setColorOther(e.target.value)} placeholder="Specify color" className={`${inputCls} mt-1`} />
              )}
            </div>
            {isMobile && (
              <div>
                <label className="mb-1 block text-xs font-medium text-surface-500">Network</label>
                <select value={network} onChange={(e) => setNetwork(e.target.value)} className={inputCls}>
                  <option value="">Select carrier...</option>
                  {NETWORK_OPTIONS.map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
                {network === 'Other' && (
                  <input type="text" value={networkOther} onChange={(e) => setNetworkOther(e.target.value)} placeholder="Specify carrier" className={`${inputCls} mt-1`} />
                )}
              </div>
            )}
          </div>
        );
      })()}

      {/* Pre-conditions */}
      <div>
        <label className="mb-1 block text-xs font-medium text-surface-500">Pre-existing Conditions</label>
        <p className="mb-2 text-[11px] text-surface-400 dark:text-surface-500">Mark any pre-existing damage:</p>
        <div className="flex flex-wrap gap-1.5">
          {conditions.map((label) => {
            const isChecked = preConditions.includes(label);
            return (
              <button
                key={label}
                onClick={() => toggleCondition(label)}
                className={cn(
                  'rounded-full border px-2.5 py-1 text-xs font-medium transition-all',
                  isChecked
                    ? 'border-amber-400 bg-amber-50 text-amber-700 dark:border-amber-600 dark:bg-amber-900/20 dark:text-amber-300'
                    : 'border-surface-200 text-surface-500 hover:border-surface-300 dark:border-surface-600 dark:text-surface-400 dark:hover:border-surface-500',
                )}
              >
                {isChecked && <Check className="mr-1 inline h-3 w-3" />}
                {label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Device location */}
      <div>
        <label className="mb-1 block text-xs font-medium text-surface-500">Device Location</label>
        <input type="text" value={deviceLocation} onChange={(e) => setDeviceLocation(e.target.value)} placeholder="e.g. Left shelf, Bin #3" className={inputCls} />
      </div>

      {/* Issue macros + Notes */}
      <div>
        <label className="mb-1 block text-xs font-medium text-surface-500">Issue / Additional Notes</label>
        <div className="mb-2 flex flex-wrap gap-1.5">
          {(ISSUE_MACROS[drillState.category] || ISSUE_MACROS.other).map((macro) => {
            const alreadyInNotes = notes.toLowerCase().includes(macro.toLowerCase());
            return (
              <button
                key={macro}
                onClick={() => setNotes((prev) => prev ? `${prev}, ${macro}` : macro)}
                className={cn(
                  'rounded-full border px-2.5 py-1 text-xs font-medium transition-colors',
                  alreadyInNotes
                    ? 'border-primary-400 bg-primary-100 text-primary-800 dark:border-primary-600 dark:bg-primary-900/40 dark:text-primary-200'
                    : 'border-primary-200 dark:border-primary-800 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300 hover:bg-primary-100 dark:hover:bg-primary-900/40',
                )}
              >
                {alreadyInNotes && <Check className="mr-1 inline h-3 w-3" />}
                {macro}
              </button>
            );
          })}
        </div>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="Describe the issue or click a quick option above..."
          rows={2}
          className={inputCls}
        />
      </div>

      {/* Estimated Completion */}
      <div>
        <label className="mb-1 block text-xs font-medium text-surface-500">Estimated Completion</label>
        <input
          type="date"
          value={dueDate}
          onChange={(e) => setDueDate(e.target.value)}
          className={inputCls}
          min={new Date().toISOString().slice(0, 10)}
        />
        {dueDate && (() => {
          const days = Math.ceil((new Date(dueDate + 'T00:00:00').getTime() - new Date().setHours(0,0,0,0)) / 86400000);
          if (days === 0) return <p className="mt-1 text-xs text-amber-600">Due today</p>;
          if (days === 1) return <p className="mt-1 text-xs text-green-600">Due tomorrow</p>;
          if (days > 1) return <p className="mt-1 text-xs text-green-600">Due in {days} days</p>;
          return null;
        })()}
      </div>

      {/* Warranty */}
      <div className="flex items-center gap-3">
        <label className="flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
          <input
            type="checkbox"
            checked={warranty}
            onChange={(e) => setWarranty(e.target.checked)}
            className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
          />
          Warranty repair
        </label>
        {warranty && (
          <div className="flex items-center gap-1.5">
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              value={warrantyDays}
              onChange={(e) => setWarrantyDays(parseInt(e.target.value) || 0)}
              className={cn(inputCls, 'w-20')}
              min={0}
            />
            <span className="text-xs text-surface-400">days</span>
          </div>
        )}
      </div>

      {/* Photo reminder */}
      <div className="flex items-center gap-2 rounded-lg bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800 px-3 py-2">
        <Camera className="h-4 w-4 text-amber-500 shrink-0" />
        <p className="text-xs text-amber-700 dark:text-amber-300">
          Remember to take device photos after check-in for pre-repair documentation.
        </p>
      </div>

      {/* Add to Cart */}
      <button
        onClick={handleAddToCart}
        className="w-full rounded-lg bg-green-600 px-4 py-3 text-sm font-bold text-white transition-colors hover:bg-green-700"
      >
        <Plus className="mr-2 inline h-4 w-4" />
        Add to Cart
      </button>
    </div>
  );
}

// ─── Main RepairsTab ────────────────────────────────────────────────

function CustomerContextBar({ customerId, customerName, onSameDevice }: {
  customerId: number;
  customerName: string;
  onSameDevice?: (deviceModelId: number, deviceName: string, category: string) => void;
}) {
  const { data } = useQuery({
    queryKey: ['customer-recent-repairs', customerId],
    queryFn: () => customerApi.getTickets(customerId, { page: 1 }),
    staleTime: 60000,
  });
  const tickets = (data?.data?.data?.tickets || []).slice(0, 3);
  const lastTicket = tickets[0] as any | undefined;
  const lastDevice = lastTicket?.first_device || lastTicket?.devices?.[0];
  const lastDate = lastTicket?.created_at
    ? new Date(lastTicket.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
    : null;

  return (
    <div className="flex-shrink-0 px-4 pt-3 pb-1 space-y-1">
      <div className="flex items-center gap-2 flex-wrap">
        <div className="inline-flex items-center gap-1.5 rounded-full bg-primary-50 dark:bg-primary-900/20 px-3 py-1 text-xs font-medium text-primary-700 dark:text-primary-300">
          <User className="h-3 w-3" />
          {customerName}
        </div>
        {tickets.length > 0 && (
          <span className="text-[10px] text-surface-400">
            Recent: {tickets.map((t: any) => `${t.first_device?.device_name || t.order_id}`).join(', ')}
          </span>
        )}
      </div>
      {lastTicket && lastDevice && (
        <div className="flex items-center gap-2 rounded-lg bg-surface-50 dark:bg-surface-800/50 px-3 py-1.5 text-xs text-surface-600 dark:text-surface-400">
          <span>Last visit: {lastDate} - {lastDevice.device_name || 'Unknown'} - {lastDevice.service?.name || lastTicket.status_name || 'Repair'}</span>
          {lastDevice.device_model_id && onSameDevice && (
            <button
              onClick={() => onSameDevice(lastDevice.device_model_id, lastDevice.device_name, lastDevice.device_type?.toLowerCase() || 'phone')}
              className="ml-auto shrink-0 rounded bg-primary-100 dark:bg-primary-900/30 px-2 py-0.5 text-[10px] font-medium text-primary-700 dark:text-primary-300 hover:bg-primary-200 dark:hover:bg-primary-900/50 transition-colors"
            >
              Same device?
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function CustomerStep({ onDone }: { onDone: () => void }) {
  const navigate = useNavigate();
  const { setCustomer } = useUnifiedPosStore();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchError, setSearchError] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [newForm, setNewForm] = useState({ first_name: '', last_name: '', phone: '', email: '', referred_by: '' });
  const [creating, setCreating] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  // Quick stats for today
  const { data: dashData } = useQuery({
    queryKey: ['dashboard-quick-stats'],
    queryFn: () => reportApi.dashboard(),
    staleTime: 60000,
  });
  const dashStats = dashData?.data?.data;
  const openTickets = dashStats?.open_tickets ?? dashStats?.openTickets ?? null;
  const awaitingPickup = dashStats?.awaiting_pickup ?? dashStats?.awaitingPickup ?? null;

  // Recent customers (from recent tickets)
  const { data: recentTicketsData } = useQuery({
    queryKey: ['recent-tickets-for-customers'],
    queryFn: () => ticketApi.list({ page: 1, pagesize: 10, sort_by: 'created_at', sort_order: 'desc' }),
    staleTime: 60000,
  });
  const recentCustomers = useMemo(() => {
    const tickets = recentTicketsData?.data?.data?.tickets || recentTicketsData?.data?.data || [];
    const seen = new Set<number>();
    const result: any[] = [];
    for (const t of tickets as any[]) {
      const c = t.customer;
      if (!c || seen.has(c.id)) continue;
      seen.add(c.id);
      result.push(c);
      if (result.length >= 5) break;
    }
    return result;
  }, [recentTicketsData]);

  useEffect(() => {
    if (query.length < 2) { setResults([]); setLoading(false); setSearchError(false); return; }
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(async () => {
      setLoading(true);
      setSearchError(false);
      try {
        const res = await customerApi.search(query);
        const data = res.data?.data;
        setResults(Array.isArray(data) ? data.slice(0, 8) : []);
      } catch (err) {
        // Surface the error so users know an empty list means "search failed"
        // rather than "no matches" — silent failure used to lie to the cashier.
        setResults([]);
        setSearchError(true);
        console.warn('[POS customer search]', err);
        toast.error('Customer search failed. Please try again.');
      }
      finally { setLoading(false); }
    }, 300);
    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const selectCustomer = (c: any) => {
    setCustomer(c);
    onDone();
  };

  const handleCreateCustomer = async () => {
    if (!newForm.first_name.trim()) { toast.error('First name is required'); return; }
    if (!newForm.phone.trim() && !newForm.email.trim()) { toast.error('Phone or email required'); return; }
    setCreating(true);
    try {
      const res = await customerApi.create({
        first_name: newForm.first_name.trim(),
        last_name: newForm.last_name.trim(),
        phone: stripPhone(newForm.phone) || undefined,
        email: newForm.email.trim() || undefined,
        referred_by: newForm.referred_by || undefined,
      } as any);
      const created = res.data?.data;
      if (created) {
        setCustomer(created);
        toast.success('Customer created');
        onDone();
      }
    } catch (err: any) {
      const status = err?.response?.status;
      const msg = err?.response?.data?.message || '';
      if (status === 409 && msg.includes('Phone number already belongs to')) {
        // Extract customer info from error message and offer to use them
        const match = msg.match(/belongs to (.+?) \(ID: (\d+)\)/);
        if (match) {
          toast.error(
            `This phone belongs to ${match[1]}. Search for them above instead.`,
            { duration: 6000 },
          );
          // Pre-fill search with the phone number so user can find existing customer
          setQuery(newForm.phone.trim());
          setShowNew(false);
        } else {
          toast.error(msg, { duration: 5000 });
        }
      } else {
        toast.error(msg || 'Failed to create customer');
      }
    } finally { setCreating(false); }
  };

  // Fetch open tickets for the inline list
  const { data: ticketsData } = useQuery({
    queryKey: ['pos-open-tickets'],
    queryFn: () => ticketApi.list({ pagesize: 30, sort_by: 'created_at', sort_order: 'desc', status_group: 'active' }),
    staleTime: 30000,
  });
  const openTicketsList: any[] = ticketsData?.data?.data?.tickets || ticketsData?.data?.tickets || [];

  const formatTicketId = (oid: string | number) => {
    const s = String(oid);
    return s.startsWith('T-') ? s : `T-${s.padStart(4, '0')}`;
  };
  const fmtCurrency = (n: number) => formatCurrency(n);

  return (
    <div className="flex flex-col space-y-5 py-2">
      <div className="text-center mb-2">
        <User className="mx-auto h-10 w-10 text-primary-400 mb-2" />
        <h3 className="text-lg font-semibold text-surface-800 dark:text-surface-200">Who is the customer?</h3>
        <p className="text-sm text-surface-500">Search existing or create new</p>
      </div>

      {/* Search existing */}
      <div className="relative mx-auto w-full max-w-md">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search by name, phone, or email..."
          className={cn(inputCls, 'pl-9')}
          autoFocus
        />
        {loading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin text-surface-400" />}
      </div>

      {/* Results */}
      {query.length >= 2 && results.length > 0 && (
        <div className="rounded-lg border border-surface-200 dark:border-surface-700 overflow-hidden">
          {results.map((c: any) => (
            <button
              key={c.id}
              onClick={() => selectCustomer(c)}
              className="flex w-full items-center gap-3 border-b border-surface-100 px-4 py-3 text-left transition-colors last:border-0 hover:bg-surface-50 dark:border-surface-800 dark:hover:bg-surface-800/50"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary-100 dark:bg-primary-900/30">
                <User className="h-4 w-4 text-primary-600 dark:text-primary-400" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
                  {c.first_name} {c.last_name}
                  {c.organization && <span className="ml-1 text-xs text-surface-400">({c.organization})</span>}
                </p>
                <p className="text-xs text-surface-500">
                  {c.mobile || c.phone || ''}
                  {c.email && <span className="ml-2">{c.email}</span>}
                </p>
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-surface-300" />
            </button>
          ))}
        </div>
      )}

      {query.length >= 2 && results.length === 0 && !loading && (
        <p
          className={`text-center text-sm py-2 ${searchError ? 'text-red-500 dark:text-red-400' : 'text-surface-400'}`}
          role={searchError ? 'alert' : undefined}
        >
          {searchError ? 'Search failed — check your connection and try again.' : 'No customers found'}
        </p>
      )}

      {/* Divider */}
      <div className="flex items-center gap-3">
        <div className="flex-1 border-t border-surface-200 dark:border-surface-700" />
        <span className="text-xs font-medium text-surface-400 uppercase">or</span>
        <div className="flex-1 border-t border-surface-200 dark:border-surface-700" />
      </div>

      {/* New customer form */}
      {!showNew ? (
        <>
          <button
            onClick={() => setShowNew(true)}
            className="w-full rounded-lg border-2 border-dashed border-surface-300 py-4 text-sm font-medium text-surface-500 transition-colors hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:hover:border-primary-500 dark:hover:text-primary-400"
          >
            <Plus className="mr-2 inline h-4 w-4" />
            New Customer
          </button>
          {/* CROSS4: walk-in ghost button. No border/fill — signals "allowed but
              unwelcome". Skips the customer step (tickets.customer_id = NULL)
              but still proceeds through device + service + details. */}
          <button
            onClick={() => { setCustomer(null); onDone(); }}
            className="w-full py-2 text-xs font-medium text-surface-500 transition-colors hover:text-surface-700 dark:text-surface-500 dark:hover:text-surface-300"
          >
            Walk-in (no customer info)
          </button>
        </>
      ) : (
        <div className="rounded-lg border border-surface-200 dark:border-surface-700 p-4 space-y-3" onKeyDown={(e) => { if (e.key === 'Enter' && !creating) handleCreateCustomer(); }}>
          <h4 className="text-sm font-semibold text-surface-700 dark:text-surface-300">New Customer</h4>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">First Name *</label>
              <input type="text" value={newForm.first_name} onChange={(e) => setNewForm({ ...newForm, first_name: e.target.value })} className={inputCls} placeholder="First name" autoFocus />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">Last Name</label>
              <input type="text" value={newForm.last_name} onChange={(e) => setNewForm({ ...newForm, last_name: e.target.value })} className={inputCls} placeholder="Last name" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">Phone *</label>
              <input type="tel" value={newForm.phone} onChange={(e) => setNewForm({ ...newForm, phone: formatPhoneAsYouType(e.target.value) })} className={inputCls} placeholder="(303) 555-1234" />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-surface-500">Email</label>
              <input type="email" value={newForm.email} onChange={(e) => setNewForm({ ...newForm, email: e.target.value })} className={inputCls} placeholder="email@example.com" />
            </div>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-500">How did you find us?</label>
            <select value={newForm.referred_by} onChange={(e) => setNewForm({ ...newForm, referred_by: e.target.value })} className={inputCls}>
              <option value="">-- Optional --</option>
              <option value="Google">Google</option>
              <option value="Yelp">Yelp</option>
              <option value="Facebook">Facebook</option>
              <option value="Walk-in">Walk-in</option>
              <option value="Referral">Referral</option>
              <option value="Other">Other</option>
            </select>
          </div>
          <div className="flex gap-2">
            <button
              onClick={handleCreateCustomer}
              disabled={creating}
              className="flex-1 rounded-lg bg-primary-600 py-2.5 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50"
            >
              {creating ? 'Creating...' : 'Create & Continue'}
            </button>
            <button onClick={() => setShowNew(false)} className="rounded-lg border border-surface-200 px-4 py-2.5 text-sm text-surface-500 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-800">
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Open Tickets list */}
      {openTicketsList.length > 0 && (
        <div className="mt-4">
          <div className="flex items-center justify-between mb-2 px-1">
            <h4 className="text-xs font-semibold text-surface-400 uppercase tracking-wider">Open Tickets</h4>
            <button
              onClick={() => navigate('/tickets')}
              className="text-xs text-primary-500 hover:text-primary-600 font-medium"
            >
              View all
            </button>
          </div>
          <div className="rounded-lg border border-surface-200 dark:border-surface-700 overflow-hidden">
            <div className="max-h-64 overflow-y-auto divide-y divide-surface-100 dark:divide-surface-800">
              {openTicketsList.map((t: any) => {
                const device = t.first_device;
                const custName = t.customer
                  ? `${t.customer.first_name || ''} ${t.customer.last_name || ''}`.trim()
                  : 'Walk-in';
                const phone = t.customer?.phone || t.customer?.mobile || '';
                return (
                  <div
                    key={t.id}
                    className="flex items-center gap-3 px-3 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors group"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-bold text-primary-600 dark:text-primary-400">{formatTicketId(t.order_id)}</span>
                        {t.status && (
                          <span
                            className="inline-block h-2 w-2 rounded-full flex-shrink-0"
                            style={{ backgroundColor: t.status.color || '#6b7280' }}
                            title={t.status.name}
                          />
                        )}
                        <span className="text-xs text-surface-500 truncate">{device?.device_name || 'No device'}</span>
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-xs text-surface-600 dark:text-surface-400">{custName}</span>
                        {phone && <span className="text-[10px] text-surface-400">{phone}</span>}
                      </div>
                    </div>
                    <span className="text-xs font-semibold text-surface-700 dark:text-surface-300 flex-shrink-0">
                      {fmtCurrency(t.total || 0)}
                    </span>
                    <button
                      onClick={() => navigate(`/pos?ticket=${t.id}`)}
                      className="flex-shrink-0 rounded-md bg-primary-600 px-2.5 py-1 text-[11px] font-medium text-white opacity-0 group-hover:opacity-100 transition-opacity hover:bg-primary-700"
                    >
                      Checkout
                    </button>
                    <button
                      onClick={() => navigate(`/tickets/${t.id}`)}
                      className="flex-shrink-0 rounded-md border border-surface-200 dark:border-surface-700 px-2.5 py-1 text-[11px] font-medium text-surface-600 dark:text-surface-400 opacity-0 group-hover:opacity-100 transition-opacity hover:bg-surface-100 dark:hover:bg-surface-800"
                    >
                      View
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export function RepairsTab() {
  const { drillState, setDrillState, resetDrill, customer } = useUnifiedPosStore();
  const [customerDone, setCustomerDone] = useState(false);

  // If customer is already set (from search bar or previous selection), skip customer step
  const showCustomerStep = !customer && !customerDone;

  const handleCustomerDone = useCallback(() => {
    setCustomerDone(true);
  }, []);

  const handleCategorySelect = (category: string) => {
    setDrillState({ step: 'DEVICE', category });
  };

  const handleDeviceSelect = (id: number, name: string) => {
    if (drillState.step !== 'DEVICE') return;
    setDrillState({
      step: 'SERVICE',
      category: drillState.category,
      deviceModelId: id,
      deviceName: name,
    });
  };

  const handleServiceSelect = (
    serviceId: number,
    serviceName: string,
    laborPrice: number,
    gradeId: number | null,
    gradeParts: PartEntry[],
  ) => {
    if (drillState.step !== 'SERVICE') return;
    setDrillState({
      step: 'DETAILS',
      category: drillState.category,
      deviceModelId: drillState.deviceModelId,
      deviceName: drillState.deviceName,
      serviceId,
      serviceName,
      laborPrice,
      gradeId,
      gradeParts,
    });
  };

  // Compute current step number (0-based: 0=Customer, 1=Category, 2=Device, 3=Service, 4=Details)
  const currentStepIndex = showCustomerStep
    ? 0
    : STEP_ORDER.indexOf(drillState.step) + 1;

  return (
    <div className="flex h-full flex-col overflow-hidden">
      {/* Persistent customer context bar */}
      {customer && !showCustomerStep && drillState.step !== 'CATEGORY' && (
        <div className="flex-shrink-0 px-4 py-2 bg-surface-50 dark:bg-surface-800/50 border-b border-surface-200 dark:border-surface-700">
          <p className="text-xs text-surface-500 dark:text-surface-400">
            <span className="font-medium text-surface-700 dark:text-surface-300">{customer.first_name} {customer.last_name}</span>
            {(customer.mobile || customer.phone) && <span> &bull; {customer.mobile || customer.phone}</span>}
          </p>
        </div>
      )}

      {/* Customer step label */}
      {showCustomerStep && (
        <div className="flex-shrink-0 px-4 pt-3">
          <div className="flex items-center gap-1.5 mb-4 text-sm">
            <span className="rounded-md px-2 py-1 font-semibold text-primary-600 dark:text-primary-400">Customer</span>
          </div>
        </div>
      )}

      {/* Step indicator with back button */}
      {!showCustomerStep && (
        <div className="flex-shrink-0 px-4 pt-2 pb-1">
          <div className="flex items-center gap-1.5">
            {currentStepIndex > 1 && (
              <button
                onClick={() => {
                  // Go back one step
                  if (drillState.step === 'DETAILS') {
                    setDrillState({ step: 'SERVICE', category: drillState.category, deviceModelId: drillState.deviceModelId, deviceName: drillState.deviceName });
                  } else if (drillState.step === 'SERVICE') {
                    setDrillState({ step: 'DEVICE', category: drillState.category });
                  } else if (drillState.step === 'DEVICE') {
                    setDrillState({ step: 'CATEGORY' });
                  }
                }}
                className="mr-1 flex items-center gap-1 rounded-lg border border-surface-300 dark:border-surface-600 px-2 py-1 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
              >
                <ArrowLeft className="h-3 w-3" />
              </button>
            )}
            {STEP_LABELS.map((label, i) => (
              <div key={label} className="flex items-center gap-1.5">
                {i > 0 && (
                  <div className={cn(
                    'h-px w-4',
                    i <= currentStepIndex ? 'bg-primary-400' : 'bg-surface-200 dark:bg-surface-700',
                  )} />
                )}
                <div
                  className={cn(
                    'flex items-center gap-1',
                    i === currentStepIndex
                      ? 'text-primary-600 dark:text-primary-400'
                      : i < currentStepIndex
                        ? 'text-primary-400 dark:text-primary-500'
                        : 'text-surface-300 dark:text-surface-600',
                  )}
                >
                  <div className={cn(
                    'h-2 w-2 rounded-full',
                    i === currentStepIndex
                      ? 'bg-primary-600 dark:bg-primary-400'
                      : i < currentStepIndex
                        ? 'bg-primary-300 dark:bg-primary-600'
                        : 'bg-surface-300 dark:bg-surface-600',
                  )} />
                  <span className="text-[10px] font-medium">{label}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Show customer name + recent repairs as context on category step */}
      {!showCustomerStep && drillState.step === 'CATEGORY' && customer && (
        <CustomerContextBar
          customerId={customer.id}
          customerName={`${customer.first_name} ${customer.last_name}`}
          onSameDevice={(deviceModelId, deviceName, category) => {
            setDrillState({ step: 'SERVICE', category, deviceModelId, deviceName });
          }}
        />
      )}

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 pb-4">
        {/* Step 0: Customer selection */}
        {showCustomerStep && (
          <CustomerStep onDone={handleCustomerDone} />
        )}

        {!showCustomerStep && drillState.step === 'CATEGORY' && (
          <CategoryStep onSelect={handleCategorySelect} />
        )}

        {drillState.step === 'DEVICE' && (
          <DeviceStep
            category={drillState.category}
            onSelect={handleDeviceSelect}
          />
        )}

        {drillState.step === 'SERVICE' && (
          <ServiceStep
            category={drillState.category}
            deviceModelId={drillState.deviceModelId}
            deviceName={drillState.deviceName}
            onSelect={handleServiceSelect}
          />
        )}

        {drillState.step === 'DETAILS' && (
          <DetailsStep
            drillState={drillState}
            onDone={resetDrill}
          />
        )}
      </div>
    </div>
  );
}
