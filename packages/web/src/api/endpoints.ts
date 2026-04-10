import { api } from './client';
import type {
  Customer, CreateCustomerInput, UpdateCustomerInput, CustomerAsset,
  Ticket, CreateTicketInput, TicketStatus, TicketNote,
  Invoice, CreateInvoiceInput, RecordPaymentInput,
  InventoryItem, CreateInventoryInput,
  User, AuthTokens,
} from '@bizarre-crm/shared';

// ==================== Server Info ====================
export const serverInfoApi = {
  get: () => api.get<{ success: boolean; data: { lan_ip: string; port: number; server_url: string } }>('/info'),
};

// ==================== Auth ====================
export const authApi = {
  setupStatus: () => api.get<{ success: boolean; data: { needsSetup: boolean } }>('/auth/setup-status'),
  setup: (data: { username: string; password: string; email?: string }) =>
    api.post<{ success: boolean; data: { message: string } }>('/auth/setup', data),
  login: (username: string, password: string) =>
    api.post<{ success: boolean; data: { challengeToken: string; totpEnabled: boolean; requires2faSetup: boolean } }>('/auth/login', { username, password }),
  setPassword: (challengeToken: string, password: string) =>
    api.post<{ success: boolean; data: { challengeToken: string } }>('/auth/login/set-password', { challengeToken, password }),
  setup2fa: (challengeToken: string) =>
    api.post<{ success: boolean; data: { qr: string; secret: string; manualEntry: string } }>('/auth/login/2fa-setup', { challengeToken }),
  verify2fa: (challengeToken: string, code: string, trustDevice?: boolean) =>
    api.post<{ success: boolean; data: AuthTokens; message?: string }>('/auth/login/2fa-verify', { challengeToken, code, trustDevice }),
  logout: () => api.post('/auth/logout'),
  switchUser: (pin: string) =>
    api.post<{ success: boolean; data: AuthTokens }>('/auth/switch-user', { pin }),
  verifyPin: (pin: string) =>
    api.post<{ success: boolean; data: { verified: boolean } }>('/auth/verify-pin', { pin }),
  me: () => api.get<{ success: boolean; data: { user: User } }>('/auth/me'),
};

// ==================== Customers ====================
interface PaginatedResponse<T> {
  success: boolean;
  data: {
    customers?: T[];
    tickets?: T[];
    invoices?: T[];
    items?: T[];
    pagination: { page: number; per_page: number; total: number; total_pages: number };
  };
}

export const customerApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; group_id?: number; include_stats?: string; from_date?: string; to_date?: string; has_open_tickets?: string }) =>
    api.get('/customers', { params }),
  importCsv: (items: any[]) => api.post('/customers/import-csv', { items }),
  get: (id: number) =>
    api.get(`/customers/${id}`),
  create: (data: CreateCustomerInput) =>
    api.post('/customers', data),
  update: (id: number, data: UpdateCustomerInput) =>
    api.put(`/customers/${id}`, data),
  delete: (id: number) =>
    api.delete(`/customers/${id}`),
  search: (q: string) =>
    api.get('/customers/search', { params: { q } }),
  // Sub-resources
  getTickets: (id: number, params?: { page?: number }) =>
    api.get(`/customers/${id}/tickets`, { params }),
  getInvoices: (id: number, params?: { page?: number }) =>
    api.get(`/customers/${id}/invoices`, { params }),
  getCommunications: (id: number, params?: { page?: number }) =>
    api.get(`/customers/${id}/communications`, { params }),
  getAssets: (id: number) =>
    api.get(`/customers/${id}/assets`),
  addAsset: (id: number, data: Partial<CustomerAsset>) =>
    api.post(`/customers/${id}/assets`, data),
  updateAsset: (assetId: number, data: Partial<CustomerAsset>) =>
    api.put(`/customers/assets/${assetId}`, data),
  deleteAsset: (assetId: number) =>
    api.delete(`/customers/assets/${assetId}`),
  // Groups — CRUD lives in settingsApi.getCustomerGroups / createCustomerGroup / etc.
  analytics: (id: number) => api.get(`/customers/${id}/analytics`),
  bulkTag: (customerIds: number[], tag: string) =>
    api.post('/customers/bulk-tag', { customer_ids: customerIds, tag }),
  exportData: (id: number) => api.get(`/customers/${id}/export`),
  merge: (keep_id: number, merge_id: number) =>
    api.post('/customers/merge', { keep_id, merge_id }),
};

// ==================== Tickets ====================
export const ticketApi = {
  myQueue: () => api.get('/tickets/my-queue'),
  list: (params?: {
    page?: number; pagesize?: number; keyword?: string;
    status_id?: number | string; assigned_to?: number;
    date_filter?: string; from_date?: string; to_date?: string;
    sort_by?: string; sort_order?: string;
  }) => api.get('/tickets', { params }),
  get: (id: number) => api.get(`/tickets/${id}`),
  create: (data: CreateTicketInput) => api.post('/tickets', data),
  update: (id: number, data: Partial<Ticket>) => api.put(`/tickets/${id}`, data),
  delete: (id: number) => api.delete(`/tickets/${id}`),
  changeStatus: (id: number, status_id: number) =>
    api.patch(`/tickets/${id}/status`, { status_id }),
  addNote: (id: number, data: { type: string; content: string; is_flagged?: boolean; ticket_device_id?: number }) =>
    api.post(`/tickets/${id}/notes`, data),
  editNote: (noteId: number, data: { content: string }) =>
    api.put(`/tickets/notes/${noteId}`, data),
  deleteNote: (noteId: number) =>
    api.delete(`/tickets/notes/${noteId}`),
  uploadPhotos: (id: number, formData: FormData) =>
    api.post(`/tickets/${id}/photos`, formData, { headers: { 'Content-Type': 'multipart/form-data' } }),
  deletePhoto: (photoId: number) =>
    api.delete(`/tickets/photos/${photoId}`),
  convertToInvoice: (id: number) =>
    api.post(`/tickets/${id}/convert-to-invoice`),
  getHistory: (id: number) =>
    api.get(`/tickets/${id}/history`),
  addDevice: (id: number, data: any) =>
    api.post(`/tickets/${id}/devices`, data),
  updateDevice: (deviceId: number, data: any) =>
    api.put(`/tickets/devices/${deviceId}`, data),
  deleteDevice: (deviceId: number) =>
    api.delete(`/tickets/devices/${deviceId}`),
  addParts: (deviceId: number, data: any) =>
    api.post(`/tickets/devices/${deviceId}/parts`, data),
  quickAddPart: (deviceId: number, data: { name: string; price: number; quantity?: number }) =>
    api.post(`/tickets/devices/${deviceId}/quick-add-part`, data),
  removePart: (partId: number) =>
    api.delete(`/tickets/devices/parts/${partId}`),
  updatePart: (partId: number, data: { status?: string; catalog_item_id?: number; supplier_url?: string }) =>
    api.patch(`/tickets/devices/parts/${partId}`, data),
  updateChecklist: (deviceId: number, items: any[]) =>
    api.put(`/tickets/devices/${deviceId}/checklist`, { items }),
  kanban: () => api.get('/tickets/kanban'),
  stalled: (days?: number) => api.get('/tickets/stalled', { params: { days } }),
  tvDisplay: () => api.get('/tickets/tv-display'),
  togglePin: (id: number) =>
    api.patch(`/tickets/${id}/pin`),
  bulkAction: (ticket_ids: number[], action: string, value?: number) =>
    api.post('/tickets/bulk-action', { ticket_ids, action, value }),
  generateOtp: (id: number) => api.post(`/tickets/${id}/otp`),
  verifyOtp: (id: number, code: string) => api.post(`/tickets/${id}/verify-otp`, { code }),
  deviceHistory: (params: { imei?: string; serial?: string }) =>
    api.get('/tickets/device-history', { params }),
  warrantyLookup: (params: { imei?: string; serial?: string; phone?: string }) =>
    api.get('/tickets/warranty-lookup', { params }),
  exportCsv: (params?: {
    keyword?: string; status_id?: number | string; assigned_to?: number;
    date_filter?: string; from_date?: string; to_date?: string;
    sort_by?: string; sort_order?: string;
  }) => api.get('/tickets/export', { params, responseType: 'blob' }),
  savedFilters: {
    list: () => api.get('/tickets/saved-filters'),
    create: (data: { name: string; filters: Record<string, string | number | undefined> }) =>
      api.post('/tickets/saved-filters', data),
    delete: (id: number) => api.delete(`/tickets/saved-filters/${id}`),
  },
  // Appointments linked to ticket
  createAppointment: (id: number, data: { start_time: string; end_time?: string; note?: string }) =>
    api.post(`/tickets/${id}/appointment`, data),
  getAppointments: (id: number) => api.get(`/tickets/${id}/appointments`),
};

// ==================== Invoices ====================
export const invoiceApi = {
  list: (params?: { page?: number; pagesize?: number; status?: string; from_date?: string; to_date?: string; keyword?: string; customer_id?: number }) =>
    api.get('/invoices', { params }),
  stats: () => api.get('/invoices/stats'),
  get: (id: number) => api.get(`/invoices/${id}`),
  create: (data: CreateInvoiceInput) => api.post('/invoices', data),
  update: (id: number, data: any) => api.put(`/invoices/${id}`, data),
  recordPayment: (id: number, data: RecordPaymentInput) => api.post(`/invoices/${id}/payments`, data),
  void: (id: number) => api.post(`/invoices/${id}/void`),
  bulkAction: (action: string, invoiceIds: number[]) =>
    api.post('/invoices/bulk-action', { action, invoice_ids: invoiceIds }),
};

// ==================== Inventory ====================
export const inventoryApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; item_type?: string; category?: string; low_stock?: boolean; supplier_id?: number; manufacturer?: string; min_price?: number; max_price?: number; hide_out_of_stock?: boolean }) =>
    api.get('/inventory', { params }),
  manufacturers: () => api.get('/inventory/manufacturers'),
  importCsv: (items: any[]) => api.post('/inventory/import-csv', { items }),
  bulkAction: (item_ids: number[], action: string, value?: string | number) =>
    api.post('/inventory/bulk-action', { item_ids, action, value }),
  get: (id: number) => api.get(`/inventory/${id}`),
  create: (data: CreateInventoryInput) => api.post('/inventory', data),
  update: (id: number, data: Partial<InventoryItem>) => api.put(`/inventory/${id}`, data),
  delete: (id: number) => api.delete(`/inventory/${id}`),
  adjustStock: (id: number, data: { quantity: number; type: string; notes?: string }) =>
    api.post(`/inventory/${id}/adjust-stock`, data),
  lowStock: () => api.get('/inventory/low-stock'),
  dismissLowStock: () => api.post('/inventory/dismiss-low-stock'),
  undismissLowStock: () => api.post('/inventory/undismiss-low-stock'),
  categories: () => api.get('/inventory/categories'),
  lookupBarcode: (code: string) => api.get(`/inventory/barcode/${code}`),
  // Suppliers
  listSuppliers: () => api.get('/inventory/suppliers/list'),
  createSupplier: (data: any) => api.post('/inventory/suppliers', data),
  updateSupplier: (id: number, data: any) => api.put(`/inventory/suppliers/${id}`, data),
  // Purchase Orders
  listPurchaseOrders: (params?: any) => api.get('/inventory/purchase-orders/list', { params }),
  getPurchaseOrder: (id: number) => api.get(`/inventory/purchase-orders/${id}`),
  createPurchaseOrder: (data: any) => api.post('/inventory/purchase-orders', data),
  receivePurchaseOrder: (id: number, data: any) => api.post(`/inventory/purchase-orders/${id}/receive`, data),
  // Scan-to-receive
  receiveScan: (items: { barcode: string; quantity: number }[], notes?: string) =>
    api.post('/inventory/receive-scan', { items, notes }),
  receiveScanFromCatalog: (data: { catalog_id: number; quantity?: number; retail_price?: number; markup_pct?: number }) =>
    api.post('/inventory/receive-scan/create-from-catalog', data),
  receiveScanQuickAdd: (data: { barcode?: string; name: string; cost_price?: number; retail_price?: number; category?: string; quantity?: number }) =>
    api.post('/inventory/receive-scan/quick-add', data),
  getBarcode: (id: number, format?: string) =>
    api.get(`/inventory/${id}/barcode`, { params: { format: format || 'svg' } }),
  varianceReport: (months?: number) =>
    api.get('/inventory/variance-report', { params: { months: months || 6 } }),
};

// ==================== Settings ====================
export const settingsApi = {
  reconcileCogs: () => api.post('/settings/reconcile-cogs'),
  getStatuses: () => api.get('/settings/statuses'),
  createStatus: (data: any) => api.post('/settings/statuses', data),
  updateStatus: (id: number, data: any) => api.put(`/settings/statuses/${id}`, data),
  deleteStatus: (id: number) => api.delete(`/settings/statuses/${id}`),
  getStore: () => api.get('/settings/store'),
  updateStore: (data: any) => api.put('/settings/store', data),
  getTaxClasses: () => api.get('/settings/tax-classes'),
  createTaxClass: (data: any) => api.post('/settings/tax-classes', data),
  updateTaxClass: (id: number, data: any) => api.put(`/settings/tax-classes/${id}`, data),
  deleteTaxClass: (id: number) => api.delete(`/settings/tax-classes/${id}`),
  getPaymentMethods: () => api.get('/settings/payment-methods'),
  createPaymentMethod: (data: any) => api.post('/settings/payment-methods', data),
  getReferralSources: () => api.get('/settings/referral-sources'),
  createReferralSource: (data: any) => api.post('/settings/referral-sources', data),
  getUsers: () => api.get('/settings/users'),
  createUser: (data: any) => api.post('/settings/users', data),
  updateUser: (id: number, data: any) => api.put(`/settings/users/${id}`, data),
  // Generic config (key-value store)
  getConfig: () => api.get('/settings/config'),
  updateConfig: (data: Record<string, string>) => api.put('/settings/config', data),
  getSetupStatus: () => api.get('/settings/setup-status'),
  completeSetup: (data: { store_name: string; address?: string; phone?: string; email?: string; timezone?: string; currency?: string }) =>
    api.post('/settings/complete-setup', data),
  // Condition Templates & Checks
  getConditionTemplates: (category?: string) => api.get('/settings/condition-templates', { params: category ? { category } : undefined }),
  createConditionTemplate: (data: { category: string; name: string }) => api.post('/settings/condition-templates', data),
  updateConditionTemplate: (id: number, data: { name?: string; is_default?: number }) => api.put(`/settings/condition-templates/${id}`, data),
  deleteConditionTemplate: (id: number) => api.delete(`/settings/condition-templates/${id}`),
  getConditionChecks: (category: string) => api.get(`/settings/condition-checks/${category}`),
  addConditionCheck: (data: { template_id: number; label: string }) => api.post('/settings/condition-checks', data),
  updateConditionCheck: (id: number, data: { label?: string; sort_order?: number; is_active?: number }) => api.put(`/settings/condition-checks/${id}`, data),
  deleteConditionCheck: (id: number) => api.delete(`/settings/condition-checks/${id}`),
  reorderConditionChecks: (templateId: number, order: number[]) => api.put(`/settings/condition-checks-reorder/${templateId}`, { order }),
  // Customer Groups
  getCustomerGroups: () => api.get('/settings/customer-groups'),
  createCustomerGroup: (data: { name: string; discount_pct?: number; discount_type?: string; auto_apply?: boolean; description?: string }) =>
    api.post('/settings/customer-groups', data),
  updateCustomerGroup: (id: number, data: { name?: string; discount_pct?: number; discount_type?: string; auto_apply?: boolean; description?: string }) =>
    api.put(`/settings/customer-groups/${id}`, data),
  deleteCustomerGroup: (id: number) => api.delete(`/settings/customer-groups/${id}`),
  // Notification Templates
  getNotificationTemplates: () => api.get('/settings/notification-templates'),
  updateNotificationTemplate: (id: number, data: any) => api.put(`/settings/notification-templates/${id}`, data),
  // Logo upload
  uploadLogo: (formData: FormData) => api.post('/settings/logo', formData, { headers: { 'Content-Type': 'multipart/form-data' } }),
  // Checklist templates
  getChecklistTemplates: () => api.get('/settings/checklist-templates'),
  createChecklistTemplate: (data: any) => api.post('/settings/checklist-templates', data),
  updateChecklistTemplate: (id: number, data: any) => api.put(`/settings/checklist-templates/${id}`, data),
  deleteChecklistTemplate: (id: number) => api.delete(`/settings/checklist-templates/${id}`),
  // ENR-S8: Audit logs
  getAuditLogs: (params?: { page?: number; pagesize?: number; event?: string; user_id?: number; from_date?: string; to_date?: string }) =>
    api.get('/settings/audit-logs', { params }),
  // ENR-S1: Settings import/export
  exportSettings: () => api.get('/settings/export'),
  importSettings: (data: Record<string, string>) => api.post('/settings/import', data),
  // ENR-S6: Per-user preferences
  getPreferences: () => api.get('/settings/preferences'),
  updatePreferences: (data: Record<string, unknown>) => api.put('/settings/preferences', data),
  // ENR-S7: Role-based module visibility
  getModuleVisibility: () => api.get('/settings/module-visibility'),
  updateModuleVisibility: (data: Record<string, string[]>) => api.put('/settings/module-visibility', data),
};

// ==================== Automations ====================
export const automationsApi = {
  list: () => api.get('/automations'),
  create: (data: { name: string; trigger_type: string; trigger_config?: Record<string, unknown>; action_type: string; action_config?: Record<string, unknown>; sort_order?: number }) =>
    api.post('/automations', data),
  update: (id: number, data: Partial<{ name: string; trigger_type: string; trigger_config: Record<string, unknown>; action_type: string; action_config: Record<string, unknown>; sort_order: number }>) =>
    api.put(`/automations/${id}`, data),
  delete: (id: number) => api.delete(`/automations/${id}`),
  toggle: (id: number) => api.patch(`/automations/${id}/toggle`),
};

// ==================== Search ====================
export const searchApi = {
  global: (q: string) => api.get('/search', { params: { q } }),
};

// ==================== Expenses ====================
export const expenseApi = {
  list: (params?: { page?: number; pagesize?: number; category?: string; from_date?: string; to_date?: string; keyword?: string }) =>
    api.get('/expenses', { params }),
  get: (id: number) => api.get(`/expenses/${id}`),
  create: (data: { category: string; amount: number; description?: string; date?: string }) =>
    api.post('/expenses', data),
  update: (id: number, data: Partial<{ category: string; amount: number; description: string; date: string }>) =>
    api.put(`/expenses/${id}`, data),
  delete: (id: number) => api.delete(`/expenses/${id}`),
};

// ==================== Reports ====================
export const reportApi = {
  dashboard: () => api.get('/reports/dashboard'),
  dashboardKpis: (params?: { from_date?: string; to_date?: string; employee_id?: number }) =>
    api.get('/reports/dashboard-kpis', { params }),
  insights: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/insights', { params }),
  sales: (params?: any) => api.get('/reports/sales', { params }),
  tickets: (params?: any) => api.get('/reports/tickets', { params }),
  employees: (params?: any) => api.get('/reports/employees', { params }),
  inventory: (params?: any) => api.get('/reports/inventory', { params }),
  tax: (params?: any) => api.get('/reports/tax', { params }),
  tips: (params?: { from_date?: string; to_date?: string; group_by?: string }) =>
    api.get('/reports/tips', { params }),
  needsAttention: () => api.get('/reports/needs-attention'),
  techWorkload: () => api.get('/reports/tech-workload'),
  warrantyClaims: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/warranty-claims', { params }),
  deviceModels: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/device-models', { params }),
  partsUsage: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/parts-usage', { params }),
  technicianHours: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/technician-hours', { params }),
  stalledTickets: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/stalled-tickets', { params }),
  customerAcquisition: (params?: { from_date?: string; to_date?: string }) =>
    api.get('/reports/customer-acquisition', { params }),
};

// ==================== SMS ====================
export const smsApi = {
  unreadCount: () => api.get<{ success: boolean; data: { count: number } }>('/sms/unread-count'),
  conversations: (params?: { keyword?: string; include_archived?: string }) => api.get('/sms/conversations', { params }),
  messages: (phone: string) => api.get(`/sms/conversations/${phone}`),
  markRead: (phone: string) => api.patch(`/sms/conversations/${phone}/read`),
  toggleFlag: (phone: string) => api.patch(`/sms/conversations/${phone}/flag`),
  togglePin: (phone: string) => api.patch(`/sms/conversations/${phone}/pin`),
  toggleArchive: (phone: string) => api.patch(`/sms/conversations/${phone}/archive`),
  send: (data: { to: string; message?: string; entity_type?: string; entity_id?: number; template_id?: number; template_vars?: Record<string, string>; send_at?: string }) =>
    api.post('/sms/send', data),
  templates: () => api.get('/sms/templates'),
  createTemplate: (data: any) => api.post('/sms/templates', data),
  updateTemplate: (id: number, data: any) => api.put(`/sms/templates/${id}`, data),
  deleteTemplate: (id: number) => api.delete(`/sms/templates/${id}`),
  previewTemplate: (template_id: number, vars: Record<string, string>) =>
    api.post('/sms/preview-template', { template_id, vars }),
  uploadMedia: (file: File) => {
    const form = new FormData();
    form.append('file', file);
    return api.post<{ success: boolean; data: { url: string; contentType: string } }>('/sms/upload-media', form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
};

// ==================== Voice / Click-to-Call ====================
export const voiceApi = {
  call: (data: { to: string; mode?: string; entity_type?: string; entity_id?: number }) =>
    api.post<{ success: boolean; data?: unknown; message?: string }>('/voice/call', data),
  calls: (params?: { page?: number; pagesize?: number; conv_phone?: string; entity_type?: string; entity_id?: number }) =>
    api.get('/voice/calls', { params }),
  callDetail: (id: number) => api.get(`/voice/calls/${id}`),
};

// ==================== POS ====================
export const posApi = {
  products: (params?: { keyword?: string; category?: string; item_type?: string }) =>
    api.get('/pos/products', { params }),
  register: () => api.get('/pos/register'),
  cashIn: (data: { amount: number; reason?: string }) => api.post('/pos/cash-in', data),
  cashOut: (data: { amount: number; reason?: string }) => api.post('/pos/cash-out', data),
  transaction: (data: any) => api.post('/pos/transaction', data),
  transactions: (params?: any) => api.get('/pos/transactions', { params }),
  checkoutWithTicket: (data: any) => api.post('/pos/checkout-with-ticket', data),
  openDrawer: (data?: { reason?: string }) => api.post('/pos/open-drawer', data ?? {}),
};

// ==================== Notifications ====================
export const notificationApi = {
  list: (params?: { page?: number; pagesize?: number }) => api.get('/notifications', { params }),
  unreadCount: () => api.get('/notifications/unread-count'),
  markRead: (id: number) => api.patch(`/notifications/${id}/read`),
  markAllRead: () => api.post('/notifications/mark-all-read'),
  sendReceipt: (data: { invoice_id: number; email?: string }) => api.post('/notifications/send-receipt', data),
};

// ==================== Catalog (supplier catalog + device models) ====================
export const catalogApi = {
  // Manufacturers
  getManufacturers: () => api.get('/catalog/manufacturers'),

  // Device models
  searchDevices: (params?: {
    q?: string;
    manufacturer_id?: number;
    category?: string;
    popular?: boolean;
    limit?: number;
  }) => api.get('/catalog/devices', { params: { ...params, popular: params?.popular ? '1' : undefined } }),
  getDevice: (id: number) => api.get(`/catalog/devices/${id}`),

  // Supplier catalog
  search: (params?: {
    q?: string;
    source?: string;
    device_model_id?: number;
    category?: string;
    limit?: number;
    offset?: number;
  }) => api.get('/catalog/search', { params }),

  // Import catalog item to inventory
  importItem: (catalogId: number, data?: { markup_pct?: number; in_stock_qty?: number }) =>
    api.post(`/catalog/import/${catalogId}`, data),

  // Sync jobs
  startSync: (source: 'mobilesentrix' | 'phonelcdparts') =>
    api.post('/catalog/sync', { source }),
  getJobs: () => api.get('/catalog/jobs'),
  getJob: (id: number) => api.get(`/catalog/jobs/${id}`),
  getStats: () => api.get('/catalog/stats'),

  // Unified parts search (inventory first + supplier catalog)
  partsSearch: (params: {
    q: string;
    device_model_id?: number;
    source?: string;
    live?: boolean;
  }) => api.get('/catalog/parts-search', {
    params: { ...params, live: params.live === false ? '0' : undefined },
  }),

  // Bulk import from CSV
  bulkImport: (data: { source: string; items: any[] }) =>
    api.post('/catalog/bulk-import', data),

  // Live search directly on supplier website
  liveSearch: (source: 'mobilesentrix' | 'phonelcdparts', q: string) =>
    api.post('/catalog/live-search', { source, q }),

  // Sync cost prices from supplier catalog to inventory
  syncCostPrices: () => api.post('/catalog/sync-cost-prices'),

  // Template catalog pre-population
  loadFromTemplate: () => api.post('/catalog/load-from-template'),
  templateCount: () => api.get('/catalog/template-count'),

  // Parts order queue
  getOrderQueue: (status?: string) => api.get('/catalog/order-queue', { params: { status } }),
  getOrderQueueSummary: () => api.get('/catalog/order-queue/summary'),
  addToOrderQueue: (data: {
    source?: string;
    catalog_item_id?: number;
    inventory_item_id?: number;
    name: string;
    sku?: string;
    supplier_url?: string;
    image_url?: string;
    unit_price?: number;
    quantity_needed?: number;
    ticket_device_part_id?: number;
    ticket_id?: number;
    notes?: string;
  }) => api.post('/catalog/order-queue/add', data),
  updateOrderQueueItem: (id: number, data: { status?: string; notes?: string }) =>
    api.patch(`/catalog/order-queue/${id}`, data),
};

// ==================== Leads ====================
export const leadApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; status?: string; assigned_to?: number }) =>
    api.get('/leads', { params }),
  get: (id: number) => api.get(`/leads/${id}`),
  create: (data: any) => api.post('/leads', data),
  update: (id: number, data: any) => api.put(`/leads/${id}`, data),
  convert: (id: number) => api.post(`/leads/${id}/convert`),
  delete: (id: number) => api.delete(`/leads/${id}`),
  pipeline: () => api.get('/leads/pipeline'),
  reminders: (id: number) => api.get(`/leads/${id}/reminders`),
  createReminder: (id: number, data: { remind_at: string; note?: string }) =>
    api.post(`/leads/${id}/reminder`, data),
  appointments: (params?: { from_date?: string; to_date?: string; assigned_to?: number; status?: string }) =>
    api.get('/leads/appointments', { params }),
  createAppointment: (data: any) => api.post('/leads/appointments', data),
  updateAppointment: (id: number, data: any) => api.put(`/leads/appointments/${id}`, data),
  deleteAppointment: (id: number) => api.delete(`/leads/appointments/${id}`),
};

// ==================== Estimates ====================
export const estimateApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; status?: string }) =>
    api.get('/estimates', { params }),
  get: (id: number) => api.get(`/estimates/${id}`),
  create: (data: any) => api.post('/estimates', data),
  update: (id: number, data: any) => api.put(`/estimates/${id}`, data),
  convert: (id: number) => api.post(`/estimates/${id}/convert`),
  bulkConvert: (estimate_ids: number[]) => api.post('/estimates/bulk-convert', { estimate_ids }),
  delete: (id: number) => api.delete(`/estimates/${id}`),
  send: (id: number, method?: 'sms' | 'email') => api.post(`/estimates/${id}/send`, { method: method ?? 'sms' }),
  approve: (id: number, token?: string) => api.post(`/estimates/${id}/approve`, token ? { token } : {}),
  versions: (id: number) => api.get(`/estimates/${id}/versions`),
  versionDetail: (id: number, versionId: number) => api.get(`/estimates/${id}/versions/${versionId}`),
};

// ==================== Employees ====================
export const employeeApi = {
  list: () => api.get('/employees'),
  get: (id: number) => api.get(`/employees/${id}`),
  clockIn: (id: number, pin: string) => api.post(`/employees/${id}/clock-in`, { pin }),
  clockOut: (id: number, pin: string) => api.post(`/employees/${id}/clock-out`, { pin }),
  hours: (id: number, params?: { from_date?: string; to_date?: string }) =>
    api.get(`/employees/${id}/hours`, { params }),
  commissions: (id: number, params?: { from_date?: string; to_date?: string }) =>
    api.get(`/employees/${id}/commissions`, { params }),
};

// ==================== User Preferences ====================
export const preferencesApi = {
  getAll: () => api.get('/preferences'),
  get: (key: string) => api.get(`/preferences/${key}`),
  set: (key: string, value: any) => api.put(`/preferences/${key}`, { value }),
  delete: (key: string) => api.delete(`/preferences/${key}`),
};

// ==================== Missing Parts ====================
export const missingPartsApi = {
  list: () => api.get('/tickets/missing-parts'),
};

// ==================== Repair Pricing ====================
export const repairPricingApi = {
  // Services
  getServices: (params?: { category?: string }) => api.get('/repair-pricing/services', { params }),
  createService: (data: any) => api.post('/repair-pricing/services', data),
  updateService: (id: number, data: any) => api.put(`/repair-pricing/services/${id}`, data),
  deleteService: (id: number) => api.delete(`/repair-pricing/services/${id}`),
  // Prices
  getPrices: (params?: { device_model_id?: number; repair_service_id?: number; category?: string }) =>
    api.get('/repair-pricing/prices', { params }),
  createPrice: (data: any) => api.post('/repair-pricing/prices', data),
  updatePrice: (id: number, data: any) => api.put(`/repair-pricing/prices/${id}`, data),
  deletePrice: (id: number) => api.delete(`/repair-pricing/prices/${id}`),
  lookup: (params: { device_model_id: number; repair_service_id: number }) =>
    api.get('/repair-pricing/lookup', { params }),
  // Grades
  addGrade: (priceId: number, data: any) => api.post(`/repair-pricing/prices/${priceId}/grades`, data),
  updateGrade: (id: number, data: any) => api.put(`/repair-pricing/grades/${id}`, data),
  deleteGrade: (id: number) => api.delete(`/repair-pricing/grades/${id}`),
  // Adjustments
  getAdjustments: () => api.get('/repair-pricing/adjustments'),
  setAdjustments: (data: { flat: number; pct: number }) => api.put('/repair-pricing/adjustments', data),
};

// ==================== Public Tracking ====================
export const trackingApi = {
  byOrderId: (orderId: string) => api.get(`/track/${orderId}`),
  lookup: (data: { phone: string; order_id?: string }) => api.post('/track/lookup', data),
  byToken: (token: string) => api.get(`/track/token/${token}`),
};

// ==================== RepairDesk Import ====================
export const rdImportApi = {
  testConnection: (apiKey: string) => api.post('/import/repairdesk/test-connection', { api_key: apiKey }),
  start: (data: { api_key: string; entities: string[] }) => api.post('/import/repairdesk/start', data),
  nuclear: (apiKey: string, password: string) => api.post('/import/repairdesk/nuclear', { api_key: apiKey, confirm: 'NUCLEAR', password }),
  status: () => api.get('/import/repairdesk/status'),
  cancel: () => api.post('/import/repairdesk/cancel'),
  oauthStatus: () => api.get('/import/oauth/status'),
  oauthAuthorizeUrl: () => api.get('/import/oauth/authorize-url'),
  oauthRefresh: () => api.post('/import/oauth/refresh'),
};

// ==================== RepairShopr Import ====================
export const rsImportApi = {
  testConnection: (data: { api_key: string; subdomain: string }) => api.post('/import/repairshopr/test-connection', data),
  start: (data: { api_key: string; subdomain: string; entities: string[] }) => api.post('/import/repairshopr/start', data),
  status: () => api.get('/import/repairshopr/status'),
  cancel: () => api.post('/import/repairshopr/cancel'),
  nuclear: (data: { api_key: string; subdomain: string; confirm: string; password: string }) => api.post('/import/repairshopr/nuclear', data),
};

// ==================== MyRepairApp Import ====================
export const mraImportApi = {
  testConnection: (data: { api_key: string }) => api.post('/import/myrepairapp/test-connection', data),
  start: (data: { api_key: string; entities: string[] }) => api.post('/import/myrepairapp/start', data),
  status: () => api.get('/import/myrepairapp/status'),
  cancel: () => api.post('/import/myrepairapp/cancel'),
  nuclear: (data: { api_key: string; confirm: string; password: string }) => api.post('/import/myrepairapp/nuclear', data),
};

// ==================== Factory Wipe ====================
export const factoryWipeApi = {
  counts: () => api.get('/import/factory-wipe/counts'),
  wipe: (data: { confirm: string; password: string; categories: Record<string, boolean> }) => api.post('/import/factory-wipe', data),
};

// ==================== BlockChyp Payment Terminal ====================
export const blockchypApi = {
  status: () => api.get<{ success: boolean; data: { enabled: boolean; terminalName: string; tcEnabled: boolean; promptForTip: boolean; autoCloseTicket: boolean } }>('/blockchyp/status'),
  testConnection: (terminalName?: string) =>
    api.post<{ success: boolean; data: { success: boolean; terminalName: string; firmwareVersion?: string; error?: string } }>('/blockchyp/test-connection', { terminalName }),
  captureCheckinSignature: () =>
    api.post<{ success: boolean; data: { success: boolean; signatureFile?: string; transactionId?: string; error?: string } }>('/blockchyp/capture-checkin-signature'),
  captureSignature: (ticketId: number) =>
    api.post<{ success: boolean; data: { success: boolean; signatureFile?: string; transactionId?: string; error?: string } }>('/blockchyp/capture-signature', { ticketId }),
  processPayment: (invoiceId: number, tip?: number) =>
    api.post<{ success: boolean; data: { success: boolean; transactionId?: string; authCode?: string; amount?: string; cardType?: string; last4?: string; signatureFile?: string; error?: string; responseDescription?: string } }>('/blockchyp/process-payment', { invoiceId, tip }),
};

// ==================== Signup (public, no auth) ====================
import axios from 'axios';
const publicApi = axios.create({ baseURL: '/api/v1', headers: { 'Content-Type': 'application/json' } });

export const signupApi = {
  checkSlug: (slug: string) =>
    publicApi.get<{ success: boolean; data: { available: boolean; reason: string | null } }>(`/signup/check-slug/${encodeURIComponent(slug)}`),
  createShop: (data: { slug: string; shop_name: string; admin_email: string; admin_password: string }) =>
    publicApi.post<{ success: boolean; data: { tenant_id: number; slug: string; url: string; message: string }; message?: string }>('/signup', data),
};
