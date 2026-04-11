/**
 * settingsMetadata.ts — Single source of truth for all settings definitions.
 *
 * Section 50 of the pre-launch critical audit noted that CLAUDE.md explicitly
 * says "65 of 70 settings toggles do nothing — massive trust problem". This
 * file is the fix: every setting toggle/field is listed here with an honest
 * `status` flag of 'live' (backend enforces it), 'beta' (partial), or
 * 'coming_soon' (UI-only, backend does NOT enforce, user should see a visible
 * "Coming Soon" badge instead of silent lies).
 *
 * Tooltips, default values, validation bounds, and required roles are also
 * centralized here so SettingsSearch, ResetDefaultsButton, and the coming-soon
 * badges can all read from one place.
 *
 * When you wire a new setting up on the backend, flip its `status` to 'live'
 * and the badge disappears automatically. When you add a new UI toggle, add
 * it here and mark it 'coming_soon' until the backend work ships. That way
 * we never accidentally lie to the user again.
 */

export type SettingStatus = 'live' | 'beta' | 'coming_soon';

export type SettingType =
  | 'string'
  | 'number'
  | 'boolean'
  | 'select'
  | 'color'
  | 'textarea';

export interface SettingDef {
  /** store_config key, or logical identifier for non-key-value settings */
  key: string;
  /** Human-readable label shown in the UI */
  label: string;
  /** Tab this setting belongs to (matches SettingsPage Tab type) */
  tab: string;
  /** Honest status — 'coming_soon' means the backend does NOT enforce this */
  status: SettingStatus;
  /** Tooltip explaining what the setting does and who should enable it */
  tooltip: string;
  /** Default value used by "Reset to defaults" button */
  default: unknown;
  /** Data type — drives inline validation and the reset flow */
  type: SettingType;
  /** Minimum value (numeric settings) */
  min?: number;
  /** Maximum value (numeric settings) */
  max?: number;
  /** Options for select-type settings */
  options?: { label: string; value: string }[];
  /** Minimum role required to modify this setting */
  requiresRole?: 'admin' | 'manager';
  /** Free-form search keywords to help SettingsSearch find this */
  keywords?: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// STORE INFO (all backend-enforced — these are the most critical settings)
// ─────────────────────────────────────────────────────────────────────────────

const STORE_SETTINGS: SettingDef[] = [
  {
    key: 'store_name',
    label: 'Store Name',
    tab: 'store',
    status: 'live',
    tooltip: 'The name of your shop as it appears on invoices, receipts, the customer portal, and SMS sender name. Required for receipt printing.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
    keywords: ['business', 'company', 'shop'],
  },
  {
    key: 'address',
    label: 'Store Address',
    tab: 'store',
    status: 'live',
    tooltip: 'Physical address shown on receipts and invoices. Used by customers to locate your shop.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'phone',
    label: 'Store Phone',
    tab: 'store',
    status: 'live',
    tooltip: 'Main phone number for your shop. Shown on receipts and included in customer notifications.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'email',
    label: 'Store Email',
    tab: 'store',
    status: 'live',
    tooltip: 'Main contact email. Used as the reply-to address on outbound customer emails.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'timezone',
    label: 'Timezone',
    tab: 'store',
    status: 'live',
    tooltip: 'Timezone used for all dates shown in the CRM. Affects ticket due dates, business hours, and reports.',
    default: 'America/Denver',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'currency',
    label: 'Currency',
    tab: 'store',
    status: 'live',
    tooltip: 'Currency for all prices, invoices, and reports. Changing this does not convert existing values.',
    default: 'USD',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'business_hours',
    label: 'Business Hours',
    tab: 'store',
    status: 'live',
    tooltip: 'Weekly operating hours shown on the portal. Used by the off-hours auto-reply to know when to send fallback messages.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'store_logo',
    label: 'Store Logo',
    tab: 'store',
    status: 'live',
    tooltip: 'Logo displayed on invoices, receipts, and the customer portal. JPEG/PNG/WebP/GIF, max 5MB.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// TICKETS & REPAIRS — Most ARE backend-enforced, but a handful are UI-only
// ─────────────────────────────────────────────────────────────────────────────

const TICKET_SETTINGS: SettingDef[] = [
  {
    key: 'ticket_show_inventory',
    label: 'Display inventory section',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, hides the parts-picker on the ticket detail page. Blocks adding inventory parts to any ticket.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'ticket_show_closed',
    label: 'Display closed/cancelled tickets',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, closed and cancelled tickets are hidden from the main listing. Use filters to find them.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'ticket_show_empty',
    label: 'Display empty tickets',
    tab: 'tickets-repairs',
    status: 'coming_soon',
    tooltip: 'Planned: hide tickets with no line items or notes from the main listing. Backend filter not yet implemented.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'ticket_show_parts_column',
    label: 'Display parts column',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Shows the parts column on the ticket listing. Useful for parts-ordering workflows.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_allow_edit_closed',
    label: 'Allow editing closed tickets',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, closed tickets are locked. Admins can always edit. Recommended off for audit trail.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_allow_delete_after_invoice',
    label: 'Allow ticket deletion after invoice',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, tickets with an invoice cannot be deleted. Strongly recommended off for accounting integrity.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_allow_edit_after_invoice',
    label: 'Allow ticket editing after invoice',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, tickets with an invoice are read-only. Turn on only if you need to edit ticket notes after billing.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_auto_close_on_invoice',
    label: 'Auto-close ticket on invoice',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Automatically moves the ticket to "Closed" status when an invoice is created.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_all_employees_view_all',
    label: 'All employees view all tickets',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When off, technicians only see tickets they created or are assigned to. Admins always see all.',
    default: true,
    type: 'boolean',
    requiresRole: 'admin',
  },
  {
    key: 'ticket_require_stopwatch',
    label: 'Require repair stopwatch',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When on, technicians must start the repair timer before marking the ticket complete. Useful for labor cost tracking.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_timer_auto_start_status',
    label: 'Auto-start timer on status',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Automatically starts the repair stopwatch when the ticket enters the selected status.',
    default: '',
    type: 'select',
    options: [
      { label: 'Disabled', value: '' },
      { label: 'In Progress', value: 'in_progress' },
    ],
  },
  {
    key: 'ticket_timer_auto_stop_status',
    label: 'Auto-stop timer on status',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Automatically stops the repair stopwatch when the ticket enters the selected status.',
    default: '',
    type: 'select',
    options: [
      { label: 'Disabled', value: '' },
      { label: 'Closed', value: 'closed' },
      { label: 'Waiting on Customer', value: 'waiting_on_customer' },
      { label: 'Waiting for Parts', value: 'waiting_for_parts' },
    ],
  },
  {
    key: 'ticket_auto_status_on_reply',
    label: 'Auto-update status on reply',
    tab: 'tickets-repairs',
    status: 'coming_soon',
    tooltip: 'Planned: automatically moves ticket status when the customer replies via SMS. Requires inbound SMS webhook wiring.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'ticket_auto_remove_passcode',
    label: 'Auto-remove passcode on close',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Clears the stored device passcode when the ticket is closed. Recommended for privacy compliance.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'ticket_copy_warranty_notes',
    label: 'Copy notes to warranty ticket',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'When creating a warranty ticket from a closed repair, automatically copy the original notes.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'ticket_default_assignment',
    label: 'Default Assignment',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'How new tickets are assigned when created. "Based on PIN" uses the employee PIN entered at check-in.',
    default: 'default',
    type: 'select',
    options: [
      { label: 'Default (Creator)', value: 'default' },
      { label: 'Unassigned', value: 'unassigned' },
      { label: 'Based on PIN', value: 'pin_based' },
    ],
  },
  {
    key: 'ticket_default_view',
    label: 'Default View',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Default landing view for the tickets page. Calendar mode is useful for appointment-based shops.',
    default: 'list',
    type: 'select',
    options: [
      { label: 'Listing', value: 'list' },
      { label: 'Calendar', value: 'calendar' },
    ],
  },
  {
    key: 'ticket_default_filter',
    label: 'Default Date Filter',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Default date range filter applied when opening the tickets page.',
    default: 'all',
    type: 'select',
    options: [
      { label: 'All', value: 'all' },
      { label: 'Today', value: 'today' },
      { label: '7 Days', value: '7days' },
      { label: '14 Days', value: '14days' },
      { label: '30 Days', value: '30days' },
    ],
  },
  {
    key: 'ticket_default_date_sort',
    label: 'Default Date Sort',
    tab: 'tickets-repairs',
    status: 'coming_soon',
    tooltip: 'Planned: switch between sorting by created date or due date. Currently only created date is respected.',
    default: 'created',
    type: 'select',
    options: [
      { label: 'Created Date', value: 'created' },
      { label: 'Due Date', value: 'due' },
    ],
  },
  {
    key: 'ticket_default_pagination',
    label: 'Default Pagination',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'How many tickets to load per page on the listing. Larger = slower but less clicking.',
    default: '25',
    type: 'select',
    options: [
      { label: '25', value: '25' },
      { label: '50', value: '50' },
      { label: '100', value: '100' },
    ],
  },
  {
    key: 'ticket_default_sort_order',
    label: 'Default Sort Order',
    tab: 'tickets-repairs',
    status: 'coming_soon',
    tooltip: 'Planned: change default sort column. Currently tickets always sort by created date descending.',
    default: 'due_date',
    type: 'select',
    options: [
      { label: 'By Due Date', value: 'due_date' },
      { label: 'By Created Date', value: 'created_date' },
      { label: 'By Ticket Number', value: 'ticket_number' },
    ],
  },
  {
    key: 'ticket_status_after_estimate',
    label: 'Status after estimate creation',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Automatically moves the ticket to this status when an estimate is sent to the customer.',
    default: '',
    type: 'select',
    options: [
      { label: 'No change', value: '' },
      { label: 'Waiting on Customer', value: 'waiting_on_customer' },
      { label: 'On Hold', value: 'on_hold' },
    ],
  },
  {
    key: 'ticket_label_template',
    label: 'Ticket Label Template',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Template used when printing ticket labels for repair bag tagging.',
    default: 'default',
    type: 'select',
    options: [
      { label: 'Default', value: 'default' },
      { label: 'Professional', value: 'professional' },
      { label: 'Compact', value: 'compact' },
      { label: 'Barcode Only', value: 'barcode' },
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// REPAIR-SPECIFIC SETTINGS
// ─────────────────────────────────────────────────────────────────────────────

const REPAIR_SETTINGS: SettingDef[] = [
  {
    key: 'repair_require_pre_condition',
    label: 'Require pre-repair condition check',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Technicians must complete the pre-repair condition checklist before starting work. Strongly recommended for liability.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'repair_require_post_condition',
    label: 'Require post-repair condition check',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Technicians must complete the post-repair checklist before closing the ticket. Catches workmanship issues early.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'repair_require_parts',
    label: 'Require part entry',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Ticket cannot be marked complete until at least one part has been added. Helps inventory tracking.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'repair_require_customer',
    label: 'Require customer information',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Blocks creating a repair ticket without a linked customer. Prevents orphan tickets.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'repair_require_diagnostic',
    label: 'Require diagnostic notes',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Diagnostic notes field must be filled before moving the ticket past "Diagnosis". Enforces quality documentation.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'repair_require_imei',
    label: 'Require device IMEI/Serial',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'IMEI or serial must be captured at check-in. Needed for warranty claims and stolen-device checks.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'repair_itemize_line_items',
    label: 'Itemize line items',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Each repair becomes a separate invoice line item instead of a single summary line. Better for customer transparency.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'repair_price_includes_parts',
    label: 'Price includes parts',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Quoted repair price is a flat rate including parts + labor. When off, parts are charged separately.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'repair_default_warranty_value',
    label: 'Default Warranty',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Default warranty period applied to new repairs. Shows on the invoice and receipt.',
    default: '90',
    type: 'number',
    min: 0,
    max: 3650,
  },
  {
    key: 'repair_default_input_criteria',
    label: 'Default Input Criteria',
    tab: 'tickets-repairs',
    status: 'coming_soon',
    tooltip: 'Planned: pre-select IMEI or Serial on the check-in form based on device type. Currently both fields are always shown.',
    default: 'imei',
    type: 'select',
    options: [
      { label: 'IMEI', value: 'imei' },
      { label: 'Serial', value: 'serial' },
    ],
  },
  {
    key: 'repair_default_due_value',
    label: 'Default Due Date',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Default due date offset for new tickets, e.g. 3 days from creation.',
    default: '3',
    type: 'number',
    min: 0,
    max: 365,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// POS — Many of these are "dead toggles" per the audit. Mark honestly.
// ─────────────────────────────────────────────────────────────────────────────

const POS_SETTINGS: SettingDef[] = [
  {
    key: 'pos_show_products',
    label: 'Display products tab',
    tab: 'pos',
    status: 'live',
    tooltip: 'Shows the Products tab in the POS right-side panel. Turn off if you only sell repairs.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_repairs',
    label: 'Display repairs tab',
    tab: 'pos',
    status: 'live',
    tooltip: 'Shows the Repairs tab in the POS. Turn off if you only sell retail products.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_miscellaneous',
    label: 'Display miscellaneous tab',
    tab: 'pos',
    status: 'live',
    tooltip: 'Shows a "Miscellaneous" tab for ad-hoc line items not in your inventory.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_bundles',
    label: 'Display product bundles tab',
    tab: 'pos',
    status: 'live',
    tooltip: 'Shows the bundles tab — prebuilt groups of products sold as a set.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'pos_show_out_of_stock',
    label: 'Display out-of-stock items',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: hide zero-stock items from the POS picker. Currently all items are always shown.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_invoice_notes',
    label: 'Display invoice notes',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: show the invoice notes field in the POS checkout panel. Currently always hidden.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_outstanding_alert',
    label: 'Display outstanding balance alert',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: warn the cashier when a customer has an outstanding balance. Currently no warning is shown.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'pos_show_images',
    label: 'Display manufacturer/device images',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: show device thumbnails in the POS picker. Currently only names are shown.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'pos_show_discount_reason',
    label: 'Display discount reason',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: add a "reason" field when applying a discount in POS. Currently discounts are applied without a reason.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'pos_show_cost_price',
    label: 'Display cost price',
    tab: 'pos',
    status: 'live',
    tooltip: 'Shows each item\'s cost price next to its sell price in the POS picker. Useful for margin calculation at checkout.',
    default: false,
    type: 'boolean',
    requiresRole: 'admin',
  },
  {
    key: 'pos_require_pin_sale',
    label: 'Require PIN to complete sale',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: prompt for employee PIN before finalizing a sale. Backend PIN gate not yet wired in POS checkout.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'pos_require_pin_ticket',
    label: 'Require PIN to create ticket',
    tab: 'pos',
    status: 'coming_soon',
    tooltip: 'Planned: prompt for employee PIN before creating a new ticket. Backend PIN gate not yet wired in check-in.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'pos_require_referral',
    label: 'Require referral source',
    tab: 'pos',
    status: 'live',
    tooltip: 'Blocks checkout until "How did you hear about us?" is filled. Useful for marketing attribution.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'checkin_default_category',
    label: 'Default device category',
    tab: 'pos',
    status: 'live',
    tooltip: 'Pre-selects this device category on the quick check-in form. Speeds up phone-only shops.',
    default: '',
    type: 'select',
    options: [
      { label: 'None (user picks)', value: '' },
      { label: 'Phone', value: 'phone' },
      { label: 'Tablet', value: 'tablet' },
      { label: 'Laptop', value: 'laptop' },
      { label: 'Console', value: 'console' },
      { label: 'TV', value: 'tv' },
      { label: 'Desktop', value: 'desktop' },
      { label: 'Other', value: 'other' },
    ],
  },
  {
    key: 'checkin_auto_print_label',
    label: 'Auto-print label after check-in',
    tab: 'pos',
    status: 'live',
    tooltip: 'Automatically opens the print-label dialog after a ticket is created via quick check-in.',
    default: false,
    type: 'boolean',
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// RECEIPTS — most receipt_cfg_* toggles ARE wired to the receipt renderer.
// A few print-path ones are coming soon.
// ─────────────────────────────────────────────────────────────────────────────

const RECEIPT_SETTINGS: SettingDef[] = [
  {
    key: 'receipt_logo',
    label: 'Receipt Logo',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Logo printed at the top of receipts. Auto-falls-back to the store logo if empty.',
    default: '',
    type: 'string',
  },
  {
    key: 'receipt_title',
    label: 'Receipt Title',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Large heading at the top of the printed receipt. Defaults to the store name.',
    default: '',
    type: 'string',
  },
  {
    key: 'receipt_terms',
    label: 'Receipt Terms',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Legal terms printed at the bottom of the receipt. Use for warranty disclaimers, return policy, etc.',
    default: '',
    type: 'textarea',
  },
  {
    key: 'receipt_footer',
    label: 'Receipt Footer',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Short friendly message at the very bottom of the receipt, e.g. "Thank you!"',
    default: '',
    type: 'textarea',
  },
  {
    key: 'receipt_thermal_terms',
    label: 'Thermal Receipt Terms',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Terms printed specifically on thermal (58mm/80mm) receipts. Keep short — thermal paper is narrow.',
    default: '',
    type: 'textarea',
  },
  {
    key: 'receipt_thermal_footer',
    label: 'Thermal Receipt Footer',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Footer message on thermal receipts. Shown under the totals section.',
    default: '',
    type: 'textarea',
  },
  {
    key: 'receipt_cfg_pre_conditions_page',
    label: 'Show pre-conditions (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the pre-repair condition checklist on letter-size receipts.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_pre_conditions_thermal',
    label: 'Show pre-conditions (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: include pre-conditions on thermal receipts. Currently only letter-size receipts include them.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_post_conditions_page',
    label: 'Show post-conditions (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the post-repair condition sign-off on letter-size receipts.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_signature_page',
    label: 'Show signature (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints a signature capture line on letter-size receipts.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_signature_thermal',
    label: 'Show signature (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: include signature line on thermal receipts. Currently thermal receipts have no signature section.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_po_so_page',
    label: 'Show PO/SO numbers (letter)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: print purchase order / sales order reference numbers on receipts. Backend field not yet wired.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_po_so_thermal',
    label: 'Show PO/SO numbers (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: same as above but for thermal receipts.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_security_code_page',
    label: 'Show security code (letter)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: print the device unlock code / backup PIN on the pickup receipt. Currently never included.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_security_code_thermal',
    label: 'Show security code (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: same as above but for thermal receipts.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_tax',
    label: 'Show tax breakdown',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Shows a per-item tax line under the totals. Required in some US jurisdictions.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_discount_thermal',
    label: 'Show discount (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: show the applied discount line on thermal receipts. Currently only letter receipts show it.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_line_price_incl_tax_thermal',
    label: 'Line prices include tax (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: show tax-inclusive line prices on thermal receipts (EU-style). Currently tax is always shown separately.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_transaction_id_page',
    label: 'Show transaction ID (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the BlockChyp / Stripe transaction reference on letter receipts. Required for dispute handling.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_transaction_id_thermal',
    label: 'Show transaction ID (thermal)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the payment transaction reference on thermal receipts.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_due_date',
    label: 'Show due date',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the ticket due date on receipts so customers know when to come back.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_employee_name',
    label: 'Show employee name',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints the employee who rang the sale. Useful for tip attribution and accountability.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_description_page',
    label: 'Show descriptions (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Shows multi-line descriptions under each line item on letter-size receipts.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_description_thermal',
    label: 'Show descriptions (thermal)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Shows short descriptions on thermal receipts. Truncated to fit narrow paper.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_parts_page',
    label: 'Show parts (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Lists individual parts used on the repair on letter-size receipts. Good for transparency.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_parts_thermal',
    label: 'Show parts (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: list parts on thermal receipts. Currently only a summary line is printed.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_part_sku',
    label: 'Show part SKUs',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: include part SKU codes next to each part line. Useful for warranty returns.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_network_thermal',
    label: 'Show carrier/network (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: print the device carrier/network on thermal receipts. Currently only letter receipts include it.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_service_desc_page',
    label: 'Show service description (letter)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Includes a short service description header before the repair line items.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_service_desc_thermal',
    label: 'Show service description (thermal)',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: include the service description on thermal receipts. Currently thermal only shows line items.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_device_location',
    label: 'Show device bin location',
    tab: 'receipts',
    status: 'coming_soon',
    tooltip: 'Planned: print the bin/shelf location of the device on the pickup receipt. Requires bin-tracking feature.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'receipt_cfg_barcode',
    label: 'Show barcode',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Prints a scannable barcode with the ticket ID for quick lookup at pickup.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'receipt_default_size',
    label: 'Default Receipt Size',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Which receipt format opens by default when printing — letter (8.5x11) or thermal (58mm/80mm).',
    default: 'letter',
    type: 'select',
    options: [
      { label: 'Letter (8.5x11)', value: 'letter' },
      { label: 'Thermal 58mm', value: 'thermal_58' },
      { label: 'Thermal 80mm', value: 'thermal_80' },
    ],
  },
  {
    key: 'label_width_mm',
    label: 'Label Width (mm)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Width of device/bag labels in millimeters. Match your label printer\'s paper size.',
    default: 40,
    type: 'number',
    min: 10,
    max: 200,
  },
  {
    key: 'label_height_mm',
    label: 'Label Height (mm)',
    tab: 'receipts',
    status: 'live',
    tooltip: 'Height of device/bag labels in millimeters.',
    default: 25,
    type: 'number',
    min: 10,
    max: 200,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATIONS / FEEDBACK — Most are live, a few planned
// ─────────────────────────────────────────────────────────────────────────────

const NOTIFICATION_SETTINGS: SettingDef[] = [
  {
    key: 'feedback_enabled',
    label: 'Enable feedback requests',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Sends a feedback request SMS to the customer after ticket close. Core review-collection feature.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'feedback_auto_sms',
    label: 'Auto-send feedback SMS',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Automatically sends the feedback SMS on close. When off, you must click "Request review" manually.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'feedback_sms_template',
    label: 'Feedback SMS template',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'Template used for feedback request SMS. Supports {customer_name}, {ticket_id}, {device_name} variables.',
    default: 'Hi {customer_name}, how was your repair experience for {device_name}? Reply 1-5 (1=poor, 5=excellent). Thank you!',
    type: 'textarea',
  },
  {
    key: 'feedback_delay_hours',
    label: 'Feedback delay',
    tab: 'tickets-repairs',
    status: 'live',
    tooltip: 'How long after ticket close to send the feedback SMS. 24h is ideal — the customer has actually used their device.',
    default: '24',
    type: 'select',
    options: [
      { label: 'Immediately', value: '0' },
      { label: '1 hour', value: '1' },
      { label: '24 hours', value: '24' },
      { label: '48 hours', value: '48' },
      { label: '72 hours', value: '72' },
    ],
  },
  {
    key: 'notification_digest_mode',
    label: 'Notification digest mode',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: batch notifications into a daily digest instead of sending each one separately. Reduces SMS costs.',
    default: 'immediate',
    type: 'select',
    options: [
      { label: 'Immediate', value: 'immediate' },
      { label: 'Daily Digest', value: 'daily' },
      { label: 'Weekly Digest', value: 'weekly' },
    ],
  },
  {
    key: 'notification_digest_hour',
    label: 'Digest send hour',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: hour of day to send the notification digest. Ignored when digest mode is "immediate".',
    default: 9,
    type: 'number',
    min: 0,
    max: 23,
  },
  {
    key: 'stall_alert_days',
    label: 'Stall alert threshold (days)',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: alert staff when a ticket has been in the same status for more than N days. Cron job not yet scheduled.',
    default: 7,
    type: 'number',
    min: 1,
    max: 90,
  },
  {
    key: 'review_request_delay_hours',
    label: 'Review request delay',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: delay before sending a Google/Yelp review link. Currently review links must be sent manually.',
    default: 48,
    type: 'number',
    min: 0,
    max: 168,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// SMS / VOICE — Provider settings are live, a few features are planned
// ─────────────────────────────────────────────────────────────────────────────

const SMS_VOICE_SETTINGS: SettingDef[] = [
  {
    key: 'sms_provider_type',
    label: 'SMS Provider',
    tab: 'sms-voice',
    status: 'live',
    tooltip: 'Which SMS gateway to use. Twilio is fully supported. Others are partially tested.',
    default: 'console',
    type: 'select',
    options: [
      { label: 'Console (dev only)', value: 'console' },
      { label: 'Twilio', value: 'twilio' },
      { label: 'Telnyx', value: 'telnyx' },
      { label: 'Bandwidth', value: 'bandwidth' },
      { label: 'Plivo', value: 'plivo' },
      { label: 'Vonage', value: 'vonage' },
    ],
    requiresRole: 'admin',
  },
  {
    key: 'voice_auto_record',
    label: 'Auto-record calls',
    tab: 'sms-voice',
    status: 'live',
    tooltip: 'Automatically records every outbound and inbound call. Check local wiretapping laws before enabling.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'voice_auto_transcribe',
    label: 'Auto-transcribe calls',
    tab: 'sms-voice',
    status: 'live',
    tooltip: 'Automatically runs speech-to-text on recorded calls. Requires the recording toggle to be on.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'voice_announce_recording',
    label: 'Announce recording to caller',
    tab: 'sms-voice',
    status: 'live',
    tooltip: 'Plays a "this call may be recorded" prompt at the start of recorded calls. Required in two-party-consent states.',
    default: true,
    type: 'boolean',
  },
  {
    key: 'voice_inbound_action',
    label: 'Inbound call action',
    tab: 'sms-voice',
    status: 'beta',
    tooltip: 'What happens when a customer calls — ring, forward, or voicemail. Voicemail transcription is still beta.',
    default: 'ring',
    type: 'select',
    options: [
      { label: 'Ring in browser', value: 'ring' },
      { label: 'Forward to phone', value: 'forward' },
      { label: 'Voicemail', value: 'voicemail' },
    ],
  },
  {
    key: 'voice_forward_number',
    label: 'Forward to phone number',
    tab: 'sms-voice',
    status: 'live',
    tooltip: 'E.164 phone number that inbound calls get forwarded to when action is set to "forward".',
    default: '',
    type: 'string',
  },
  {
    key: 'auto_reply_enabled',
    label: 'Off-hours auto-reply',
    tab: 'sms-voice',
    status: 'coming_soon',
    tooltip: 'Planned: auto-reply to inbound SMS outside business hours. Requires business hours to be configured. Backend scheduler not wired.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'auto_reply_message',
    label: 'Off-hours auto-reply message',
    tab: 'sms-voice',
    status: 'coming_soon',
    tooltip: 'Planned: the message sent as the off-hours auto-reply. Supports template variables.',
    default: 'Thanks for reaching out! We\'re currently closed. We\'ll respond when we open at {open_time}.',
    type: 'textarea',
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// INTEGRATIONS — Webhooks, 3CX, etc
// ─────────────────────────────────────────────────────────────────────────────

const INTEGRATION_SETTINGS: SettingDef[] = [
  {
    key: 'webhook_url',
    label: 'Webhook URL',
    tab: 'store',
    status: 'live',
    tooltip: 'HTTPS endpoint that receives POST requests when selected events occur. Use with Zapier, Make.com, or custom tools.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'webhook_events',
    label: 'Webhook Events',
    tab: 'store',
    status: 'live',
    tooltip: 'Which events trigger webhook calls. Select carefully — each event is a real HTTP request.',
    default: '[]',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'theme_primary_color',
    label: 'Primary Accent Color',
    tab: 'store',
    status: 'coming_soon',
    tooltip: 'Planned: customize the primary accent color across the whole app. Currently the value is saved but only lightly themed.',
    default: '#3b82f6',
    type: 'color',
  },
  {
    key: 'tcx_host',
    label: '3CX Host',
    tab: 'sms-voice',
    status: 'coming_soon',
    tooltip: 'Planned: 3CX PBX hostname for outbound call integration. Backend 3CX client not yet implemented.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'tcx_username',
    label: '3CX Username',
    tab: 'sms-voice',
    status: 'coming_soon',
    tooltip: 'Planned: 3CX user account for call routing.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'tcx_extension',
    label: '3CX Extension',
    tab: 'sms-voice',
    status: 'coming_soon',
    tooltip: 'Planned: your 3CX extension number.',
    default: '',
    type: 'string',
    requiresRole: 'admin',
  },
  {
    key: 'lead_auto_assign',
    label: 'Auto-assign leads',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: round-robin auto-assignment for incoming leads. Requires leads module to be fully wired.',
    default: false,
    type: 'boolean',
  },
  {
    key: 'estimate_followup_days',
    label: 'Estimate follow-up days',
    tab: 'notifications',
    status: 'coming_soon',
    tooltip: 'Planned: send a follow-up SMS N days after an estimate with no response. Cron job not yet scheduled.',
    default: 3,
    type: 'number',
    min: 1,
    max: 30,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// ASSEMBLED LIST
// ─────────────────────────────────────────────────────────────────────────────

export const SETTINGS_METADATA: SettingDef[] = [
  ...STORE_SETTINGS,
  ...TICKET_SETTINGS,
  ...REPAIR_SETTINGS,
  ...POS_SETTINGS,
  ...RECEIPT_SETTINGS,
  ...NOTIFICATION_SETTINGS,
  ...SMS_VOICE_SETTINGS,
  ...INTEGRATION_SETTINGS,
];

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/** Returns true when the given key has backend enforcement wired up. */
export function isSettingImplemented(key: string): boolean {
  return SETTINGS_METADATA.find((s) => s.key === key)?.status === 'live';
}

/** Returns the metadata entry for a given setting key, or null. */
export function getSettingMeta(key: string): SettingDef | null {
  return SETTINGS_METADATA.find((s) => s.key === key) ?? null;
}

/** Returns every setting that belongs to a given tab. */
export function getSettingsForTab(tab: string): SettingDef[] {
  return SETTINGS_METADATA.filter((s) => s.tab === tab);
}

/**
 * Returns the default values for a given tab, as a plain record. Used by the
 * "Reset to defaults" button.
 */
export function getDefaultsForTab(tab: string): Record<string, string> {
  const defaults: Record<string, string> = {};
  for (const s of SETTINGS_METADATA) {
    if (s.tab !== tab) continue;
    if (s.type === 'boolean') {
      defaults[s.key] = s.default ? '1' : '0';
    } else {
      defaults[s.key] = String(s.default ?? '');
    }
  }
  return defaults;
}

/**
 * Case-insensitive search across label, tooltip, tab name, and keywords.
 * Used by SettingsSearch to find matches across all tabs at once.
 */
export function searchSettings(query: string): SettingDef[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return SETTINGS_METADATA.filter((s) => {
    const haystack = [
      s.label,
      s.tooltip,
      s.tab,
      s.key,
      ...(s.keywords ?? []),
    ]
      .join(' ')
      .toLowerCase();
    return haystack.includes(q);
  });
}

/** Count of how many settings are "coming soon" (honesty metric). */
export function getComingSoonCount(): number {
  return SETTINGS_METADATA.filter((s) => s.status === 'coming_soon').length;
}

/** Count of how many settings are fully live. */
export function getLiveCount(): number {
  return SETTINGS_METADATA.filter((s) => s.status === 'live').length;
}
