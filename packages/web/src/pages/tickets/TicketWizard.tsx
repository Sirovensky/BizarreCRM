import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, X, Search, User, Smartphone, Tablet, Laptop, Monitor, Gamepad2,
  HelpCircle, Loader2, ChevronDown, ChevronRight, ChevronLeft, Check,
  CheckCircle2, Camera, Printer, Package, Star, Minus, DollarSign,
  Tag, Calendar, FileText, ExternalLink, ShoppingCart, Wrench,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { QRCodeSVG } from 'qrcode.react';
import { ticketApi, customerApi, catalogApi, settingsApi, serverInfoApi, repairPricingApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { getIFixitUrl } from '@/utils/ifixit';

// ─── Types ──────────────────────────────────────────────────────────

interface PartEntry {
  _key: string;
  inventory_item_id: number;
  name: string;
  sku: string | null;
  quantity: number;
  price: number;
  taxable: boolean;
  status: string; // available | missing | ordered
}

interface DeviceForm {
  _key: string;
  device_type: string;
  device_name: string;
  device_model_id: number | null;
  imei: string;
  serial: string;
  security_code: string;
  color: string;
  network: string;
  pre_conditions: string[];
  custom_condition: string;
  additional_notes: string;
  device_location: string;
  warranty: boolean;
  warranty_days: number;
  price: number;
  line_discount: number;
  taxable: boolean;
  parts: PartEntry[];
  repair_service_id: number | null;
  repair_service_name: string;
  selected_grade_id: number | null;
  auto_part_key: string | null; // tracks the auto-added part so we can remove it when grade changes
}

interface CustomerForm {
  id: number | null;
  first_name: string;
  last_name: string;
  phone: string;
  email: string;
}

interface CustomerResult {
  id: number;
  first_name: string;
  last_name: string;
  phone: string | null;
  mobile: string | null;
  email: string | null;
  organization: string | null;
  customer_group_id?: number | null;
  customer_group_name?: string | null;
  group_discount_pct?: number | null;
  group_discount_type?: string | null;
  group_auto_apply?: number | null;
}

// ─── Constants ──────────────────────────────────────────────────────

const DEVICE_TYPES = [
  { value: 'phone', label: 'Phone', icon: Smartphone },
  { value: 'tablet', label: 'Tablet', icon: Tablet },
  { value: 'laptop', label: 'Laptop', icon: Laptop },
  { value: 'desktop', label: 'Desktop', icon: Monitor },
  { value: 'console', label: 'Console', icon: Gamepad2 },
  { value: 'other', label: 'Other', icon: HelpCircle },
];

const DEVICE_ICON_MAP: Record<string, typeof Smartphone> = {
  phone: Smartphone, tablet: Tablet, laptop: Laptop, desktop: Monitor,
  console: Gamepad2, other: HelpCircle,
};

const PRE_CONDITIONS = [
  'Screen cracked', 'LCD damage', 'Water damage', 'Battery issues',
  'Charging port broken', 'Camera not working', 'Speaker issues',
  'Buttons not working', 'Overheating', "Won't turn on",
];

const SOURCES = ['Walk-in', 'Phone', 'Online', 'Referral'];
const STEP_LABELS = ['Customer', 'Devices', 'Parts & Pricing', 'Review'];

function makeDevice(): DeviceForm {
  return {
    _key: (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36)),
    device_type: 'phone',
    device_name: '',
    device_model_id: null,
    imei: '',
    serial: '',
    security_code: '',
    color: '',
    network: '',
    pre_conditions: [],
    custom_condition: '',
    additional_notes: '',
    device_location: '',
    warranty: false,
    warranty_days: 90,
    price: 0,
    line_discount: 0,
    taxable: true,
    parts: [],
    repair_service_id: null,
    repair_service_name: '',
    selected_grade_id: null,
    auto_part_key: null,
  };
}

function initials(first?: string, last?: string) {
  return `${(first || '?').charAt(0)}${(last || '').charAt(0)}`.toUpperCase();
}

// ─── Reusable Input Helpers ─────────────────────────────────────────

function FormLabel({ label, required }: { label: string; required?: boolean }) {
  return (
    <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
      {label}
      {required && <span className="ml-0.5 text-red-500">*</span>}
    </label>
  );
}

const inputCls = 'w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500';

// ─── Inline Parts Search Panel ──────────────────────────────────────

function InlinePartsSearch({
  deviceKey,
  deviceModelId,
  onAdd,
}: {
  deviceKey: string;
  deviceModelId: number | null;
  onAdd: (part: PartEntry) => void;
}) {
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedQuery(query), 300);
    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const { data: searchData, isLoading: searching } = useQuery({
    queryKey: ['parts-search-wizard', debouncedQuery, deviceModelId],
    queryFn: () => catalogApi.partsSearch({ q: debouncedQuery, device_model_id: deviceModelId ?? undefined }),
    enabled: debouncedQuery.length >= 2,
  });

  const results = searchData?.data?.data;
  const inventoryItems: any[] = results?.inventoryItems || [];
  const supplierItems: any[] = results?.supplierItems || [];

  const handleAddInventory = (item: any) => {
    onAdd({
      _key: (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36)),
      inventory_item_id: item.id,
      name: item.name,
      sku: item.sku || null,
      quantity: 1,
      price: item.price ?? item.retail_price ?? item.cost_price ?? 0,
      taxable: true,
      status: item.in_stock > 0 ? 'available' : 'missing',
    });
    setQuery('');
  };

  const handleAddSupplier = (item: any) => {
    // For supplier items, we add them with a temporary negative id; actual import happens on submit
    onAdd({
      _key: (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36)),
      inventory_item_id: -(item.id), // negative = supplier catalog item, needs import
      name: item.name,
      sku: item.sku || null,
      quantity: 1,
      price: item.price ?? 0,
      taxable: true,
      status: 'missing',
    });
    setQuery('');
  };

  return (
    <div className="mt-3">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
        {searching && <Loader2 className="absolute right-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-surface-400" />}
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search parts by name, SKU..."
          className={cn(inputCls, 'pl-9')}
        />
      </div>

      {debouncedQuery.length >= 2 && !searching && (
        <div className="mt-1 max-h-60 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
          {/* In stock (green) */}
          {inventoryItems.filter((i) => i.in_stock > 0).length > 0 && (
            <div>
              <p className="px-3 py-1.5 text-xs font-semibold uppercase text-green-600 dark:text-green-400">In Stock</p>
              {inventoryItems.filter((i) => i.in_stock > 0).map((item) => (
                <button
                  key={`inv-${item.id}`}
                  onClick={() => handleAddInventory(item)}
                  className="flex w-full items-center gap-3 px-3 py-2 text-left transition-colors hover:bg-green-50 dark:hover:bg-green-900/10"
                >
                  <div className="h-2 w-2 flex-shrink-0 rounded-full bg-green-500" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">{item.name}</p>
                    <p className="text-xs text-surface-500">{item.sku ? `SKU: ${item.sku} · ` : ''}Stock: {item.in_stock} · {formatCurrency(item.price ?? item.retail_price ?? 0)}</p>
                  </div>
                  <Plus className="h-4 w-4 text-green-600" />
                </button>
              ))}
            </div>
          )}

          {/* Out of stock (orange) */}
          {inventoryItems.filter((i) => i.in_stock <= 0).length > 0 && (
            <div>
              <p className="px-3 py-1.5 text-xs font-semibold uppercase text-amber-600 dark:text-amber-400">Out of Stock</p>
              {inventoryItems.filter((i) => i.in_stock <= 0).map((item) => (
                <button
                  key={`inv-oos-${item.id}`}
                  onClick={() => handleAddInventory(item)}
                  className="flex w-full items-center gap-3 px-3 py-2 text-left transition-colors hover:bg-amber-50 dark:hover:bg-amber-900/10"
                >
                  <div className="h-2 w-2 flex-shrink-0 rounded-full bg-amber-500" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">{item.name}</p>
                    <p className="text-xs text-surface-500">{item.sku ? `SKU: ${item.sku} · ` : ''}Out of stock · {formatCurrency(item.price ?? item.retail_price ?? 0)}</p>
                  </div>
                  <Plus className="h-4 w-4 text-amber-600" />
                </button>
              ))}
            </div>
          )}

          {/* Supplier items (yellow) */}
          {supplierItems.length > 0 && (
            <div>
              <p className="px-3 py-1.5 text-xs font-semibold uppercase text-yellow-600 dark:text-yellow-400">From Supplier</p>
              {supplierItems.slice(0, 15).map((item) => (
                <button
                  key={`sup-${item.id}`}
                  onClick={() => handleAddSupplier(item)}
                  className="flex w-full items-center gap-3 px-3 py-2 text-left transition-colors hover:bg-yellow-50 dark:hover:bg-yellow-900/10"
                >
                  <div className="h-2 w-2 flex-shrink-0 rounded-full bg-yellow-500" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">{item.name}</p>
                    <p className="text-xs text-surface-500">{item.source} · {item.sku ? `SKU: ${item.sku} · ` : ''}{formatCurrency(item.price || 0)}</p>
                  </div>
                  <ShoppingCart className="h-4 w-4 text-yellow-600" />
                </button>
              ))}
            </div>
          )}

          {inventoryItems.length === 0 && supplierItems.length === 0 && (
            <p className="py-6 text-center text-sm text-surface-400">No parts found</p>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Device Model Typeahead ─────────────────────────────────────────

function DeviceModelSearch({
  deviceType,
  onSelect,
}: {
  deviceType: string;
  onSelect: (model: { id: number; name: string; manufacturer_name: string; category: string }) => void;
}) {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 200);
    return () => clearTimeout(debounceRef.current);
  }, [search]);

  const { data: searchData, isLoading } = useQuery({
    queryKey: ['device-model-search', debouncedSearch, deviceType],
    queryFn: () => catalogApi.searchDevices({ q: debouncedSearch, category: deviceType || undefined, limit: 12 }),
    enabled: debouncedSearch.length >= 2,
  });
  const results: any[] = searchData?.data?.data || [];

  const { data: popularData } = useQuery({
    queryKey: ['popular-devices-wizard', deviceType],
    queryFn: () => catalogApi.searchDevices({ popular: true, category: deviceType || undefined, limit: 20 }),
  });
  const popularDevices: any[] = (popularData?.data?.data as any[]) || [];

  return (
    <div>
      <FormLabel label="Device Model" required />
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
        {isLoading && <Loader2 className="absolute right-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-surface-400" />}
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder='Search — e.g. "iPhone 15", "Galaxy S24"...'
          className={cn(inputCls, 'pl-9')}
        />
      </div>

      {results.length > 0 && (
        <div className="mt-1 max-h-52 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
          {results.map((m: any) => (
            <button
              key={m.id}
              onClick={() => {
                onSelect({ id: m.id, name: m.name, manufacturer_name: m.manufacturer_name, category: m.category });
                setSearch('');
              }}
              className="flex w-full items-center gap-3 px-3 py-2.5 text-left transition-colors hover:bg-surface-50 dark:hover:bg-surface-700"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-surface-800 dark:text-surface-200">{m.name}</p>
                <p className="text-xs text-surface-400">{m.manufacturer_name} · {m.category}{m.release_year ? ` · ${m.release_year}` : ''}</p>
              </div>
              {m.is_popular === 1 && <Star className="h-3.5 w-3.5 flex-shrink-0 text-amber-400" />}
            </button>
          ))}
        </div>
      )}

      {search.length < 2 && popularDevices.length > 0 && (
        <div className="mt-2">
          <p className="mb-1.5 text-xs font-medium text-surface-400">
            {deviceType ? `Popular ${deviceType}s` : 'Popular devices'}
          </p>
          <div className="flex flex-wrap gap-1.5">
            {popularDevices.slice(0, 18).map((m: any) => (
              <button
                key={m.id}
                onClick={() => onSelect({ id: m.id, name: m.name, manufacturer_name: m.manufacturer_name, category: m.category })}
                className="rounded-full border border-surface-200 px-2.5 py-1 text-xs text-surface-600 transition-colors hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:text-surface-300 dark:hover:border-primary-500 dark:hover:text-primary-400"
              >
                {m.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Repair Service Picker ──────────────────────────────────────────

function RepairServicePicker({
  device,
  onUpdate,
  onAddPart,
  onRemovePart,
}: {
  device: DeviceForm;
  onUpdate: (updates: Partial<DeviceForm>) => void;
  onAddPart: (part: PartEntry) => void;
  onRemovePart: (partKey: string) => void;
}) {
  // Fetch services matching the device category
  const { data: servicesData, isLoading: loadingServices } = useQuery({
    queryKey: ['repair-services', device.device_type],
    queryFn: () => repairPricingApi.getServices({ category: device.device_type }),
  });
  const services: any[] = servicesData?.data?.data || [];

  // When a service is selected AND device_model_id is set, look up pricing
  const { data: lookupData, isLoading: loadingLookup } = useQuery({
    queryKey: ['repair-pricing-lookup', device.device_model_id, device.repair_service_id],
    queryFn: () => repairPricingApi.lookup({
      device_model_id: device.device_model_id!,
      repair_service_id: device.repair_service_id!,
    }),
    enabled: !!device.device_model_id && !!device.repair_service_id,
  });
  const pricingData = lookupData?.data?.data;
  const grades: any[] = pricingData?.grades || [];

  // Quick-price map: for each service, preload price if device_model_id is known
  const { data: allPricesData } = useQuery({
    queryKey: ['repair-prices-for-device', device.device_model_id],
    queryFn: () => repairPricingApi.getPrices({ device_model_id: device.device_model_id! }),
    enabled: !!device.device_model_id,
  });
  const priceMap = new Map<number, number>();
  if (allPricesData?.data?.data) {
    for (const p of allPricesData.data.data as any[]) {
      priceMap.set(p.repair_service_id, p.labor_price);
    }
  }

  const handleSelectService = (service: any) => {
    // If clicking same service, deselect
    if (device.repair_service_id === service.id) {
      // Remove auto-added part
      if (device.auto_part_key) {
        onRemovePart(device.auto_part_key);
      }
      onUpdate({
        repair_service_id: null,
        repair_service_name: '',
        selected_grade_id: null,
        auto_part_key: null,
        price: 0,
        taxable: true,
      });
      return;
    }

    // Remove previously auto-added part
    if (device.auto_part_key) {
      onRemovePart(device.auto_part_key);
    }

    onUpdate({
      repair_service_id: service.id,
      repair_service_name: service.name,
      selected_grade_id: null,
      auto_part_key: null,
    });
  };

  // When pricing data arrives and no grade is selected yet, auto-select the default grade
  useEffect(() => {
    if (!pricingData || device.selected_grade_id) return;

    if (grades.length > 0) {
      const defaultGrade = grades.find((g: any) => g.is_default) || grades[0];
      applyGrade(defaultGrade);
    } else {
      // No grades — just set the labor price
      onUpdate({
        price: pricingData.labor_price ?? 0,
        taxable: false, // labor is tax-free
      });
    }
  }, [pricingData]); // intentional: only re-run when pricing data changes, other deps are stable or intentionally excluded

  const applyGrade = (grade: any) => {
    // Remove previously auto-added part
    if (device.auto_part_key) {
      onRemovePart(device.auto_part_key);
    }

    const laborPrice = grade.effective_labor_price ?? pricingData?.labor_price ?? 0;

    // Auto-add part if grade links to an inventory item
    let newAutoPartKey: string | null = null;
    if (grade.part_inventory_item_id) {
      const partKey = (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36));
      newAutoPartKey = partKey;
      const inStock = grade.inventory_in_stock != null ? grade.inventory_in_stock > 0 : false;
      onAddPart({
        _key: partKey,
        inventory_item_id: grade.part_inventory_item_id,
        name: grade.inventory_item_name || grade.grade_label,
        sku: null,
        quantity: 1,
        price: grade.part_price ?? 0,
        taxable: true, // parts are taxed
        status: inStock ? 'available' : 'missing',
      });
    }

    onUpdate({
      selected_grade_id: grade.id,
      auto_part_key: newAutoPartKey,
      price: laborPrice,
      taxable: false, // labor is tax-free when auto-priced
    });
  };

  if (loadingServices) {
    return (
      <div className="mt-4">
        <div className="flex items-center gap-2 text-sm text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading repair services...
        </div>
      </div>
    );
  }

  if (services.length === 0) return null;

  const selectedGrade = grades.find((g: any) => g.id === device.selected_grade_id);

  return (
    <div className="mt-4 rounded-lg border border-surface-200 bg-surface-50/30 p-4 dark:border-surface-700 dark:bg-surface-800/30">
      <div className="mb-3 flex items-center gap-2">
        <Wrench className="h-4 w-4 text-surface-500" />
        <span className="text-sm font-semibold text-surface-700 dark:text-surface-300">Repair Service</span>
      </div>

      {/* Service pills */}
      <div className="flex flex-wrap gap-2">
        {services.filter((s: any) => s.is_active).map((service: any) => {
          const isSelected = device.repair_service_id === service.id;
          const previewPrice = priceMap.get(service.id);
          return (
            <button
              key={service.id}
              onClick={() => handleSelectService(service)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-lg border px-3 py-2 text-sm font-medium transition-all',
                isSelected
                  ? 'border-primary-500 bg-primary-50 text-primary-700 shadow-sm dark:border-primary-600 dark:bg-primary-900/30 dark:text-primary-300'
                  : 'border-surface-200 text-surface-600 hover:border-primary-300 hover:text-primary-600 dark:border-surface-600 dark:text-surface-300 dark:hover:border-primary-500 dark:hover:text-primary-400',
              )}
            >
              {service.name}
              {device.device_model_id && previewPrice != null && (
                <span className={cn(
                  'text-xs',
                  isSelected ? 'text-primary-500 dark:text-primary-400' : 'text-surface-400',
                )}>
                  {formatCurrency(previewPrice)}
                </span>
              )}
              {isSelected && <Check className="h-3.5 w-3.5" />}
            </button>
          );
        })}
      </div>

      {/* Grade selector */}
      {device.repair_service_id && loadingLookup && (
        <div className="mt-3 flex items-center gap-2 text-sm text-surface-400">
          <Loader2 className="h-3.5 w-3.5 animate-spin" /> Looking up pricing...
        </div>
      )}

      {device.repair_service_id && !loadingLookup && !pricingData && device.device_model_id && (
        <p className="mt-3 text-sm text-amber-600 dark:text-amber-400">
          No preset price for this device + service — enter price manually in Step 2.
        </p>
      )}

      {device.repair_service_id && !device.device_model_id && (
        <p className="mt-3 text-sm text-surface-400">
          Select a device model above to see preset pricing, or set the price manually in Step 2.
        </p>
      )}

      {grades.length > 0 && (
        <div className="mt-3">
          <p className="mb-2 text-xs font-semibold uppercase text-surface-400">Select Grade</p>
          <div className="space-y-1.5">
            {grades.map((grade: any) => {
              const isGradeSelected = device.selected_grade_id === grade.id;
              const effectiveLabor = grade.effective_labor_price ?? pricingData?.labor_price ?? 0;
              return (
                <button
                  key={grade.id}
                  onClick={() => applyGrade(grade)}
                  className={cn(
                    'flex w-full items-center gap-3 rounded-lg border px-3 py-2.5 text-left transition-all',
                    isGradeSelected
                      ? 'border-primary-500 bg-primary-50 dark:border-primary-600 dark:bg-primary-900/20'
                      : 'border-surface-200 hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600',
                  )}
                >
                  {/* Radio indicator */}
                  <span className={cn(
                    'flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full border-2',
                    isGradeSelected
                      ? 'border-primary-600 dark:border-primary-400'
                      : 'border-surface-300 dark:border-surface-600',
                  )}>
                    {isGradeSelected && <span className="h-2 w-2 rounded-full bg-primary-600 dark:bg-primary-400" />}
                  </span>

                  {/* Label */}
                  <span className={cn(
                    'flex-1 text-sm font-medium',
                    isGradeSelected ? 'text-primary-700 dark:text-primary-300' : 'text-surface-700 dark:text-surface-300',
                  )}>
                    {grade.grade_label}
                  </span>

                  {/* Part price */}
                  {grade.part_price > 0 && (
                    <span className="text-sm text-surface-500 dark:text-surface-400">
                      Part: {formatCurrency(grade.part_price)}
                    </span>
                  )}

                  {/* Stock indicator */}
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

      {/* Price summary */}
      {device.repair_service_id && pricingData && (
        <div className="mt-3 rounded-lg bg-surface-100/80 px-3 py-2 dark:bg-surface-800/60">
          <div className="flex items-center justify-between text-sm">
            <span className="text-surface-500 dark:text-surface-400">Labor</span>
            <span className="font-medium text-surface-800 dark:text-surface-200">
              {formatCurrency(device.price)} <span className="text-xs text-surface-400">(tax-free)</span>
            </span>
          </div>
          {selectedGrade && selectedGrade.part_price > 0 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-surface-500 dark:text-surface-400">
                Part: {selectedGrade.inventory_item_name || selectedGrade.grade_label}
              </span>
              <span className="font-medium text-surface-800 dark:text-surface-200">
                {formatCurrency(selectedGrade.part_price)} <span className="text-xs text-surface-400">(taxed)</span>
              </span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Step Indicator ─────────────────────────────────────────────────

function StepIndicator({ current, onGoTo }: { current: number; onGoTo: (step: number) => void }) {
  return (
    <div className="mb-8 flex items-center gap-0">
      {STEP_LABELS.map((label, i) => (
        <div key={label} className="flex flex-1 items-center">
          <button
            onClick={() => { if (i < current) onGoTo(i); }}
            disabled={i > current}
            className={cn(
              'flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
              i === current && 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300',
              i < current && 'cursor-pointer text-primary-600 hover:bg-primary-50 dark:text-primary-400 dark:hover:bg-primary-900/10',
              i > current && 'cursor-not-allowed text-surface-400',
            )}
          >
            <span className={cn(
              'flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full text-xs font-bold',
              i <= current ? 'bg-primary-600 text-white' : 'bg-surface-200 text-surface-500 dark:bg-surface-700',
            )}>
              {i < current ? <Check className="h-3.5 w-3.5" /> : i + 1}
            </span>
            <span className="hidden sm:inline">{label}</span>
          </button>
          {i < STEP_LABELS.length - 1 && <div className="mx-1 h-px flex-1 bg-surface-200 dark:bg-surface-700" />}
        </div>
      ))}
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────

export function TicketWizard() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const isKiosk = searchParams.get('mode') === 'kiosk';

  const [step, setStep] = useState(0);
  const [createdTicket, setCreatedTicket] = useState<any>(null);

  // ─── Customer state ─────────────────────────────────────────────
  const [customerSearch, setCustomerSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<CustomerResult | null>(null);
  const [showNewCustomer, setShowNewCustomer] = useState(false);
  const [newCustomer, setNewCustomer] = useState<CustomerForm>({
    id: null, first_name: '', last_name: '', phone: '', email: '',
  });
  const [searchOpen, setSearchOpen] = useState(false);
  const searchRef = useRef<HTMLDivElement>(null);
  const [source, setSource] = useState('Walk-in');
  const [referredBy, setReferredBy] = useState('');

  // Debounced customer search
  const [debouncedCustSearch, setDebouncedCustSearch] = useState('');
  const custDebounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => {
    clearTimeout(custDebounceRef.current);
    custDebounceRef.current = setTimeout(() => setDebouncedCustSearch(customerSearch), 300);
    return () => clearTimeout(custDebounceRef.current);
  }, [customerSearch]);

  const { data: custSearchData, isLoading: custSearchLoading } = useQuery({
    queryKey: ['customer-search', debouncedCustSearch],
    queryFn: () => customerApi.search(debouncedCustSearch),
    enabled: debouncedCustSearch.length >= 2,
  });
  const custSearchResults: CustomerResult[] = (() => {
    const d = custSearchData?.data?.data;
    return Array.isArray(d) ? d : d?.customers || [];
  })();

  // Close search dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) setSearchOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // ─── Devices state ──────────────────────────────────────────────
  const [devices, setDevices] = useState<DeviceForm[]>([makeDevice()]);

  const updateDevice = useCallback((key: string, updates: Partial<DeviceForm>) => {
    setDevices((prev) => prev.map((d) => d._key === key ? { ...d, ...updates } : d));
  }, []);

  const removeDevice = useCallback((key: string) => {
    setDevices((prev) => prev.filter((d) => d._key !== key));
  }, []);

  const addPartToDevice = useCallback((deviceKey: string, part: PartEntry) => {
    setDevices((prev) => prev.map((d) => {
      if (d._key !== deviceKey) return d;
      // if same inventory item already exists, bump qty
      const existing = d.parts.find((p) => p.inventory_item_id === part.inventory_item_id);
      if (existing) {
        return { ...d, parts: d.parts.map((p) => p.inventory_item_id === part.inventory_item_id ? { ...p, quantity: p.quantity + 1 } : p) };
      }
      return { ...d, parts: [...d.parts, part] };
    }));
  }, []);

  const updatePart = useCallback((deviceKey: string, partKey: string, updates: Partial<PartEntry>) => {
    setDevices((prev) => prev.map((d) => {
      if (d._key !== deviceKey) return d;
      return { ...d, parts: d.parts.map((p) => p._key === partKey ? { ...p, ...updates } : p) };
    }));
  }, []);

  const removePart = useCallback((deviceKey: string, partKey: string) => {
    setDevices((prev) => prev.map((d) => {
      if (d._key !== deviceKey) return d;
      return { ...d, parts: d.parts.filter((p) => p._key !== partKey) };
    }));
  }, []);

  // ─── Step 3 summary fields ──────────────────────────────────────
  const [assignedTo, setAssignedTo] = useState('');
  const [labels, setLabels] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [ticketDiscount, setTicketDiscount] = useState(0);
  const [discountReason, setDiscountReason] = useState('');
  const [internalNotes, setInternalNotes] = useState('');
  const [memberDiscountApplied, setMemberDiscountApplied] = useState(false);

  // Auto-apply member discount when customer is selected
  useEffect(() => {
    if (
      selectedCustomer &&
      selectedCustomer.group_auto_apply &&
      selectedCustomer.group_discount_pct &&
      selectedCustomer.group_discount_pct > 0
    ) {
      setMemberDiscountApplied(true);
    } else {
      setMemberDiscountApplied(false);
    }
  }, [selectedCustomer]);

  // ─── Expanded device sections in step 3 ────────────────────────
  const [expandedDevices, setExpandedDevices] = useState<Record<string, boolean>>({});

  useEffect(() => {
    // Auto-expand all devices when entering step 3
    if (step === 2) {
      const expanded: Record<string, boolean> = {};
      devices.forEach((d) => { expanded[d._key] = true; });
      setExpandedDevices(expanded);
    }
  }, [step]);

  // ─── Queries ────────────────────────────────────────────────────
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  const { data: referralData } = useQuery({
    queryKey: ['referral-sources'],
    queryFn: () => settingsApi.getReferralSources(),
  });
  const referralSources: { id: number; name: string }[] =
    referralData?.data?.data?.referral_sources || referralData?.data?.data?.sources || referralData?.data?.data || [];

  const { data: taxClassData } = useQuery({
    queryKey: ['tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
  });
  const taxClasses: { id: number; name: string; rate: number; is_default?: boolean }[] =
    taxClassData?.data?.data?.tax_classes || taxClassData?.data?.data || [];
  const defaultTaxClass = taxClasses.find((tc) => tc.rate > 0) || taxClasses[0];
  const exemptTaxClass = taxClasses.find((tc) => tc.rate === 0);
  const taxRate = (defaultTaxClass?.rate ?? 8.865) / 100;

  // ─── Totals computation ─────────────────────────────────────────
  const computeTotals = useCallback(() => {
    let subtotal = 0;
    let taxableAmount = 0;

    for (const d of devices) {
      const servicePrice = d.price - d.line_discount;
      subtotal += servicePrice;
      if (d.taxable) taxableAmount += servicePrice;

      for (const p of d.parts) {
        const partTotal = p.price * p.quantity;
        subtotal += partTotal;
        if (p.taxable) taxableAmount += partTotal;
      }
    }

    // Calculate effective discount: manual ticket discount + member percentage discount
    let effectiveDiscount = ticketDiscount;
    let memberDiscountAmount = 0;
    if (memberDiscountApplied && selectedCustomer?.group_discount_pct) {
      if (selectedCustomer.group_discount_type === 'fixed') {
        memberDiscountAmount = selectedCustomer.group_discount_pct;
      } else {
        memberDiscountAmount = subtotal * (selectedCustomer.group_discount_pct / 100);
      }
      memberDiscountAmount = Math.round(memberDiscountAmount * 100) / 100;
      effectiveDiscount += memberDiscountAmount;
    }

    const afterDiscount = subtotal - effectiveDiscount;
    // proportional tax reduction when there's a discount
    const discountRatio = subtotal > 0 ? Math.max(0, afterDiscount) / subtotal : 1;
    const tax = taxableAmount * discountRatio * taxRate;
    const total = afterDiscount + tax;

    return { subtotal, discount: effectiveDiscount, memberDiscount: memberDiscountAmount, manualDiscount: ticketDiscount, tax, total };
  }, [devices, ticketDiscount, taxRate, memberDiscountApplied, selectedCustomer]);

  const totals = computeTotals();

  // ─── Create customer mutation ───────────────────────────────────
  const createCustomerMut = useMutation({
    mutationFn: (data: Omit<CustomerForm, 'id'>) => customerApi.create(data as any),
    onSuccess: (res) => {
      const created = res?.data?.data;
      if (created) {
        setSelectedCustomer(created);
        setShowNewCustomer(false);
        toast.success('Customer created');
      }
    },
    onError: () => toast.error('Failed to create customer'),
  });

  // ─── Create ticket mutation ─────────────────────────────────────
  const createTicketMut = useMutation({
    mutationFn: (data: any) => ticketApi.create(data),
    onSuccess: (res) => {
      const ticket = res?.data?.data;
      if (ticket) {
        queryClient.invalidateQueries({ queryKey: ['tickets'] });
        setCreatedTicket(ticket);
        setStep(4); // success
      }
    },
    onError: () => toast.error('Failed to create ticket'),
  });

  // ─── Validation ─────────────────────────────────────────────────
  const validateStep = (s: number): boolean => {
    if (s === 0) {
      if (!selectedCustomer) {
        toast.error('Please select or create a customer');
        return false;
      }
      return true;
    }
    if (s === 1) {
      if (devices.length === 0) {
        toast.error('Add at least one device');
        return false;
      }
      for (let i = 0; i < devices.length; i++) {
        if (!devices[i].device_name.trim()) {
          toast.error(`Device ${i + 1} needs a name`);
          return false;
        }
      }
      return true;
    }
    if (s === 2) return true;
    return true;
  };

  const goNext = () => {
    if (!validateStep(step)) return;
    setStep((s) => Math.min(s + 1, 3));
  };

  const goBack = () => setStep((s) => Math.max(s - 1, 0));

  // ─── Submit ─────────────────────────────────────────────────────
  const handleSubmit = async () => {
    if (!selectedCustomer) return;

    // First: import any supplier catalog parts (negative inventory_item_id) to inventory
    const resolvedDevices = await Promise.all(
      devices.filter((d) => d.device_name.trim()).map(async (d) => {
        const resolvedParts = await Promise.all(
          d.parts.map(async (p) => {
            if (p.inventory_item_id < 0) {
              // Negative ID = supplier catalog item, needs import to inventory first
              const catalogId = Math.abs(p.inventory_item_id);
              try {
                const importRes = await catalogApi.importItem(catalogId, { markup_pct: 0, in_stock_qty: 0 });
                const imported = importRes?.data?.data;
                if (imported?.id) {
                  return { ...p, inventory_item_id: imported.id };
                }
              } catch (err) {
                toast.error(`Failed to import part: ${p.name}`);
              }
              return null; // skip this part if import failed
            }
            return p;
          })
        );
        return {
          device_name: d.device_name.trim(),
          device_type: d.device_type || undefined,
          device_model_id: d.device_model_id || undefined,
          repair_service_id: d.repair_service_id || undefined,
          repair_service_name: d.repair_service_name || undefined,
          imei: d.imei || undefined,
          serial: d.serial || undefined,
          security_code: d.security_code || undefined,
          color: d.color || undefined,
          network: d.network || undefined,
          pre_conditions: [...d.pre_conditions, ...(d.custom_condition.trim() ? [d.custom_condition.trim()] : [])],
          additional_notes: d.additional_notes || undefined,
          device_location: d.device_location || undefined,
          warranty: d.warranty ? 1 : 0,
          warranty_days: d.warranty ? d.warranty_days : 0,
          price: d.price,
          line_discount: d.line_discount,
          tax_class_id: d.taxable ? (defaultTaxClass?.id ?? 1) : (exemptTaxClass?.id ?? 2),
          tax_inclusive: 0,
          parts: resolvedParts
            .filter((p): p is PartEntry => p !== null)
            .map((p) => ({
              inventory_item_id: p.inventory_item_id,
              quantity: p.quantity,
              price: p.price,
            })),
        };
      })
    );

    createTicketMut.mutate({
      customer_id: selectedCustomer.id,
      source: source || undefined,
      referral_source: referredBy || undefined,
      assigned_to: assignedTo ? Number(assignedTo) : undefined,
      labels: labels ? labels.split(',').map((l) => l.trim()).filter(Boolean) : undefined,
      due_on: dueDate || undefined,
      discount: totals.discount || undefined,
      discount_reason: (memberDiscountApplied && selectedCustomer?.customer_group_name
        ? `Member discount (${selectedCustomer.customer_group_name}: ${selectedCustomer.group_discount_type === 'fixed' ? '$' + selectedCustomer.group_discount_pct : selectedCustomer.group_discount_pct + '%'})${discountReason ? ' + ' + discountReason : ''}`
        : discountReason) || undefined,
      internal_notes: internalNotes || undefined,
      devices: resolvedDevices,
    });
  };

  // ─── Reset for "New Check-In" ───────────────────────────────────
  const resetAll = () => {
    setStep(0);
    setSelectedCustomer(null);
    setShowNewCustomer(false);
    setNewCustomer({ id: null, first_name: '', last_name: '', phone: '', email: '' });
    setCustomerSearch('');
    setSource('Walk-in');
    setReferredBy('');
    setDevices([makeDevice()]);
    setAssignedTo('');
    setLabels('');
    setDueDate('');
    setTicketDiscount(0);
    setDiscountReason('');
    setInternalNotes('');
    setMemberDiscountApplied(false);
    setCreatedTicket(null);
  };

  // ─── Success Screen ─────────────────────────────────────────────
  if (step === 4 && createdTicket) {
    return (
      <SuccessScreen
        ticket={createdTicket}
        customer={selectedCustomer}
        devices={devices}
        onNewCheckIn={resetAll}
        isKiosk={isKiosk}
      />
    );
  }

  // ─── Render ─────────────────────────────────────────────────────
  return (
    <div className={cn('mx-auto max-w-4xl', isKiosk && 'kiosk-mode')}>
      {/* Header */}
      <div className="mb-6 flex items-center gap-4">
        <button
          aria-label="Back to tickets"
          onClick={() => navigate('/tickets')}
          className="rounded-lg p-2 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800 dark:hover:text-surface-300"
        >
          <ChevronLeft className="h-5 w-5" />
        </button>
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
            {isKiosk ? 'Customer Check-In' : 'New Repair Ticket'}
          </h1>
          <p className="text-surface-500 dark:text-surface-400">
            {isKiosk ? 'Walk-in repair intake' : 'Create a new repair ticket'}
          </p>
        </div>
      </div>

      <StepIndicator current={step} onGoTo={setStep} />

      <div className="card p-6">
        {/* ── Step 0: Customer ──────────────────────────────────────── */}
        {step === 0 && (
          <div className="space-y-5">
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Customer</h2>

            {selectedCustomer ? (
              <div className="flex items-center justify-between rounded-xl border border-primary-200 bg-primary-50/50 p-4 dark:border-primary-800 dark:bg-primary-950/20">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-600 dark:bg-primary-900 dark:text-primary-400">
                    {initials(selectedCustomer.first_name, selectedCustomer.last_name)}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-surface-900 dark:text-surface-100">
                        {selectedCustomer.first_name} {selectedCustomer.last_name}
                      </p>
                      {memberDiscountApplied && selectedCustomer.customer_group_name && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-semibold text-green-700 dark:bg-green-900/30 dark:text-green-400">
                          <Tag className="h-3 w-3" />
                          Member: {selectedCustomer.customer_group_name} ({selectedCustomer.group_discount_type === 'fixed' ? `$${selectedCustomer.group_discount_pct}` : `${selectedCustomer.group_discount_pct}%`} off)
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-surface-500 dark:text-surface-400">
                      {[selectedCustomer.phone || selectedCustomer.mobile, selectedCustomer.email].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                </div>
                <button
                  aria-label="Clear customer"
                  onClick={() => { setSelectedCustomer(null); setCustomerSearch(''); }}
                  className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-200 hover:text-surface-600 dark:hover:bg-surface-700"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <>
                {/* Search */}
                <div className="relative" ref={searchRef}>
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                    <input
                      type="text"
                      value={customerSearch}
                      onChange={(e) => { setCustomerSearch(e.target.value); setSearchOpen(true); }}
                      onFocus={() => setSearchOpen(true)}
                      placeholder="Search by name, phone, or email..."
                      className={cn(inputCls, 'py-2.5 pl-10')}
                      autoFocus
                    />
                    {custSearchLoading && (
                      <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />
                    )}
                  </div>

                  {searchOpen && debouncedCustSearch.length >= 2 && (
                    <div className="absolute left-0 right-0 top-full z-50 mt-1 max-h-60 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                      {custSearchResults.length === 0 && !custSearchLoading && (
                        <div className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">No customers found</div>
                      )}
                      {custSearchResults.map((c) => (
                        <button
                          key={c.id}
                          onClick={() => { setSelectedCustomer(c); setSearchOpen(false); setCustomerSearch(''); }}
                          className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-surface-50 dark:hover:bg-surface-700"
                        >
                          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-surface-100 text-xs font-medium text-surface-600 dark:bg-surface-700 dark:text-surface-300">
                            {initials(c.first_name, c.last_name)}
                          </div>
                          <div>
                            <p className="text-sm font-medium text-surface-800 dark:text-surface-200">
                              {c.first_name} {c.last_name}
                            </p>
                            <p className="text-xs text-surface-500 dark:text-surface-400">
                              {[c.phone || c.mobile, c.email].filter(Boolean).join(' · ')}
                            </p>
                          </div>
                        </button>
                      ))}
                    </div>
                  )}
                </div>

                {/* New customer toggle */}
                <div className="mt-3">
                  <button
                    onClick={() => setShowNewCustomer((v) => !v)}
                    className="inline-flex items-center gap-1.5 text-sm font-medium text-primary-600 transition-colors hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300"
                  >
                    <Plus className="h-4 w-4" />
                    {showNewCustomer ? 'Cancel New Customer' : 'Create New Customer'}
                  </button>
                </div>

                {showNewCustomer && (
                  <div className="mt-4 rounded-lg border border-surface-200 bg-surface-50/50 p-4 dark:border-surface-700 dark:bg-surface-800/50">
                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                      <div>
                        <FormLabel label="First Name" required />
                        <input value={newCustomer.first_name} onChange={(e) => setNewCustomer((p) => ({ ...p, first_name: e.target.value }))} placeholder="John" className={inputCls} />
                      </div>
                      <div>
                        <FormLabel label="Last Name" required />
                        <input value={newCustomer.last_name} onChange={(e) => setNewCustomer((p) => ({ ...p, last_name: e.target.value }))} placeholder="Doe" className={inputCls} />
                      </div>
                      <div>
                        <FormLabel label="Phone" />
                        <input type="tel" value={newCustomer.phone} onChange={(e) => setNewCustomer((p) => ({ ...p, phone: e.target.value }))} placeholder="(555) 123-4567" className={inputCls} />
                      </div>
                      <div>
                        <FormLabel label="Email" />
                        <input type="email" value={newCustomer.email} onChange={(e) => setNewCustomer((p) => ({ ...p, email: e.target.value }))} placeholder="john@example.com" className={inputCls} />
                      </div>
                    </div>
                    <div className="mt-4">
                      <button
                        onClick={() => {
                          if (!newCustomer.first_name.trim() || !newCustomer.last_name.trim()) {
                            toast.error('First and last name are required');
                            return;
                          }
                          createCustomerMut.mutate({
                            first_name: newCustomer.first_name,
                            last_name: newCustomer.last_name,
                            phone: newCustomer.phone,
                            email: newCustomer.email,
                          });
                        }}
                        disabled={createCustomerMut.isPending}
                        className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-700 disabled:opacity-50"
                      >
                        {createCustomerMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                        Create Customer
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}

            {/* Source + Referral */}
            <div className="grid grid-cols-1 gap-4 pt-2 sm:grid-cols-2">
              <div>
                <FormLabel label="Source" />
                <select value={source} onChange={(e) => setSource(e.target.value)} className={inputCls}>
                  {SOURCES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>
              <div>
                <FormLabel label="Referred By" />
                <select value={referredBy} onChange={(e) => setReferredBy(e.target.value)} className={inputCls}>
                  <option value="">Select...</option>
                  {referralSources.map((r) => <option key={r.id} value={r.name}>{r.name}</option>)}
                </select>
              </div>
            </div>
          </div>
        )}

        {/* ── Step 1: Devices ──────────────────────────────────────── */}
        {step === 1 && (
          <div className="space-y-5">
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Devices</h2>

            {devices.map((device, idx) => (
              <div key={device._key} className="rounded-lg border border-surface-200 bg-surface-50/50 p-4 dark:border-surface-700 dark:bg-surface-800/50">
                {/* Device header */}
                <div className="mb-4 flex items-center justify-between">
                  <h3 className="text-sm font-medium text-surface-700 dark:text-surface-300">Device {idx + 1}</h3>
                  {devices.length > 1 && (
                    <button onClick={() => removeDevice(device._key)} className="rounded-lg p-1 text-surface-400 transition-colors hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-950/30" title="Remove device">
                      <X className="h-4 w-4" />
                    </button>
                  )}
                </div>

                {/* Device type tiles */}
                <div className="mb-4 grid grid-cols-3 gap-2 sm:grid-cols-6">
                  {DEVICE_TYPES.map(({ value, label, icon: Icon }) => (
                    <button
                      key={value}
                      onClick={() => updateDevice(device._key, { device_type: value })}
                      className={cn(
                        'flex flex-col items-center gap-1.5 rounded-xl border-2 p-2.5 transition-all',
                        device.device_type === value
                          ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20'
                          : 'border-surface-200 hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600',
                      )}
                    >
                      <Icon className={cn('h-5 w-5', device.device_type === value ? 'text-primary-600 dark:text-primary-400' : 'text-surface-400')} />
                      <span className={cn('text-xs font-medium', device.device_type === value ? 'text-primary-700 dark:text-primary-300' : 'text-surface-600 dark:text-surface-300')}>{label}</span>
                    </button>
                  ))}
                </div>

                {/* Device model search or selected chip */}
                {device.device_model_id && device.device_name ? (
                  <div className="mb-4 flex items-center gap-2 rounded-lg border border-primary-200 bg-primary-50 px-3 py-2 dark:border-primary-700 dark:bg-primary-900/20">
                    <Star className="h-4 w-4 flex-shrink-0 text-primary-500" />
                    <span className="flex-1 text-sm font-medium text-primary-800 dark:text-primary-200">{device.device_name}</span>
                    <button onClick={() => {
                      // Remove auto-added part if any
                      if (device.auto_part_key) removePart(device._key, device.auto_part_key);
                      updateDevice(device._key, {
                        device_model_id: null, device_name: '',
                        repair_service_id: null, repair_service_name: '', selected_grade_id: null, auto_part_key: null,
                        price: 0, taxable: true,
                      });
                    }} className="text-surface-400 hover:text-surface-600" aria-label="Clear device selection">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                ) : (
                  <div className="mb-4">
                    <DeviceModelSearch
                      deviceType={device.device_type}
                      onSelect={(m) => updateDevice(device._key, {
                        device_model_id: m.id,
                        device_name: `${m.manufacturer_name} ${m.name}`,
                        device_type: m.category,
                      })}
                    />
                    <div className="mt-2">
                      <p className="mb-1 text-xs text-surface-400">Device not in list? Enter manually:</p>
                      <input
                        value={device.device_name}
                        onChange={(e) => {
                          // Remove auto-added part if switching away from a model
                          if (device.auto_part_key) removePart(device._key, device.auto_part_key);
                          updateDevice(device._key, {
                            device_name: e.target.value, device_model_id: null,
                            selected_grade_id: null, auto_part_key: null,
                            price: 0, taxable: true,
                          });
                        }}
                        className={cn(inputCls, 'text-sm')}
                        placeholder="Type device name manually..."
                      />
                    </div>
                  </div>
                )}

                {/* Repair Service Picker */}
                {device.device_name && (
                  <div className="mb-4">
                    <RepairServicePicker
                      device={device}
                      onUpdate={(updates) => updateDevice(device._key, updates)}
                      onAddPart={(part) => addPartToDevice(device._key, part)}
                      onRemovePart={(partKey) => removePart(device._key, partKey)}
                    />
                  </div>
                )}

                {/* IMEI / Serial / Passcode row */}
                <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <div>
                    <FormLabel label="IMEI" />
                    <input value={device.imei} onChange={(e) => updateDevice(device._key, { imei: e.target.value })} className={cn(inputCls, 'font-mono')} placeholder="IMEI number" />
                  </div>
                  <div>
                    <FormLabel label="Serial" />
                    <input value={device.serial} onChange={(e) => updateDevice(device._key, { serial: e.target.value })} className={cn(inputCls, 'font-mono')} placeholder="Serial number" />
                  </div>
                  <div>
                    <FormLabel label="Passcode" />
                    <input value={device.security_code} onChange={(e) => updateDevice(device._key, { security_code: e.target.value })} className={cn(inputCls, 'font-mono')} placeholder="Device passcode" />
                  </div>
                </div>

                {/* Color / Network row */}
                <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <FormLabel label="Color" />
                    <input value={device.color} onChange={(e) => updateDevice(device._key, { color: e.target.value })} className={inputCls} placeholder="e.g. Space Black" />
                  </div>
                  <div>
                    <FormLabel label="Network / Carrier" />
                    <input value={device.network} onChange={(e) => updateDevice(device._key, { network: e.target.value })} className={inputCls} placeholder="e.g. AT&T, Verizon" />
                  </div>
                </div>

                {/* Pre-conditions */}
                <div className="mb-4">
                  <FormLabel label="Pre-conditions (select all that apply)" />
                  <div className="mt-1.5 grid grid-cols-2 gap-2">
                    {PRE_CONDITIONS.map((c) => {
                      const checked = device.pre_conditions.includes(c);
                      return (
                        <button
                          key={c}
                          onClick={() => {
                            const next = checked
                              ? device.pre_conditions.filter((x) => x !== c)
                              : [...device.pre_conditions, c];
                            updateDevice(device._key, { pre_conditions: next });
                          }}
                          className={cn(
                            'flex items-center gap-2 rounded-lg border px-3 py-2 text-left text-sm transition-all',
                            checked
                              ? 'border-primary-500 bg-primary-50 text-primary-700 dark:bg-primary-900/20 dark:text-primary-300'
                              : 'border-surface-200 text-surface-600 hover:border-surface-300 dark:border-surface-700 dark:text-surface-300',
                          )}
                        >
                          <span className={cn(
                            'flex h-4 w-4 flex-shrink-0 items-center justify-center rounded border',
                            checked ? 'border-primary-600 bg-primary-600 text-white' : 'border-surface-300 dark:border-surface-600',
                          )}>
                            {checked && <Check className="h-3 w-3" />}
                          </span>
                          {c}
                        </button>
                      );
                    })}
                  </div>
                  <div className="mt-2">
                    <input
                      value={device.custom_condition}
                      onChange={(e) => updateDevice(device._key, { custom_condition: e.target.value })}
                      className={inputCls}
                      placeholder="Other condition (custom)..."
                    />
                  </div>
                </div>

                {/* Issue / Notes */}
                <div className="mb-4">
                  <FormLabel label="Issue / Notes" />
                  <textarea
                    value={device.additional_notes}
                    onChange={(e) => updateDevice(device._key, { additional_notes: e.target.value })}
                    rows={2}
                    className={inputCls}
                    placeholder="Customer describes the problem..."
                  />
                </div>

                {/* Location + Warranty */}
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <FormLabel label="Device Location" />
                    <input value={device.device_location} onChange={(e) => updateDevice(device._key, { device_location: e.target.value })} className={inputCls} placeholder="e.g. Front counter, Shelf A" />
                  </div>
                  <div>
                    <FormLabel label="Warranty" />
                    <div className="flex items-center gap-3 pt-1">
                      <label className="flex cursor-pointer items-center gap-2">
                        <input
                          type="checkbox"
                          checked={device.warranty}
                          onChange={(e) => updateDevice(device._key, { warranty: e.target.checked })}
                          className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                        />
                        <span className="text-sm text-surface-700 dark:text-surface-300">Warranty repair</span>
                      </label>
                      {device.warranty && (
                        <input
                          type="number"
                          value={device.warranty_days}
                          onChange={(e) => updateDevice(device._key, { warranty_days: parseInt(e.target.value) || 0 })}
                          className={cn(inputCls, 'w-24')}
                          min={0}
                          placeholder="Days"
                        />
                      )}
                      {device.warranty && <span className="text-xs text-surface-400">days</span>}
                    </div>
                  </div>
                </div>
              </div>
            ))}

            <button
              onClick={() => setDevices((prev) => [...prev, makeDevice()])}
              className="inline-flex items-center gap-2 rounded-lg border-2 border-dashed border-surface-300 px-4 py-2.5 text-sm font-medium text-surface-600 transition-colors hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:text-surface-400 dark:hover:border-primary-500 dark:hover:text-primary-400"
            >
              <Plus className="h-4 w-4" />
              Add Another Device
            </button>
          </div>
        )}

        {/* ── Step 2: Parts, Pricing & Assignment ──────────────────── */}
        {step === 2 && (
          <div className="space-y-5">
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Parts, Pricing & Assignment</h2>

            {/* Per-device sections */}
            {devices.map((device, idx) => {
              const isExpanded = expandedDevices[device._key] ?? true;
              const DevIcon = DEVICE_ICON_MAP[device.device_type] || HelpCircle;
              return (
                <div key={device._key} className="rounded-lg border border-surface-200 dark:border-surface-700">
                  {/* Collapsible header */}
                  <button
                    onClick={() => setExpandedDevices((prev) => ({ ...prev, [device._key]: !isExpanded }))}
                    className="flex w-full items-center gap-3 p-4 text-left transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50"
                  >
                    <DevIcon className="h-5 w-5 text-surface-400" />
                    <span className="flex-1 text-sm font-medium text-surface-900 dark:text-surface-100">
                      {device.device_name || `Device ${idx + 1}`}
                    </span>
                    <ChevronDown className={cn('h-4 w-4 text-surface-400 transition-transform', isExpanded && 'rotate-180')} />
                  </button>

                  {isExpanded && (
                    <div className="border-t border-surface-200 p-4 dark:border-surface-700">
                      {/* Parts search */}
                      <div className="mb-4">
                        <div className="flex items-center gap-2">
                          <Package className="h-4 w-4 text-surface-400" />
                          <span className="text-sm font-medium text-surface-700 dark:text-surface-300">Parts</span>
                        </div>

                        {/* Added parts list */}
                        {device.parts.length > 0 && (
                          <div className="mt-2 space-y-2">
                            {device.parts.map((part) => (
                              <div key={part._key} className="flex items-center gap-3 rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 dark:border-surface-700 dark:bg-surface-800">
                                <div className="min-w-0 flex-1">
                                  <p className="truncate text-sm font-medium text-surface-800 dark:text-surface-200">{part.name}</p>
                                  {part.sku && <p className="font-mono text-xs text-surface-400">SKU: {part.sku}</p>}
                                </div>
                                {/* Qty controls */}
                                <div className="flex flex-shrink-0 items-center gap-1.5">
                                  <button
                                    onClick={() => updatePart(device._key, part._key, { quantity: Math.max(1, part.quantity - 1) })}
                                    className="flex h-6 w-6 items-center justify-center rounded-full bg-surface-200 transition-colors hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
                                  >
                                    <Minus className="h-3 w-3 text-surface-600 dark:text-surface-300" />
                                  </button>
                                  <span className="w-5 text-center text-sm font-semibold text-surface-800 dark:text-surface-200">{part.quantity}</span>
                                  <button
                                    onClick={() => updatePart(device._key, part._key, { quantity: part.quantity + 1 })}
                                    className="flex h-6 w-6 items-center justify-center rounded-full bg-surface-200 transition-colors hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
                                  >
                                    <Plus className="h-3 w-3 text-surface-600 dark:text-surface-300" />
                                  </button>
                                </div>
                                {/* Price input */}
                                <div className="relative w-24 flex-shrink-0">
                                  <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-xs font-medium text-surface-400">$</span>
                                  <input
                                    type="number"
                                    value={part.price}
                                    onChange={(e) => updatePart(device._key, part._key, { price: parseFloat(e.target.value) || 0 })}
                                    className={cn(inputCls, 'py-1.5 pl-6 pr-2 text-right text-sm font-medium [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none')}
                                    step="0.01"
                                  />
                                </div>
                                {/* Taxable toggle */}
                                <label className="flex flex-shrink-0 cursor-pointer items-center gap-1" title="Taxable">
                                  <input
                                    type="checkbox"
                                    checked={part.taxable}
                                    onChange={(e) => updatePart(device._key, part._key, { taxable: e.target.checked })}
                                    className="h-3.5 w-3.5 rounded border-surface-300 text-primary-600"
                                  />
                                  <span className="text-xs text-surface-400">Tax</span>
                                </label>
                                {/* Status badge */}
                                <span className={cn(
                                  'flex-shrink-0 rounded-full px-2 py-0.5 text-xs font-medium',
                                  part.status === 'available' && 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
                                  part.status === 'missing' && 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
                                  part.status === 'ordered' && 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
                                )}>
                                  {part.status}
                                </span>
                                {/* Remove */}
                                <button aria-label="Remove part" onClick={() => removePart(device._key, part._key)} className="flex-shrink-0 text-surface-400 transition-colors hover:text-red-500">
                                  <X className="h-4 w-4" />
                                </button>
                              </div>
                            ))}
                          </div>
                        )}

                        <InlinePartsSearch
                          deviceKey={device._key}
                          deviceModelId={device.device_model_id}
                          onAdd={(part) => addPartToDevice(device._key, part)}
                        />
                      </div>

                      {/* Service price + tax + discount */}
                      <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <div>
                          <FormLabel label="Service/Labor Price" />
                          <div className="relative">
                            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">$</span>
                            <input
                              type="number"
                              value={device.price || ''}
                              onChange={(e) => updateDevice(device._key, { price: parseFloat(e.target.value) || 0 })}
                              className={cn(inputCls, 'pl-7')}
                              placeholder="0.00"
                              step="0.01"
                            />
                          </div>
                        </div>
                        <div>
                          <FormLabel label="Line Discount" />
                          <div className="relative">
                            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">$</span>
                            <input
                              type="number"
                              value={device.line_discount || ''}
                              onChange={(e) => updateDevice(device._key, { line_discount: parseFloat(e.target.value) || 0 })}
                              className={cn(inputCls, 'pl-7')}
                              placeholder="0.00"
                              step="0.01"
                            />
                          </div>
                        </div>
                        <div>
                          <FormLabel label="Service Taxable" />
                          <label className="mt-1 flex cursor-pointer items-center gap-2">
                            <input
                              type="checkbox"
                              checked={device.taxable}
                              onChange={(e) => updateDevice(device._key, { taxable: e.target.checked })}
                              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                            />
                            <span className="text-sm text-surface-700 dark:text-surface-300">
                              Colorado {((defaultTaxClass?.rate ?? 8.865)).toFixed(3)}%
                            </span>
                          </label>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}

            {/* Ticket-level fields */}
            <div className="rounded-lg border border-surface-200 p-4 dark:border-surface-700">
              <h3 className="mb-4 text-sm font-semibold text-surface-700 dark:text-surface-300">Ticket Details</h3>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                <div>
                  <FormLabel label="Assigned To" />
                  <select value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)} className={inputCls}>
                    <option value="">Unassigned</option>
                    {users.map((u) => <option key={u.id} value={String(u.id)}>{u.first_name} {u.last_name}</option>)}
                  </select>
                </div>
                <div>
                  <FormLabel label="Labels" />
                  <input value={labels} onChange={(e) => setLabels(e.target.value)} className={inputCls} placeholder="urgent, vip (comma-separated)" />
                </div>
                <div>
                  <FormLabel label="Due Date" />
                  <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} className={inputCls} />
                </div>
                <div>
                  <FormLabel label="Additional Discount" />
                  <div className="relative">
                    <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">$</span>
                    <input
                      type="number"
                      value={ticketDiscount || ''}
                      onChange={(e) => setTicketDiscount(parseFloat(e.target.value) || 0)}
                      className={cn(inputCls, 'pl-7')}
                      placeholder="0.00"
                      step="0.01"
                    />
                  </div>
                  {memberDiscountApplied && selectedCustomer?.customer_group_name && (
                    <p className="mt-1.5 text-xs font-medium text-green-600 dark:text-green-400">
                      Member discount auto-applied: {selectedCustomer.group_discount_type === 'fixed'
                        ? `$${selectedCustomer.group_discount_pct}`
                        : `${selectedCustomer.group_discount_pct}%`} ({selectedCustomer.customer_group_name})
                    </p>
                  )}
                </div>
                <div className="sm:col-span-2">
                  <FormLabel label="Discount Reason" />
                  <input value={discountReason} onChange={(e) => setDiscountReason(e.target.value)} className={inputCls} placeholder="Reason for discount" />
                </div>
              </div>
              <div className="mt-4">
                <FormLabel label="Internal Notes" />
                <textarea
                  value={internalNotes}
                  onChange={(e) => setInternalNotes(e.target.value)}
                  rows={2}
                  className={inputCls}
                  placeholder="Staff notes (not visible to customer)..."
                />
              </div>
            </div>

            {/* Totals card */}
            <div className="flex justify-end">
              <div className="w-full max-w-xs space-y-2 rounded-lg bg-surface-50 p-4 dark:bg-surface-800">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-surface-500 dark:text-surface-400">Subtotal</span>
                  <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(totals.subtotal)}</span>
                </div>
                {totals.memberDiscount > 0 && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-green-600 dark:text-green-400">Member Discount</span>
                    <span className="font-medium text-green-600 dark:text-green-400">-{formatCurrency(totals.memberDiscount)}</span>
                  </div>
                )}
                {totals.manualDiscount > 0 && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-surface-500 dark:text-surface-400">Additional Discount</span>
                    <span className="font-medium text-red-600 dark:text-red-400">-{formatCurrency(totals.manualDiscount)}</span>
                  </div>
                )}
                <div className="flex items-center justify-between text-sm">
                  <span className="text-surface-500 dark:text-surface-400">Tax</span>
                  <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(totals.tax)}</span>
                </div>
                <div className="border-t border-surface-200 pt-2 dark:border-surface-700">
                  <div className="flex items-center justify-between">
                    <span className="font-semibold text-surface-900 dark:text-surface-100">Total</span>
                    <span className="text-lg font-bold text-surface-900 dark:text-surface-100">{formatCurrency(totals.total)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ── Step 3: Review ───────────────────────────────────────── */}
        {step === 3 && (
          <div className="space-y-5">
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Review & Confirm</h2>

            {/* Customer card */}
            {selectedCustomer && (
              <div className="flex items-center gap-3 rounded-lg bg-surface-50 p-4 dark:bg-surface-800">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-600 dark:bg-primary-900 dark:text-primary-400">
                  {initials(selectedCustomer.first_name, selectedCustomer.last_name)}
                </div>
                <div>
                  <p className="font-medium text-surface-900 dark:text-surface-100">{selectedCustomer.first_name} {selectedCustomer.last_name}</p>
                  <p className="text-sm text-surface-500 dark:text-surface-400">
                    {[selectedCustomer.phone || selectedCustomer.mobile, selectedCustomer.email].filter(Boolean).join(' · ')}
                  </p>
                </div>
                {source && <span className="ml-auto rounded-full bg-surface-200 px-2.5 py-0.5 text-xs font-medium text-surface-600 dark:bg-surface-700 dark:text-surface-300">{source}</span>}
              </div>
            )}

            {/* Devices */}
            {devices.filter((d) => d.device_name.trim()).map((device, idx) => {
              const DevIcon = DEVICE_ICON_MAP[device.device_type] || HelpCircle;
              const allConditions = [...device.pre_conditions, ...(device.custom_condition.trim() ? [device.custom_condition.trim()] : [])];
              return (
                <div key={device._key} className="rounded-lg border border-surface-200 p-4 dark:border-surface-700">
                  <div className="mb-3 flex items-center gap-2">
                    <DevIcon className="h-5 w-5 text-surface-400" />
                    <span className="font-medium text-surface-900 dark:text-surface-100">{device.device_name}</span>
                    <a href={getIFixitUrl(device.device_name)} target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-xs text-blue-500 hover:text-blue-600 hover:underline"
                      title="iFixit Repair Guide">
                      <ExternalLink className="h-3 w-3" /> iFixit
                    </a>
                    <span className="ml-auto text-sm font-medium text-surface-700 dark:text-surface-300">{formatCurrency(device.price - device.line_discount)}</span>
                  </div>

                  {/* Repair service badge */}
                  {device.repair_service_name && (
                    <div className="mb-2 flex items-center gap-2">
                      <Wrench className="h-3.5 w-3.5 text-primary-500" />
                      <span className="text-sm font-medium text-primary-600 dark:text-primary-400">{device.repair_service_name}</span>
                    </div>
                  )}

                  {/* Details grid */}
                  <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
                    {device.imei && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">IMEI:</span> <span className="font-mono">{device.imei}</span></p>}
                    {device.serial && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Serial:</span> <span className="font-mono">{device.serial}</span></p>}
                    {device.security_code && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Passcode:</span> <span className="font-mono">{device.security_code}</span></p>}
                    {device.color && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Color:</span> {device.color}</p>}
                    {device.network && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Network:</span> {device.network}</p>}
                    {device.device_location && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Location:</span> {device.device_location}</p>}
                    {device.warranty && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Warranty:</span> {device.warranty_days} days</p>}
                  </div>

                  {/* Pre-conditions */}
                  {allConditions.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1">
                      {allConditions.map((c) => (
                        <span key={c} className="rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-700 dark:bg-amber-900/20 dark:text-amber-400">{c}</span>
                      ))}
                    </div>
                  )}

                  {device.additional_notes && (
                    <p className="mt-2 text-sm text-surface-500 dark:text-surface-400 italic">{device.additional_notes}</p>
                  )}

                  {/* Parts table */}
                  {device.parts.length > 0 && (
                    <div className="mt-3">
                      <p className="mb-1 text-xs font-semibold uppercase text-surface-400">Parts ({device.parts.length})</p>
                      <div className="divide-y divide-surface-100 dark:divide-surface-700">
                        {device.parts.map((p) => (
                          <div key={p._key} className="flex items-center justify-between py-1.5 text-sm">
                            <span className="text-surface-700 dark:text-surface-300">{p.name} <span className="text-surface-400">x{p.quantity}</span></span>
                            <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(p.price * p.quantity)}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}

            {/* Assignment / labels / notes summary */}
            <div className="rounded-lg bg-surface-50 p-4 dark:bg-surface-800">
              <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
                {assignedTo && (
                  <p className="text-surface-500">
                    <span className="font-medium text-surface-700 dark:text-surface-300">Assigned:</span>{' '}
                    {users.find((u) => String(u.id) === assignedTo)?.first_name ?? 'Unknown'} {users.find((u) => String(u.id) === assignedTo)?.last_name ?? ''}
                  </p>
                )}
                {labels && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Labels:</span> {labels}</p>}
                {dueDate && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Due:</span> {dueDate}</p>}
                {referredBy && <p className="text-surface-500"><span className="font-medium text-surface-700 dark:text-surface-300">Referred by:</span> {referredBy}</p>}
              </div>
              {internalNotes && <p className="mt-2 text-sm italic text-surface-400">{internalNotes}</p>}
            </div>

            {/* Totals */}
            <div className="flex justify-end">
              <div className="w-full max-w-xs space-y-2 rounded-lg border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-surface-500">Subtotal</span>
                  <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(totals.subtotal)}</span>
                </div>
                {totals.discount > 0 && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-surface-500">Discount</span>
                    <span className="font-medium text-red-600">-{formatCurrency(totals.discount)}</span>
                  </div>
                )}
                <div className="flex items-center justify-between text-sm">
                  <span className="text-surface-500">Tax</span>
                  <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(totals.tax)}</span>
                </div>
                <div className="border-t border-surface-200 pt-2 dark:border-surface-700">
                  <div className="flex items-center justify-between">
                    <span className="font-semibold text-surface-900 dark:text-surface-100">Total</span>
                    <span className="text-lg font-bold text-surface-900 dark:text-surface-100">{formatCurrency(totals.total)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ── Navigation ───────────────────────────────────────────── */}
        <div className="mt-6 flex items-center justify-between border-t border-surface-200 pt-6 dark:border-surface-700">
          {step > 0 ? (
            <button
              onClick={goBack}
              className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              <ChevronLeft className="h-4 w-4" /> Back
            </button>
          ) : (
            <div />
          )}

          {step < 3 ? (
            <button
              onClick={goNext}
              disabled={createCustomerMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
            >
              {createCustomerMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Continue <ChevronRight className="h-4 w-4" />
            </button>
          ) : (
            <button
              onClick={handleSubmit}
              disabled={createTicketMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-2.5 text-sm font-bold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
            >
              {createTicketMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
              Create Ticket
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Success Screen ─────────────────────────────────────────────────

function SuccessScreen({
  ticket,
  customer,
  devices,
  onNewCheckIn,
  isKiosk,
}: {
  ticket: any;
  customer: CustomerResult | null;
  devices: DeviceForm[];
  onNewCheckIn: () => void;
  isKiosk: boolean;
}) {
  const navigate = useNavigate();
  const { data: infoData } = useQuery({
    queryKey: ['server-info'],
    queryFn: serverInfoApi.get,
    staleTime: 60000,
  });
  const serverUrl = infoData?.data?.data?.server_url || window.location.origin;
  const authToken = typeof window !== 'undefined' ? localStorage.getItem('accessToken') : '';

  return (
    <div className="mx-auto max-w-lg space-y-4 px-4 py-4">
      {/* Ticket banner */}
      <div className="flex items-center gap-3 rounded-xl border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20">
        <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/40">
          <CheckCircle2 className="h-5 w-5 text-green-600 dark:text-green-400" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="font-bold text-green-800 dark:text-green-200">
            Ticket Created Successfully
          </p>
          <p className="text-sm text-green-600 dark:text-green-400">
            <span className="font-mono font-semibold">{ticket.order_id || `T-${String(ticket.id).padStart(4, '0')}`}</span>
            {customer && ` · ${customer.first_name} ${customer.last_name}`}
          </p>
        </div>
      </div>

      {/* Photo capture cards — one per device */}
      {(ticket.devices || []).map((ticketDevice: any, idx: number) => {
        const photoUrl = `${serverUrl}/photo-capture/${ticket.id}/${ticketDevice.id}?t=${authToken || ''}`;
        const deviceName = ticketDevice.device_name || devices[idx]?.device_name || `Device ${idx + 1}`;
        return (
          <div key={ticketDevice.id} className="card overflow-hidden border-2 border-amber-400 dark:border-amber-600">
            <div className="flex items-center gap-2 bg-amber-400 px-4 py-3 dark:bg-amber-600">
              <Camera className="h-5 w-5 flex-shrink-0 text-amber-900 dark:text-white" />
              <div className="flex-1">
                <p className="text-sm font-bold text-amber-900 dark:text-white">Take Photos: {deviceName}</p>
                <p className="text-xs text-amber-800 dark:text-amber-100">Document device before repair</p>
              </div>
            </div>
            <div className="flex items-start gap-4 p-4">
              <div className="flex-shrink-0">
                <div className="inline-block rounded-xl bg-white p-2 shadow-sm">
                  <QRCodeSVG value={photoUrl} size={140} level="M" includeMargin={false} />
                </div>
              </div>
              <div className="flex-1 space-y-2">
                <div className="flex items-start gap-2">
                  <span className="flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-amber-100 text-xs font-bold text-amber-800 dark:bg-amber-900/30 dark:text-amber-300">1</span>
                  <p className="text-sm text-surface-700 dark:text-surface-300">Scan QR code with shop phone/tablet</p>
                </div>
                <div className="flex items-start gap-2">
                  <span className="flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-amber-100 text-xs font-bold text-amber-800 dark:bg-amber-900/30 dark:text-amber-300">2</span>
                  <p className="text-sm text-surface-700 dark:text-surface-300">Take photos of all sides and damage</p>
                </div>
                <div className="flex items-start gap-2">
                  <span className="flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-amber-100 text-xs font-bold text-amber-800 dark:bg-amber-900/30 dark:text-amber-300">3</span>
                  <p className="text-sm text-surface-700 dark:text-surface-300">Upload automatically</p>
                </div>
              </div>
            </div>
          </div>
        );
      })}

      {/* Action buttons */}
      <div className="card p-4">
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => navigate(`/print/ticket/${ticket.id}?size=receipt80`)}
            className="inline-flex items-center gap-2 rounded-xl border border-surface-200 px-4 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Printer className="h-4 w-4" /> Print Receipt
          </button>
          <button
            onClick={() => navigate(`/print/ticket/${ticket.id}?size=label`)}
            className="inline-flex items-center gap-2 rounded-xl border border-surface-200 px-4 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Tag className="h-4 w-4" /> Print Label
          </button>
          <button
            onClick={() => navigate(`/tickets/${ticket.id}`)}
            className="inline-flex items-center gap-2 rounded-xl border border-surface-200 px-4 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            View Ticket
          </button>
          <button
            onClick={onNewCheckIn}
            className="ml-auto inline-flex items-center gap-2 rounded-xl bg-primary-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-700"
          >
            New Check-In
          </button>
        </div>
      </div>
    </div>
  );
}
