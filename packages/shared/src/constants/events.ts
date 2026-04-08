export const WS_EVENTS = {
  // Tickets
  TICKET_CREATED: 'ticket:created',
  TICKET_UPDATED: 'ticket:updated',
  TICKET_STATUS_CHANGED: 'ticket:status_changed',
  TICKET_NOTE_ADDED: 'ticket:note_added',
  TICKET_DELETED: 'ticket:deleted',

  // Customers
  CUSTOMER_CREATED: 'customer:created',
  CUSTOMER_UPDATED: 'customer:updated',

  // Invoices
  INVOICE_CREATED: 'invoice:created',
  INVOICE_UPDATED: 'invoice:updated',
  PAYMENT_RECEIVED: 'invoice:payment',

  // SMS
  SMS_RECEIVED: 'sms:received',
  SMS_SENT: 'sms:sent',

  // Inventory
  INVENTORY_STOCK_CHANGED: 'inventory:stock_changed',
  INVENTORY_LOW_STOCK: 'inventory:low_stock',

  // Leads
  LEAD_CREATED: 'lead:created',

  // Notifications
  NOTIFICATION_NEW: 'notification:new',

  // Import
  IMPORT_PROGRESS: 'import:progress',
  IMPORT_COMPLETE: 'import:complete',

  // System
  STALL_ALERT: 'system:stall_alert',
} as const;
