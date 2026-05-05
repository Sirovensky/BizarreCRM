export const PERMISSIONS = {
  // Tickets
  TICKETS_VIEW: 'tickets.view',
  TICKETS_CREATE: 'tickets.create',
  TICKETS_EDIT: 'tickets.edit',
  TICKETS_DELETE: 'tickets.delete',
  TICKETS_CHANGE_STATUS: 'tickets.change_status',
  TICKETS_ASSIGN: 'tickets.assign',
  // SEC-H25: bulk operations (merge, bulk-action, clone-warranty) require elevated access
  TICKETS_BULK_UPDATE: 'tickets.bulk_update',

  // Customers
  CUSTOMERS_VIEW: 'customers.view',
  CUSTOMERS_CREATE: 'customers.create',
  CUSTOMERS_EDIT: 'customers.edit',
  CUSTOMERS_DELETE: 'customers.delete',
  // SEC-H25: destructive / privileged customer actions
  CUSTOMERS_MERGE: 'customers.merge',
  CUSTOMERS_GDPR_ERASE: 'customers.gdpr_erase',
  CUSTOMERS_ARCHIVE: 'customers.archive',
  CUSTOMERS_BULK_TAG: 'customers.bulk_tag',

  // Inventory
  INVENTORY_VIEW: 'inventory.view',
  INVENTORY_CREATE: 'inventory.create',
  INVENTORY_EDIT: 'inventory.edit',
  INVENTORY_DELETE: 'inventory.delete',
  INVENTORY_ADJUST_STOCK: 'inventory.adjust_stock',
  // SEC-H25: bulk operations (stocktake, bulk-action, receive-scan)
  INVENTORY_BULK_ACTION: 'inventory.bulk_action',

  // Invoices
  INVOICES_VIEW: 'invoices.view',
  INVOICES_CREATE: 'invoices.create',
  INVOICES_EDIT: 'invoices.edit',
  INVOICES_DELETE: 'invoices.delete',
  INVOICES_RECORD_PAYMENT: 'invoices.record_payment',
  // SEC-H25: void and bulk actions are destructive — separate from edit
  INVOICES_VOID: 'invoices.void',
  INVOICES_BULK_ACTION: 'invoices.bulk_action',
  INVOICES_CREDIT_NOTE: 'invoices.credit_note',

  // Refunds
  REFUNDS_CREATE: 'refunds.create',
  REFUNDS_APPROVE: 'refunds.approve',

  // Gift Cards
  GIFT_CARDS_ISSUE: 'gift_cards.issue',
  GIFT_CARDS_RELOAD: 'gift_cards.reload',
  GIFT_CARDS_REDEEM: 'gift_cards.redeem',

  // Deposits
  DEPOSITS_CREATE: 'deposits.create',
  DEPOSITS_APPLY: 'deposits.apply',
  DEPOSITS_DELETE: 'deposits.delete',

  // POS
  POS_ACCESS: 'pos.access',
  POS_CASH_REGISTER: 'pos.cash_register',

  // Leads
  LEADS_VIEW: 'leads.view',
  LEADS_CREATE: 'leads.create',
  LEADS_EDIT: 'leads.edit',

  // Estimates
  ESTIMATES_VIEW: 'estimates.view',
  ESTIMATES_CREATE: 'estimates.create',
  ESTIMATES_EDIT: 'estimates.edit',

  // Reports
  REPORTS_VIEW: 'reports.view',

  // Communications
  SMS_VIEW: 'sms.view',
  SMS_SEND: 'sms.send',
  EMAIL_SEND: 'email.send',

  // Employees
  EMPLOYEES_VIEW: 'employees.view',
  EMPLOYEES_MANAGE: 'employees.manage',
  CLOCK_IN_OUT: 'employees.clock',

  // Settings
  SETTINGS_VIEW: 'settings.view',
  SETTINGS_EDIT: 'settings.edit',
  USERS_MANAGE: 'users.manage',
  IMPORT_EXPORT: 'settings.import_export',
} as const;

export const ROLE_PERMISSIONS: Record<string, string[]> = {
  admin: Object.values(PERMISSIONS),
  // SEC-H25: manager gets all non-user-admin permissions except GDPR erase,
  // customer archive, invoice bulk-action, and settings.import_export.
  manager: Object.values(PERMISSIONS).filter(p =>
    !p.startsWith('users.') &&
    p !== PERMISSIONS.IMPORT_EXPORT &&
    p !== PERMISSIONS.CUSTOMERS_GDPR_ERASE,
  ),
  technician: [
    PERMISSIONS.TICKETS_VIEW, PERMISSIONS.TICKETS_CREATE, PERMISSIONS.TICKETS_EDIT,
    PERMISSIONS.TICKETS_CHANGE_STATUS, PERMISSIONS.TICKETS_ASSIGN,
    PERMISSIONS.CUSTOMERS_VIEW, PERMISSIONS.CUSTOMERS_CREATE, PERMISSIONS.CUSTOMERS_EDIT,
    PERMISSIONS.CUSTOMERS_BULK_TAG,
    PERMISSIONS.INVENTORY_VIEW,
    PERMISSIONS.INVOICES_VIEW,
    PERMISSIONS.SMS_VIEW, PERMISSIONS.SMS_SEND,
    PERMISSIONS.LEADS_VIEW, PERMISSIONS.LEADS_CREATE,
    PERMISSIONS.ESTIMATES_VIEW,
    PERMISSIONS.CLOCK_IN_OUT,
  ],
  cashier: [
    PERMISSIONS.POS_ACCESS, PERMISSIONS.POS_CASH_REGISTER,
    PERMISSIONS.TICKETS_VIEW,
    PERMISSIONS.CUSTOMERS_VIEW, PERMISSIONS.CUSTOMERS_CREATE,
    PERMISSIONS.INVOICES_VIEW, PERMISSIONS.INVOICES_RECORD_PAYMENT,
    PERMISSIONS.INVENTORY_VIEW,
    // SEC-H25: cashier can collect a deposit and redeem a gift card at POS
    PERMISSIONS.DEPOSITS_CREATE,
    PERMISSIONS.GIFT_CARDS_REDEEM,
    PERMISSIONS.CLOCK_IN_OUT,
  ],
};
