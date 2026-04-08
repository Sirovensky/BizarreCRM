export const DEFAULT_TICKET_STATUSES = [
  // ─── Open (blue) ─────────────────────────────────────────────
  { name: 'Waiting for inspection', color: '#3b82f6', sort_order: 0, is_default: true, is_closed: false, is_cancelled: false },
  { name: 'Need to Order Parts', color: '#ef4444', sort_order: 1, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Part received, in queue to fix - SMS', color: '#3b82f6', sort_order: 2, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Diagnosis - In progress', color: '#3b82f6', sort_order: 3, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'In Progress', color: '#3b82f6', sort_order: 4, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Diagnosis completed', color: '#3b82f6', sort_order: 5, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Repaired - Pending QC', color: '#3b82f6', sort_order: 6, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Repaired - QC Passed', color: '#3b82f6', sort_order: 7, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Repaired - QC Failed', color: '#3b82f6', sort_order: 8, is_default: false, is_closed: false, is_cancelled: false },
  // ─── On Hold (orange/amber) ──────────────────────────────────
  { name: 'Parts arrived, need the device - SMS', color: '#f97316', sort_order: 9, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Waiting for asset', color: '#f97316', sort_order: 10, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'In-transit', color: '#f97316', sort_order: 11, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Approval required', color: '#f97316', sort_order: 12, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Waiting on customer', color: '#f97316', sort_order: 13, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Pending for customer approval', color: '#f97316', sort_order: 14, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Waiting for Parts', color: '#f97316', sort_order: 15, is_default: false, is_closed: false, is_cancelled: false },
  { name: 'Repaired - Waiting for payment', color: '#f97316', sort_order: 16, is_default: false, is_closed: false, is_cancelled: false },
  // ─── Closed (green) ──────────────────────────────────────────
  { name: 'Repaired', color: '#22c55e', sort_order: 17, is_default: false, is_closed: true, is_cancelled: false },
  { name: 'Payment Collected - Ready for shipment', color: '#22c55e', sort_order: 18, is_default: false, is_closed: true, is_cancelled: false },
  { name: 'Device shipped', color: '#22c55e', sort_order: 19, is_default: false, is_closed: true, is_cancelled: false },
  { name: 'Repaired & Collected', color: '#22c55e', sort_order: 20, is_default: false, is_closed: true, is_cancelled: false },
  { name: 'Payment Received & Picked Up', color: '#22c55e', sort_order: 21, is_default: false, is_closed: true, is_cancelled: false },
  // ─── Cancelled (red) ─────────────────────────────────────────
  { name: 'Cancelled', color: '#ef4444', sort_order: 22, is_default: false, is_closed: false, is_cancelled: true },
  { name: 'BER (Beyond Economical Repair)', color: '#ef4444', sort_order: 23, is_default: false, is_closed: false, is_cancelled: true },
  { name: 'Disposed', color: '#ef4444', sort_order: 24, is_default: false, is_closed: false, is_cancelled: true },
] as const;

export const LEAD_STATUSES = ['new', 'contacted', 'scheduled', 'converted', 'lost'] as const;
export const INVOICE_STATUSES = ['unpaid', 'partial', 'paid', 'refunded', 'void'] as const;
export const ESTIMATE_STATUSES = ['draft', 'sent', 'approved', 'rejected', 'converted'] as const;
export const PO_STATUSES = ['draft', 'sent', 'partial', 'received', 'cancelled'] as const;
export const SERVICE_TYPES = ['mail_in', 'walk_in', 'on_site', 'pick_up', 'drop_off'] as const;
