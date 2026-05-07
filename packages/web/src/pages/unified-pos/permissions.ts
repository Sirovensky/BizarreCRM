import { useMemo } from 'react';
import { useAuthStore } from '@/stores/authStore';

const MANAGER_ROLES = new Set(['admin', 'manager', 'owner']);

function hasExplicitGrant(permissions: Record<string, boolean> | null | undefined, key: string): boolean {
  return permissions?.[key] === true;
}

export function useUnifiedPosActionVisibility() {
  const user = useAuthStore((s) => s.user);
  const role = user?.role ?? '';
  const permissions = user?.permissions;

  return useMemo(() => {
    const isManagerRole = MANAGER_ROLES.has(role);
    const canEditInvoice = isManagerRole || hasExplicitGrant(permissions, 'invoices.edit');
    const canVoidInvoice = isManagerRole || hasExplicitGrant(permissions, 'invoices.void');
    const canRefund = isManagerRole || hasExplicitGrant(permissions, 'refunds.create');
    const canCreditNote = isManagerRole || hasExplicitGrant(permissions, 'invoices.credit_note');

    return {
      canEditCartPricing: canEditInvoice,
      canAdjustLineTax: canEditInvoice,
      canVoidCartLine: canVoidInvoice,
      canCloseDrawerShift: isManagerRole,
      canRefundOrVoidInvoice: canVoidInvoice || canRefund || canCreditNote,
    };
  }, [permissions, role]);
}
