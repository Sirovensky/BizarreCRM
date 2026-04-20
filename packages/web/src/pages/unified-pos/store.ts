import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import type { CartItem, RepairCartItem, ProductCartItem, MiscCartItem, CustomerResult, RepairDrillState, TicketMeta } from './types';
import { useAuthStore } from '@/stores/authStore';

// Discriminated union for the POS checkout success payload.
// Server route: POST /pos/checkout-with-ticket
// The client merges the server data with a `mode` field before storing.
interface CheckoutTicketRef {
  id: number;
  order_id: string;
  c_first_name?: string | null;
  c_last_name?: string | null;
  customer?: { first_name: string; last_name: string; phone?: string | null; email?: string | null } | null;
  devices?: Array<{ id: number; device_name: string; device_type?: string; service_name?: string }>;
}
interface CheckoutInvoiceRef {
  id: number;
  order_id: string;
  total?: number;
  first_name?: string | null;
  last_name?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
}
/** Common optional fallback fields the SuccessScreen reads for legacy compatibility */
interface CheckoutSuccessExtras {
  // Legacy flat fields that may appear on older server responses or
  // are spread from the server data object in callers.
  ticket_id?: number | null;
  order_id?: string | null;
  invoice_id?: number | null;
  total?: number;
  change?: number;
  customer_name?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
  devices?: Array<{ id: number; device_name: string; device_type?: string; service_name?: string }>;
  store_credit_issued?: number;
  checkin_default_category?: string | null;
  auto_print_label?: boolean;
}

export type CheckoutSuccessPayload = CheckoutSuccessExtras & (
  | {
      mode: 'checkout';
      ticket: CheckoutTicketRef | null;
      invoice: CheckoutInvoiceRef;
    }
  | {
      mode: 'create_ticket';
      ticket: CheckoutTicketRef;
      invoice?: CheckoutInvoiceRef | null;
    }
);

/** Returns a user-scoped localStorage key so each user gets their own POS state */
function getUserPosKey(): string {
  const user = useAuthStore.getState().user;
  const userId = user?.id ?? 'anon';
  return `pos-store-u${userId}`;
}

interface UnifiedPosState {
  // Customer
  customer: CustomerResult | null;
  setCustomer: (c: CustomerResult | null) => void;

  // Cart
  cartItems: CartItem[];
  addRepair: (item: RepairCartItem) => void;
  addProduct: (item: ProductCartItem) => void;
  addMisc: (item: MiscCartItem) => void;
  updateCartItem: (id: string, updates: Partial<CartItem>) => void;
  updateProductQty: (id: string, delta: number) => void;
  removeCartItem: (id: string) => void;
  clearCart: () => void;

  // Repair drill-down
  drillState: RepairDrillState;
  setDrillState: (state: RepairDrillState) => void;
  resetDrill: () => void;

  // Discount
  discount: number;
  discountReason: string;
  setDiscount: (amount: number, reason: string) => void;
  memberDiscountApplied: boolean;
  setMemberDiscountApplied: (applied: boolean) => void;

  // Ticket metadata
  meta: TicketMeta;
  setMeta: (updates: Partial<TicketMeta>) => void;

  // Source ticket (when checking out an existing ticket)
  sourceTicketId: number | null;
  setSourceTicketId: (id: number | null) => void;

  // UI
  activeTab: 'repairs' | 'products' | 'misc';
  setActiveTab: (tab: 'repairs' | 'products' | 'misc') => void;
  showCheckout: boolean;
  setShowCheckout: (show: boolean) => void;
  showSuccess: CheckoutSuccessPayload | null;
  setShowSuccess: (data: CheckoutSuccessPayload | null) => void;

  // Reset everything
  resetAll: () => void;
}

const DEFAULT_META: TicketMeta = {
  assignedTo: null,
  dueDate: '',
  source: 'Walk-in',
  internalNotes: '',
  labels: '',
  discountReason: '',
};

export const useUnifiedPosStore = create<UnifiedPosState>()(persist((set) => ({
  customer: null,
  setCustomer: (customer) => set({ customer }),

  cartItems: [],
  addRepair: (item) => set((s) => ({ cartItems: [...s.cartItems, item] })),
  addProduct: (item) => set((s) => {
    // If same inventory item already in cart, increment quantity
    const existing = s.cartItems.find(
      (c) => c.type === 'product' && (c as ProductCartItem).inventoryItemId === item.inventoryItemId
    );
    if (existing) {
      return {
        cartItems: s.cartItems.map((c) =>
          c.id === existing.id && c.type === 'product'
            ? { ...c, quantity: (c as ProductCartItem).quantity + 1 } as ProductCartItem
            : c
        ),
      };
    }
    return { cartItems: [...s.cartItems, item] };
  }),
  addMisc: (item) => set((s) => ({ cartItems: [...s.cartItems, item] })),
  updateCartItem: (id, updates) => set((s) => ({
    cartItems: s.cartItems.map((c) => (c.id === id ? { ...c, ...updates } as CartItem : c)),
  })),
  updateProductQty: (id, delta) => set((s) => ({
    cartItems: s.cartItems
      .map((c) => {
        if (c.id !== id || c.type !== 'product') return c;
        const newQty = (c as ProductCartItem).quantity + delta;
        return newQty <= 0 ? null : { ...c, quantity: newQty } as ProductCartItem;
      })
      .filter(Boolean) as CartItem[],
  })),
  removeCartItem: (id) => set((s) => ({ cartItems: s.cartItems.filter((c) => c.id !== id) })),
  clearCart: () => set({ cartItems: [] }),

  drillState: { step: 'CATEGORY' },
  setDrillState: (drillState) => set({ drillState }),
  resetDrill: () => set({ drillState: { step: 'CATEGORY' } }),

  discount: 0,
  discountReason: '',
  setDiscount: (discount, discountReason) => set({ discount, discountReason }),
  memberDiscountApplied: false,
  setMemberDiscountApplied: (memberDiscountApplied) => set({ memberDiscountApplied }),

  meta: { ...DEFAULT_META },
  setMeta: (updates) => set((s) => ({ meta: { ...s.meta, ...updates } })),

  sourceTicketId: null,
  setSourceTicketId: (sourceTicketId) => set({ sourceTicketId }),

  activeTab: 'repairs',
  setActiveTab: (activeTab) => set({ activeTab }),
  showCheckout: false,
  setShowCheckout: (showCheckout) => set({ showCheckout }),
  showSuccess: null,
  setShowSuccess: (showSuccess) => set({ showSuccess }),

  resetAll: () => set({
    customer: null,
    cartItems: [],
    drillState: { step: 'CATEGORY' },
    discount: 0,
    discountReason: '',
    memberDiscountApplied: false,
    meta: { ...DEFAULT_META },
    sourceTicketId: null,
    activeTab: 'repairs',
    showCheckout: false,
    showSuccess: null,
  }),
}), {
  name: 'pos-store', // base name (actual key is user-scoped)
  storage: createJSONStorage(() => ({
    getItem: (name: string) => {
      const key = getUserPosKey();
      return localStorage.getItem(key);
    },
    setItem: (name: string, value: string) => {
      const key = getUserPosKey();
      localStorage.setItem(key, value);
    },
    removeItem: (name: string) => {
      const key = getUserPosKey();
      localStorage.removeItem(key);
    },
  })),
  // Only persist essential data, not transient UI state
  partialize: (state) => ({
    customer: state.customer,
    cartItems: state.cartItems,
    drillState: state.drillState,
    discount: state.discount,
    discountReason: state.discountReason,
    meta: state.meta,
    sourceTicketId: state.sourceTicketId,
    activeTab: state.activeTab,
  }),
}));
