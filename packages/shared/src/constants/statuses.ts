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
  { name: 'Intake received', color: '#3b82f6', sort_order: 0, is_default: true, is_closed: false, is_cancelled: false, notify_customer: true },
  // Parts need to be sourced — let the customer know about the delay.
  { name: 'Parts quote needed', color: '#ef4444', sort_order: 1, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Parts arrived, queued for repair — customer update.
  { name: 'Parts received - bench queue', color: '#3b82f6', sort_order: 2, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Internal — tech is investigating, no need to ping the customer yet.
  { name: 'Diagnostic underway', color: '#3b82f6', sort_order: 3, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // Actively being worked on — customer wants to know work has started.
  { name: 'Bench work active', color: '#3b82f6', sort_order: 4, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Internal — diagnosis finished, about to move into repair or quote.
  { name: 'Diagnostic ready', color: '#3b82f6', sort_order: 5, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // Internal QC states — don't notify until QC actually passes.
  { name: 'Repair complete - final check', color: '#3b82f6', sort_order: 6, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  { name: 'Final check passed', color: '#3b82f6', sort_order: 7, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Final check needs review', color: '#3b82f6', sort_order: 8, is_default: false, is_closed: false, is_cancelled: false, notify_customer: false },
  // ─── On Hold (orange/amber) ──────────────────────────────────
  // Parts waiting, need the device back.
  { name: 'Parts ready - device needed', color: '#f97316', sort_order: 9, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Loaner/asset workflow — customer needs to return the device.
  { name: 'Awaiting related device', color: '#f97316', sort_order: 10, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Shipment in-transit — customer tracking update.
  { name: 'In transit', color: '#f97316', sort_order: 11, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Needs approval from customer — must ping them.
  { name: 'Estimate approval needed', color: '#f97316', sort_order: 12, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Customer response needed', color: '#f97316', sort_order: 13, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Customer approval pending', color: '#f97316', sort_order: 14, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  { name: 'Parts on order', color: '#f97316', sort_order: 15, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // Repair complete, awaiting payment — the classic "come pick it up" message.
  { name: 'Complete - balance due', color: '#f97316', sort_order: 16, is_default: false, is_closed: false, is_cancelled: false, notify_customer: true },
  // ─── Closed (green) ──────────────────────────────────────────
  // Ready/completed states — always ping the customer.
  { name: 'Ready after repair', color: '#22c55e', sort_order: 17, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Paid - ready to ship', color: '#22c55e', sort_order: 18, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Shipped', color: '#22c55e', sort_order: 19, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  // Hand-off finished — thank-you / review request.
  { name: 'Repaired and collected', color: '#22c55e', sort_order: 20, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  { name: 'Paid and picked up', color: '#22c55e', sort_order: 21, is_default: false, is_closed: true, is_cancelled: false, notify_customer: true },
  // ─── Cancelled (red) ─────────────────────────────────────────
  // Stopped/not-economical/disposal states — customer needs to know the job stopped.
  { name: 'Job cancelled', color: '#ef4444', sort_order: 22, is_default: false, is_closed: false, is_cancelled: true, notify_customer: true },
  { name: 'Not economical to repair', color: '#ef4444', sort_order: 23, is_default: false, is_closed: false, is_cancelled: true, notify_customer: true },
  // Internal — device is gone, nothing to tell the customer that was not already sent at stop decision.
  { name: 'Disposal completed', color: '#ef4444', sort_order: 24, is_default: false, is_closed: false, is_cancelled: true, notify_customer: false },
] as const;

export const LEAD_STATUSES = ['new', 'contacted', 'scheduled', 'converted', 'lost'] as const;
export const INVOICE_STATUSES = ['unpaid', 'partial', 'paid', 'refunded', 'void'] as const;
export const ESTIMATE_STATUSES = ['draft', 'sent', 'approved', 'rejected', 'converted'] as const;
export const PO_STATUSES = ['draft', 'sent', 'partial', 'received', 'cancelled'] as const;
export const SERVICE_TYPES = ['mail_in', 'walk_in', 'on_site', 'pick_up', 'drop_off'] as const;
