import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import type { CartItem, RepairCartItem, ProductCartItem, MiscCartItem, CustomerResult, RepairDrillState, TicketMeta } from './types';
import { useAuthStore } from '@/stores/authStore';

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
  showSuccess: any;
  setShowSuccess: (data: any) => void;

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
