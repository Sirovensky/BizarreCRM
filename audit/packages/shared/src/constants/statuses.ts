/**
 * Default ticket statuses seeded on fresh DB provisioning.
 *
 * `notify_customer` — when true, a status change TO this status will trigger
 * an automatic SMS (and/or email) to the customer via
 * `services/notifications.ts#sendTicketStatusNotification`. Customer-facing
 * statuses ("waiting", "ready", "repaired", "picked up") default to true so
 * SMS flows out of the box. Internal workshop statuses ("diagnosis in
 * progress", "QC") stay false so we don't spam the customer while the tech
 * is still heads-down on the device.
 *
 * Shops can flip these per-status at any time in Settings → Statuses, and
 * the first-run setup wizard surfaces them via `StepDefaultStatuses` so the
 * owner makes an explicit decision before the first ticket is created.
 */
export const DEFAULT_TICKET_STATUSES = [
  // ─── Open (blue) ─────────────────────────────────────────────
  // First customer touch-point — confirm the device arrived.
  { name: 'Waiting for inspection', color: '#3b82f6', sort_order: 0, is_default: true, is_closed: false, is_cancelled: false, notify_customer: true },
  // Parts need to be sourced — let the customer know about the delay.
  { name: 'Need to Order Parts', color: '#ef4444', sort_order: 1, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Parts arrived, queued for repair — customer update (legacy name contains "SMS").
  { name: 'Part received, in queue to fix - SMS', color: '#3b82f6', sort_order: 2, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Internal — tech is investigating, no need to ping the customer yet.
  { name: 'Diagnosis - In progress', color: '#3b82f6', sort_order: 3, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // Actively being worked on — customer wants to know work has started.
  { name: 'In Progress', color: '#3b82f6', sort_order: 4, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Internal — diagnosis finished, about to move into repair or quote.
  { name: 'Diagnosis completed', color: '#3b82f6', sort_order: 5, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // Internal QC states — don't notify until QC actually passes.
  { name: 'Repaired - Pending QC', color: '#3b82f6', sort_order: 6, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  { name: 'Repaired - QC Passed', color: '#3b82f6', sort_order: 7, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Repaired - QC Failed', color: '#3b82f6', sort_order: 8, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // ─── On Hold (orange/amber) ──────────────────────────────────
  // Parts waiting, need the device back — legacy "SMS" naming preserved.
  { name: 'Parts arrived, need the device - SMS', color: '#f97316', sort_order: 9, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Loaner/asset workflow — customer needs to return the device.
  { name: 'Waiting for asset', color: '#f97316', sort_order: 10, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Shipment in-transit — customer tracking update.
  { name: 'In-transit', color: '#f97316', sort_order: 11, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Needs approval from customer — must ping them.
  { name: 'Approval required', color: '#f97316', sort_order: 12, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Waiting on customer', color: '#f97316', sort_order: 13, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Pending for customer approval', color: '#f97316', sort_order: 14, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Waiting for Parts', color: '#f97316', sort_order: 15, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Repair complete, awaiting payment — the classic "come pick it up" message.
  { name: 'Repaired - Waiting for payment', color: '#f97316', sort_order: 16, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // ─── Closed (green) ──────────────────────────────────────────
  // Ready/completed states — always ping the customer.
  { name: 'Repaired', color: '#22c55e', sort_order: 17, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Payment Collected - Ready for shipment', color: '#22c55e', sort_order: 18, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Device shipped', color: '#22c55e', sort_order: 19, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  // Hand-off finished — thank-you / review request.
  { name: 'Repaired & Collected', color: '#22c55e', sort_order: 20, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Payment Received & Picked Up', color: '#22c55e', sort_order: 21, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  // ─── Cancelled (red) ─────────────────────────────────────────
  // Cancel/BER/disposed — customer needs to know the job stopped.
  { name: 'Cancelled', color: '#ef4444', sort_order: 22, is_default: false, is_closed: false, is_cancelled: true, notify_customer: true },
  { name: 'BER (Beyond Economical Repair)', color: '#ef4444', sort_order: 23, is_default: false, is_closed: false, is_cancelled: true, notify_customer: true },
  // Internal — device is gone, nothing to tell the customer that wasn't already sent at BER.
  { name: 'Disposed', color: '#ef4444', sort_order: 24, is_default: false, is_closed: false, is_cancelled: true, notify_customer: false },
] as const;

export const LEAD_STATUSES = ['new', 'contacted', 'scheduled', 'converted', 'lost'] as const;
export const INVOICE_STATUSES = ['unpaid', 'partial', 'paid', 'refunded', 'void'] as const;
export const ESTIMATE_STATUSES = ['draft', 'sent', 'approved', 'rejected', 'converted'] as const;
export const PO_STATUSES = ['draft', 'sent', 'partial', 'received', 'cancelled'] as const;
export const SERVICE_TYPES = ['mail_in', 'walk_in', 'on_site', 'pick_up', 'drop_off'] as const;
