// @audit-fixed: hoisted from a mid-file `import axios from 'axios';` (originally
// near line 886) up to the top with the rest of the imports. Mid-file imports
// are valid ESM but break tree-shaking heuristics in some bundlers and confuse
// linters / refactor tools.
import axios from 'axios';
import { api, superAdminClient } from './client';
import type {
  Customer, CreateCustomerInput, UpdateCustomerInput, CustomerAsset,
  Ticket, CreateTicketInput, TicketStatus, TicketNote,
  Invoice, CreateInvoiceInput, RecordPaymentInput,
  InventoryItem, CreateInventoryInput,
  User, AuthTokens,
} from '@bizarre-crm/shared';
import type {
  ImportCustomerItem, AddDeviceInput, UpdateDeviceInput, AddPartInput, ChecklistItem,
  UpdateInvoiceInput, ImportInventoryItem, CreateSupplierInput, UpdateSupplierInput,
  ListPurchaseOrdersParams, CreatePurchaseOrderInput, ReceivePurchaseOrderInput,
  CreateStatusInput, UpdateStatusInput, UpdateStoreInput, CreateTaxClassInput, UpdateTaxClassInput,
  CreatePaymentMethodInput, CreateReferralSourceInput, CreateUserInput, UpdateUserInput,
  UpdateNotificationTemplateInput, CreateChecklistTemplateInput, UpdateChecklistTemplateInput,
  ReportParams, CreateSmsTemplateInput, UpdateSmsTemplateInput,
  PosTransactionInput, GetTransactionsParams, CheckoutWithTicketInput, BulkImportItem,
  CreateLeadInput, UpdateLeadInput, CreateAppointmentInput, UpdateAppointmentInput,
  CreateEstimateInput, UpdateEstimateInput, PreferenceValue,
  CreateServiceInput, UpdateServiceInput, CreateRepairPriceInput, UpdateRepairPriceInput,
  AddGradeInput, UpdateGradeInput,
} from './types';

// ==================== Server Info ====================
// @audit-fixed: server returns a `protocol` field too (index.ts:827) — added
// to the typed response so callers can decide between http/https without
// re-parsing `server_url`.
export const serverInfoApi = {
  get: () => api.get<{ success: boolean; data: { lan_ip: string; port: number; server_url: string; protocol: string } }>('/info'),
};

// @audit-fixed: `/auth/switch-user` returns `{ accessToken, user }` only — the
// refresh token is set as an httpOnly cookie (auth.routes.ts:972). Use a
// dedicated type instead of `AuthTokens` (which requires `refreshToken`) to
// stop the typed wrapper from promising a field that never reaches the
// caller.
interface AuthSwitchResponse {
  accessToken: string;
  user: User;
}

// ==================== Auth ====================
export const authApi = {
  setupStatus: () =>
    api.get<{ success: boolean; data: { needsSetup: boolean; isMultiTenant: boolean } }>(
      '/auth/setup-status',
    ),
  setup: (data: {
    username: string;
    password: string;
    email?: string;
    first_name?: string;
    last_name?: string;
    store_name?: string;
    setup_token?: string;
  }) => api.post<{ success: boolean; data: { message: string } }>('/auth/setup', data),
  login: (username: string, password: string) =>
    api.post<{ success: boolean; data: {
      challengeToken?: string; totpEnabled?: boolean; requires2faSetup?: boolean;
      requiresPasswordSetup?: boolean;
      trustedDevice?: boolean; accessToken?: string; refreshToken?: string; user?: User;
    }; message?: string }>('/auth/login', { username, password }),
  setPassword: (challengeToken: string, password: string) =>
    api.post<{ success: boolean; data: { challengeToken: string; message?: string }; message?: string }>('/auth/login/set-password', { challengeToken, password }),
  setup2fa: (challengeToken: string) =>
    api.post<{ success: boolean; data: { qr: string; secret: string; manualEntry: string; challengeToken?: string }; message?: string }>('/auth/login/2fa-setup', { challengeToken }),
  verify2fa: (challengeToken: string, code: string, trustDevice?: boolean) =>
    api.post<{ success: boolean; data: AuthTokens; message?: string }>('/auth/login/2fa-verify', { challengeToken, code, trustDevice }),
  logout: () => api.post('/auth/logout'),
  // @audit-fixed: server only returns `{ accessToken, user }` — refresh is in
  // an httpOnly cookie. Was previously typed as `AuthTokens` which required
  // `refreshToken: string`, a field the client never receives.
  switchUser: (pin: string) =>
    api.post<{ success: boolean; data: AuthSwitchResponse; message?: string }>('/auth/switch-user', { pin }),
  verifyPin: (pin: string) =>
    api.post<{ success: boolean; data: { verified: boolean }; message?: string }>('/auth/verify-pin', { pin }),
  // @audit-fixed: BUG. Server returns `{ success: true, data: req.user }`
  // (auth.routes.ts:1557) — i.e. the User object is the payload, not nested
  // under `data.user`. The previous typing claimed `data: { user: User }`
  // which made `LoginPage.tsx:129` (`res.data?.data?.user`) silently undefined,
  // breaking auto-login on every page reload. Type now matches the wire shape;
  // LoginPage was patched in tandem to read `res.data?.data` directly.
  me: () => api.get<{ success: boolean; data: User }>('/auth/me'),
  forgotPassword: (email: string) =>
    api.post<{ success: boolean; data: { message: string }; message?: string }>('/auth/forgot-password', { email }),
  resetPassword: (token: string, password: string) =>
    api.post<{ success: boolean; data: { message: string }; message?: string }>('/auth/reset-password', { token, password }),
};

// ==================== Customers ====================
// @audit-fixed: removed orphan `PaginatedResponse<T>` interface — it was
// declared at the top of this section but never imported, exported, or used
// as a type parameter anywhere. None of the customerApi methods below were
// even typed, so the interface contributed nothing but bundle bytes and
// reader confusion.

export const customerApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; group_id?: number; include_stats?: string; from_date?: string; to_date?: string; has_open_tickets?: string }) =>
    api.get('/customers', { params }),
  importCsv: (items: ImportCustomerItem[], skipDuplicates = true) =>
    api.post('/customers/import-csv', { items, skip_duplicates: skipDuplicates }),
  get: (id: number) =>
    api.get(`/customers/${id}`),
  create: (data: CreateCustomerInput) =>
    api.post('/customers', data),
  update: (id: number, data: UpdateCustomerInput) =>
    api.put(`/customers/${id}`, data),
  delete: (id: number, confirmName: string) =>
    api.delete(`/customers/${id}`, { data: { confirm_name: confirmName } }),
  search: (q: string) =>
    api.get('/customers/search', { params: { q } }),
  // @audit-fixed: orphan server route. `GET /customers/repeat` exists at
  // customers.routes.ts:929 (3+ tickets in last N months) but had no client
  // wrapper — pages had to hand-roll axios calls.
  repeat: (params?: { min_tickets?: number; months?: number }) =>
    api.get('/customers/repeat', { params }),
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
    status_id?: number | string; status_group?: string; assigned_to?: number | 'me';
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
  addDevice: (id: number, data: AddDeviceInput) =>
    api.post(`/tickets/${id}/devices`, data),
  updateDevice: (deviceId: number, data: UpdateDeviceInput) =>
    api.put(`/tickets/devices/${deviceId}`, data),
  deleteDevice: (deviceId: number) =>
    api.delete(`/tickets/devices/${deviceId}`),
  addParts: (deviceId: number, data: AddPartInput) =>
    api.post(`/tickets/devices/${deviceId}/parts`, data),
  quickAddPart: (deviceId: number, data: { name: string; price: number; quantity?: number }) =>
    api.post(`/tickets/devices/${deviceId}/quick-add-part`, data),
  removePart: (partId: number) =>
    api.delete(`/tickets/devices/parts/${partId}`),
  updatePart: (partId: number, data: { status?: string; catalog_item_id?: number; supplier_url?: string }) =>
    api.patch(`/tickets/devices/parts/${partId}`, data),
  updateChecklist: (deviceId: number, items: ChecklistItem[]) =>
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
    keyword?: string; status_id?: number | string; status_group?: string; assigned_to?: number | 'me';
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
  // Merge tickets (admin only)
  merge: (keep_id: number, merge_id: number) =>
    api.post('/tickets/merge', { keep_id, merge_id }),
  // Linked/related tickets
  link: (id: number, data: { linked_ticket_id: number; link_type?: string }) =>
    api.post(`/tickets/${id}/link`, data),
  getLinks: (id: number) => api.get(`/tickets/${id}/links`),
  deleteLink: (linkId: number) => api.delete(`/tickets/links/${linkId}`),
  // Clone as warranty case
  cloneWarranty: (id: number) => api.post(`/tickets/${id}/clone-warranty`),
  // AUDIT-WEB-002: mint a scoped short-lived photo-upload token for the QR URL.
  // Returns { token: string } — 30-minute JWT scoped to one ticket+device.
  getPhotoUploadToken: (ticketId: number, deviceId: number) =>
    api.post<{ success: boolean; data: { token: string } }>(
      `/tickets/${ticketId}/devices/${deviceId}/photo-upload-token`,
    ),
};

// ==================== Invoices ====================
import type { InvoiceDetail } from '@/types/invoice';

export const invoiceApi = {
  list: (params?: { page?: number; pagesize?: number; status?: string; from_date?: string; to_date?: string; keyword?: string; customer_id?: number }) =>
    api.get('/invoices', { params }),
  stats: () => api.get('/invoices/stats'),
  // Server returns { success: true, data: <flat invoice + line_items + payments + deposit_invoices> }
  get: (id: number) => api.get<{ success: boolean; data: InvoiceDetail }>(`/invoices/${id}`),
  // DA-6: send an idempotency key so a double-click or flaky network can't
  // create two invoices for the same ticket. Server middleware (idempotent)
  // caches responses keyed on (user, url, key) for 5 minutes.
  create: (data: CreateInvoiceInput) =>
    api.post('/invoices', data, {
      headers: {
        'X-Idempotency-Key':
          (globalThis.crypto?.randomUUID?.() ??
            `inv-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`),
      },
    }),
  update: (id: number, data: UpdateInvoiceInput) => api.put(`/invoices/${id}`, data),
  recordPayment: (id: number, data: RecordPaymentInput) =>
    api.post(`/invoices/${id}/payments`, data, {
      headers: {
        'X-Idempotency-Key':
          (globalThis.crypto?.randomUUID?.() ??
            `pay-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`),
      },
    }),
  void: (id: number) => api.post(`/invoices/${id}/void`),
  createCreditNote: (id: number, data: { amount: number; reason: string }) =>
    api.post(`/invoices/${id}/credit-note`, data),
  bulkAction: (action: string, invoiceIds: number[]) =>
    api.post('/invoices/bulk-action', { action, invoice_ids: invoiceIds }),
};

// @audit-fixed: write-safe payload for `PUT /inventory/:id`. The previous
// `Partial<InventoryItem>` allowed callers to pass joined fields like
// `supplier`, `serials`, `group_prices`, plus immutable bookkeeping
// (`id`, `created_at`, `updated_at`) — none of which the route reads
// (inventory.routes.ts:896). Type drift hid silent no-op writes.
export interface UpdateInventoryInput {
  name?: string;
  description?: string;
  item_type?: 'product' | 'part' | 'service';
  category?: string;
  manufacturer?: string;
  device_type?: string;
  sku?: string;
  upc?: string;
  cost_price?: number;
  retail_price?: number;
  reorder_level?: number;
  stock_warning?: number;
  tax_class_id?: number;
  tax_inclusive?: boolean | number;
  is_serialized?: boolean | number;
  supplier_id?: number;
  image_url?: string;
  location?: string;
  shelf?: string;
  bin?: string;
  cost_locked?: 0 | 1;
}

// ==================== Inventory ====================
export const inventoryApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; item_type?: string; category?: string; low_stock?: boolean; supplier_id?: number; manufacturer?: string; min_price?: number; max_price?: number; hide_out_of_stock?: boolean }) =>
    api.get('/inventory', { params }),
  manufacturers: () => api.get('/inventory/manufacturers'),
  importCsv: (items: ImportInventoryItem[]) => api.post('/inventory/import-csv', { items }),
  bulkAction: (item_ids: number[], action: string, value?: string | number) =>
    api.post('/inventory/bulk-action', { item_ids, action, value }),
  get: (id: number) => api.get(`/inventory/${id}`),
  create: (data: CreateInventoryInput) => api.post('/inventory', data),
  // @audit-fixed: switched from `Partial<InventoryItem>` to a write-safe DTO
  // (UpdateInventoryInput, defined above this object). See note on the
  // interface for the rationale.
  update: (id: number, data: UpdateInventoryInput) => api.put(`/inventory/${id}`, data),
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
  createSupplier: (data: CreateSupplierInput) => api.post('/inventory/suppliers', data),
  updateSupplier: (id: number, data: UpdateSupplierInput) => api.put(`/inventory/suppliers/${id}`, data),
  // @audit-fixed: orphan server route. `DELETE /inventory/suppliers/:id`
  // exists at inventory.routes.ts:1101 (soft-delete) but had no client
  // wrapper. Suppliers UI was hand-rolling axios for delete.
  deleteSupplier: (id: number) => api.delete(`/inventory/suppliers/${id}`),
  // Purchase Orders
  listPurchaseOrders: (params?: ListPurchaseOrdersParams) => api.get('/inventory/purchase-orders/list', { params }),
  getPurchaseOrder: (id: number) => api.get(`/inventory/purchase-orders/${id}`),
  createPurchaseOrder: (data: CreatePurchaseOrderInput) => api.post('/inventory/purchase-orders', data),
  // @audit-fixed: orphan server route. `PUT /inventory/purchase-orders/:id`
  // exists at inventory.routes.ts:1263 but had no client wrapper.
  updatePurchaseOrder: (id: number, data: { notes?: string; expected_date?: string; status?: string }) =>
    api.put(`/inventory/purchase-orders/${id}`, data),
  receivePurchaseOrder: (id: number, data: ReceivePurchaseOrderInput) => api.post(`/inventory/purchase-orders/${id}/receive`, data),
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

/** Shape returned by GET /settings/statuses: { success: true, data: TicketStatus[] } */
export interface StatusListResponse {
  success: boolean;
  // Matches the shared TicketStatus shape returned by the server.
  // SQLite booleans (0/1) are coerced by callers where needed.
  data: TicketStatus[];
}

export const settingsApi = {
  reconcileCogs: () => api.post('/settings/reconcile-cogs'),
  getStatuses: () => api.get<StatusListResponse>('/settings/statuses'),
  createStatus: (data: CreateStatusInput) => api.post('/settings/statuses', data),
  updateStatus: (id: number, data: UpdateStatusInput) => api.put(`/settings/statuses/${id}`, data),
  deleteStatus: (id: number) => api.delete(`/settings/statuses/${id}`),
  getStore: () => api.get('/settings/store'),
  updateStore: (data: UpdateStoreInput) => api.put('/settings/store', data),
  getTaxClasses: () => api.get('/settings/tax-classes'),
  createTaxClass: (data: CreateTaxClassInput) => api.post('/settings/tax-classes', data),
  updateTaxClass: (id: number, data: UpdateTaxClassInput) => api.put(`/settings/tax-classes/${id}`, data),
  deleteTaxClass: (id: number) => api.delete(`/settings/tax-classes/${id}`),
  getPaymentMethods: () => api.get('/settings/payment-methods'),
  createPaymentMethod: (data: CreatePaymentMethodInput) => api.post('/settings/payment-methods', data),
  getReferralSources: () => api.get('/settings/referral-sources'),
  createReferralSource: (data: CreateReferralSourceInput) => api.post('/settings/referral-sources', data),
  getUsers: () => api.get('/settings/users'),
  createUser: (data: CreateUserInput) => api.post('/settings/users', data),
  updateUser: (id: number, data: UpdateUserInput) => api.put(`/settings/users/${id}`, data),
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
  updateNotificationTemplate: (id: number, data: UpdateNotificationTemplateInput) => api.put(`/settings/notification-templates/${id}`, data),
  // Logo upload
  uploadLogo: (formData: FormData) => api.post('/settings/logo', formData, { headers: { 'Content-Type': 'multipart/form-data' } }),
  // Checklist templates
  getChecklistTemplates: () => api.get('/settings/checklist-templates'),
  createChecklistTemplate: (data: CreateChecklistTemplateInput) => api.post('/settings/checklist-templates', data),
  updateChecklistTemplate: (id: number, data: UpdateChecklistTemplateInput) => api.put(`/settings/checklist-templates/${id}`, data),
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
  // Receipt templates (migration 067)
  getReceiptTemplates: () => api.get('/settings/receipt-templates'),
  getReceiptTemplateForType: (type: 'default' | 'warranty' | 'trade_in' | 'credit_note') =>
    api.get(`/settings/receipt-templates/for-type/${type}`),
  updateReceiptTemplate: (id: number, data: { name?: string; header_text?: string; footer_text?: string }) =>
    api.put(`/settings/receipt-templates/${id}`, data),
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
  dryRun: (id: number, context?: { ticket_id?: number; invoice_id?: number; customer_id?: number }) =>
    api.post(`/automations/${id}/dry-run`, context ?? {}),
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
  sales: (params?: ReportParams) => api.get('/reports/sales', { params }),
  tickets: (params?: ReportParams) => api.get('/reports/tickets', { params }),
  employees: (params?: ReportParams) => api.get('/reports/employees', { params }),
  inventory: (params?: ReportParams) => api.get('/reports/inventory', { params }),
  tax: (params?: ReportParams) => api.get('/reports/tax', { params }),
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
  // ── Business Intelligence (audit 47) ──────────────────────────────────
  profitHero: () => api.get('/reports/profit-hero'),
  updateProfitThresholds: (data: { green: number; amber: number }) =>
    api.patch('/reports/profit-hero/thresholds', data),
  trendVsAverage: () => api.get('/reports/trend-vs-average'),
  busyHoursHeatmap: (days?: number) =>
    api.get('/reports/busy-hours-heatmap', { params: { days } }),
  techLeaderboard: (period?: 'week' | 'month' | 'quarter') =>
    api.get('/reports/tech-leaderboard', { params: { period } }),
  repeatCustomers: (limit?: number) =>
    api.get('/reports/repeat-customers', { params: { limit } }),
  dayOfWeekProfit: () => api.get('/reports/day-of-week-profit'),
  faultStatistics: () => api.get('/reports/fault-statistics'),
  cashTrapped: () => api.get('/reports/cash-trapped'),
  inventoryTurnover: () => api.get('/reports/inventory-turnover'),
  demandForecast: (months?: number) =>
    api.get('/reports/demand-forecast', { params: { months } }),
  churn: (days_inactive?: number) =>
    api.get('/reports/churn', { params: { days_inactive } }),
  overstaffing: (days?: number) =>
    api.get('/reports/overstaffing', { params: { days } }),
  taxReportPdfUrl: (from: string, to: string, jurisdiction?: string) =>
    `/api/v1/reports/tax-report.pdf?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}${jurisdiction ? `&jurisdiction=${encodeURIComponent(jurisdiction)}` : ''}`,
  partnerReportPdfUrl: (year: string | number) =>
    `/api/v1/reports/partner-report.pdf?year=${encodeURIComponent(String(year))}`,
  npsTrend: (months?: number) => api.get('/reports/nps-trend', { params: { months } }),
  referrals: () => api.get('/reports/referrals'),
  submitNps: (data: { customer_id: number; ticket_id?: number; score: number; comment?: string; channel?: string }) =>
    api.post('/reports/nps', data),
  scheduledList: () => api.get('/reports/scheduled'),
  scheduleEmail: (data: { name: string; recipient_email: string; report_type: string; cron_schedule: string; config_json?: unknown }) =>
    api.post('/reports/schedule-email', data),
  deleteScheduled: (id: number) => api.delete(`/reports/scheduled/${id}`),
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
  createTemplate: (data: CreateSmsTemplateInput) => api.post('/sms/templates', data),
  updateTemplate: (id: number, data: UpdateSmsTemplateInput) => api.put(`/sms/templates/${id}`, data),
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

export interface VoiceCall {
  id: number;
  from_number: string;
  to_number: string;
  direction: 'inbound' | 'outbound';
  duration: number | null;
  status: string;
  recording_url: string | null;
  recording_local_path: string | null;
  created_at: string;
  user_name: string | null;
  conv_phone: string | null;
  entity_type: string | null;
  entity_id: number | null;
}

export interface VoiceCallsResponse {
  success: boolean;
  data: {
    calls: VoiceCall[];
    pagination: { page: number; per_page: number; total: number; total_pages: number };
  };
}

export const voiceApi = {
  call: (data: { to: string; mode?: string; entity_type?: string; entity_id?: number }) =>
    api.post<{ success: boolean; data?: unknown; message?: string }>('/voice/call', data),
  calls: (params?: { page?: number; pagesize?: number; conv_phone?: string; entity_type?: string; entity_id?: number }) =>
    api.get<VoiceCallsResponse>('/voice/calls', { params }),
  callDetail: (id: number) => api.get(`/voice/calls/${id}`),
  /** Returns the URL path to stream/redirect to the recording. Opens in new tab. */
  recordingPath: (id: number) => `/api/v1/voice/calls/${id}/recording`,
};

// ==================== POS ====================
export const posApi = {
  products: (params?: { keyword?: string; category?: string; item_type?: string }) =>
    api.get('/pos/products', { params }),
  register: () => api.get('/pos/register'),
  cashIn: (data: { amount: number; reason?: string }) => api.post('/pos/cash-in', data),
  cashOut: (data: { amount: number; reason?: string }) => api.post('/pos/cash-out', data),
  transaction: (data: PosTransactionInput) => api.post('/pos/transaction', data),
  transactions: (params?: GetTransactionsParams) => api.get('/pos/transactions', { params }),
  checkoutWithTicket: (data: CheckoutWithTicketInput) => api.post('/pos/checkout-with-ticket', data),
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
  bulkImport: (data: { source: string; items: BulkImportItem[] }) =>
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
  create: (data: CreateLeadInput) => api.post('/leads', data),
  update: (id: number, data: UpdateLeadInput) => api.put(`/leads/${id}`, data),
  convert: (id: number) => api.post(`/leads/${id}/convert`),
  delete: (id: number) => api.delete(`/leads/${id}`),
  pipeline: () => api.get('/leads/pipeline'),
  reminders: (id: number) => api.get(`/leads/${id}/reminders`),
  createReminder: (id: number, data: { remind_at: string; note?: string }) =>
    api.post(`/leads/${id}/reminder`, data),
  appointments: (params?: { from_date?: string; to_date?: string; assigned_to?: number; status?: string }) =>
    api.get('/leads/appointments', { params }),
  createAppointment: (data: CreateAppointmentInput) => api.post('/leads/appointments', data),
  updateAppointment: (id: number, data: UpdateAppointmentInput) => api.put(`/leads/appointments/${id}`, data),
  deleteAppointment: (id: number) => api.delete(`/leads/appointments/${id}`),
};

// ==================== Estimates ====================
export const estimateApi = {
  list: (params?: { page?: number; pagesize?: number; keyword?: string; status?: string }) =>
    api.get('/estimates', { params }),
  get: (id: number) => api.get(`/estimates/${id}`),
  create: (data: CreateEstimateInput) => api.post('/estimates', data),
  update: (id: number, data: UpdateEstimateInput) => api.put(`/estimates/${id}`, data),
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

// ==================== Day-1 Onboarding (audit section 42) ====================
/**
 * Typed client for the /api/v1/onboarding endpoints. The server owns the
 * canonical shape; these helpers just wrap the HTTP verbs so page components
 * don't hand-craft URLs. See packages/server/src/routes/onboarding.routes.ts
 * for field definitions.
 */
export type OnboardingShopType =
  | 'phone_repair'
  | 'computer_repair'
  | 'watch_repair'
  | 'general_electronics';

export interface OnboardingState {
  checklist_dismissed: boolean;
  shop_type: OnboardingShopType | null;
  sample_data_loaded: boolean;
  sample_data_counts: { customers: number; tickets: number; invoices: number } | null;
  first_customer_at: string | null;
  first_ticket_at: string | null;
  first_invoice_at: string | null;
  first_payment_at: string | null;
  first_review_at: string | null;
  nudge_day3_seen: boolean;
  nudge_day5_seen: boolean;
  nudge_day7_seen: boolean;
  advanced_settings_unlocked: boolean;
  intro_video_dismissed: boolean;
  /** ISO timestamp when the onboarding row was created (i.e. tenant sign-up date). */
  created_at: string | null;
}

export type OnboardingPatchableFlag =
  | 'checklist_dismissed'
  | 'nudge_day3_seen'
  | 'nudge_day5_seen'
  | 'nudge_day7_seen'
  | 'advanced_settings_unlocked'
  | 'intro_video_dismissed';

export type OnboardingPatchBody = Partial<Record<OnboardingPatchableFlag, boolean>>;

export const onboardingApi = {
  getState: () => api.get('/onboarding/state'),
  patchState: (body: OnboardingPatchBody) => api.patch('/onboarding/state', body),
  loadSampleData: () => api.post('/onboarding/sample-data'),
  removeSampleData: () => api.delete('/onboarding/sample-data'),
  setShopType: (shop_type: OnboardingShopType) =>
    api.post('/onboarding/set-shop-type', { shop_type }),
};

// ==================== User Preferences ====================
export const preferencesApi = {
  getAll: () => api.get('/preferences'),
  get: (key: string) => api.get(`/preferences/${key}`),
  set: (key: string, value: PreferenceValue) => api.put(`/preferences/${key}`, { value }),
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
  createService: (data: CreateServiceInput) => api.post('/repair-pricing/services', data),
  updateService: (id: number, data: UpdateServiceInput) => api.put(`/repair-pricing/services/${id}`, data),
  deleteService: (id: number) => api.delete(`/repair-pricing/services/${id}`),
  // Prices
  getPrices: (params?: { device_model_id?: number; repair_service_id?: number; category?: string }) =>
    api.get('/repair-pricing/prices', { params }),
  createPrice: (data: CreateRepairPriceInput) => api.post('/repair-pricing/prices', data),
  updatePrice: (id: number, data: UpdateRepairPriceInput) => api.put(`/repair-pricing/prices/${id}`, data),
  deletePrice: (id: number) => api.delete(`/repair-pricing/prices/${id}`),
  lookup: (params: { device_model_id: number; repair_service_id: number }) =>
    api.get('/repair-pricing/lookup', { params }),
  // Grades
  addGrade: (priceId: number, data: AddGradeInput) => api.post(`/repair-pricing/prices/${priceId}/grades`, data),
  updateGrade: (id: number, data: UpdateGradeInput) => api.put(`/repair-pricing/grades/${id}`, data),
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

// ==================== Tenant Termination (PROD59) ====================
// Multi-step self-service flow. Each call is POST /admin/terminate-tenant with
// a different `action`. The server rejects mismatched typed_slug (case-
// sensitive) and rejects typed_phrase that isn't literally
// "DELETE ALL DATA PERMANENTLY".
export const tenantTerminationApi = {
  request: () =>
    api.post<{ success: boolean; data: { token: string; expires_at: string }; message?: string }>(
      '/admin/terminate-tenant',
      { action: 'request' },
    ),
  confirm: (token: string, typed_slug: string) =>
    api.post<{ success: boolean; data: { stage: string }; message?: string }>(
      '/admin/terminate-tenant',
      { action: 'confirm', token, typed_slug },
    ),
  finalize: (token: string, typed_slug: string, typed_phrase: string) =>
    api.post<{
      success: boolean;
      deletion_scheduled_at: string;
      permanent_delete_at: string;
      grace_days: number;
      message?: string;
    }>('/admin/terminate-tenant', {
      action: 'finalize',
      token,
      typed_slug,
      typed_phrase,
    }),
};

// ==================== GDPR/CCPA Data Export (PROD58) ====================
// Admin-only. Downloads a streamed JSON dump of every user-owned table in
// the tenant DB. Rate-limited to 1 export per tenant per hour server-side.
export interface DataExportStatus {
  last_export_at: string | null;
  next_allowed_in_seconds: number;
  allowed: boolean;
  rate_limit_window_seconds: number;
}

export const dataExportApi = {
  /**
   * Returns last-export timestamp + whether a new export is currently
   * allowed. Used by the Settings UI to render a countdown instead of
   * letting the user click and hit a 429.
   */
  status: () =>
    api.get<{ success: boolean; data: DataExportStatus }>('/data-export/export-all-data/status'),
  /**
   * Triggers the streamed JSON download. `responseType: 'blob'` keeps
   * axios from trying to parse a multi-megabyte payload as JSON in
   * memory; the browser then materializes the Blob for saving.
   */
  downloadAll: () =>
    api.get('/data-export/export-all-data', { responseType: 'blob' }),
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
  processPayment: (invoiceId: number, tip?: number) => {
    const idempotencyKey =
      globalThis.crypto?.randomUUID?.() ??
      `bc-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    return api.post<{ success: boolean; data: { success: boolean; transactionId?: string; authCode?: string; amount?: string; cardType?: string; last4?: string; signatureFile?: string; error?: string; responseDescription?: string } }>(
      '/blockchyp/process-payment',
      { invoiceId, tip, idempotency_key: idempotencyKey },
    );
  },
  adjustTip: (transaction_id: string, new_tip: number) =>
    api.post<{ success: boolean; data: { success: boolean; code?: string; error?: string } }>(
      '/blockchyp/adjust-tip',
      { transaction_id, new_tip },
    ),
};

// ==================== Loaners ====================
export const loanerApi = {
  list: (params?: { page?: number; per_page?: number }) =>
    api.get<{ success: boolean; data: LoanerDevice[]; pagination: { page: number; per_page: number; total: number; total_pages: number } }>(
      '/loaners',
      { params },
    ),
  get: (id: number) =>
    api.get<{ success: boolean; data: LoanerDevice & { history: LoanerHistoryEntry[] } }>(`/loaners/${id}`),
  returnDevice: (id: number, body: { condition_in?: string; notes?: string }) =>
    api.post<{ success: boolean; data: { returned: boolean } }>(`/loaners/${id}/return`, body),
};

export interface LoanerDevice {
  id: number;
  name: string;
  serial: string | null;
  imei: string | null;
  condition: string;
  status: 'available' | 'loaned';
  notes: string | null;
  created_at: string;
  updated_at: string;
  is_loaned_out?: number;
  loaned_to?: string | null;
}

export interface LoanerHistoryEntry {
  id: number;
  loaner_device_id: number;
  customer_id: number;
  loaned_at: string;
  returned_at: string | null;
  condition_out: string | null;
  condition_in: string | null;
  notes: string | null;
  first_name?: string | null;
  last_name?: string | null;
  ticket_order_id?: string | null;
}

// ==================== Gift Cards ====================
export const giftCardApi = {
  list: (params?: { keyword?: string; status?: string; page?: number; per_page?: number }) =>
    api.get('/gift-cards', { params }),
  get: (id: number) => api.get(`/gift-cards/${id}`),
  issue: (data: {
    amount: number;
    customer_id?: number | null;
    recipient_name?: string | null;
    recipient_email?: string | null;
    expires_at?: string | null;
    notes?: string | null;
  }) => api.post('/gift-cards', data),
  lookup: (code: string) => api.get(`/gift-cards/lookup/${encodeURIComponent(code)}`),
  redeem: (id: number, data: { amount: number; invoice_id?: number | null }) =>
    api.post(`/gift-cards/${id}/redeem`, data),
  reload: (id: number, data: { amount: number }) =>
    api.post(`/gift-cards/${id}/reload`, data),
};

// ==================== Membership ====================
// @audit-fixed: enum drift on `discount_applies_to`. createTier had a strict
// `'labor' | 'all' | 'parts'` literal union but updateTier widened to bare
// `string`, which let callers store junk values that the server then
// COALESCE'd straight into the column. Aligned both directions to the same
// literal union.
type MembershipDiscountAppliesTo = 'labor' | 'all' | 'parts';

export const membershipApi = {
  // Tiers
  getTiers: () => api.get('/membership/tiers'),
  createTier: (data: {
    name: string; monthly_price: number; discount_pct?: number;
    discount_applies_to?: MembershipDiscountAppliesTo; benefits?: string[];
    color?: string; sort_order?: number;
  }) => api.post('/membership/tiers', data),
  updateTier: (id: number, data: {
    name?: string; monthly_price?: number; discount_pct?: number;
    discount_applies_to?: MembershipDiscountAppliesTo; benefits?: string[]; color?: string;
    sort_order?: number; is_active?: number;
  }) => api.put(`/membership/tiers/${id}`, data),
  deleteTier: (id: number) => api.delete(`/membership/tiers/${id}`),

  // Customer membership
  getCustomerMembership: (customerId: number) =>
    api.get(`/membership/customer/${customerId}`),

  // Subscriptions
  subscribe: (data: { customer_id: number; tier_id: number; blockchyp_token?: string; signature_file?: string }) =>
    api.post('/membership/subscribe', data),
  // @audit-fixed: orphan server route. `POST /membership/enroll` exists at
  // membership.routes.ts:275 (used by the customer-portal self-enroll flow)
  // but the client had no wrapper. Pages were hand-rolling axios calls.
  enroll: (data: { tier_id: number; payment_method_token?: string }) =>
    api.post('/membership/enroll', data),
  // @audit-fixed: orphan server route. `POST /membership/payment-link` exists
  // at membership.routes.ts:298 (returns a hosted-payment URL for tier
  // checkout). Adding a typed wrapper so the membership-marketing pages can
  // stop reaching for raw axios.
  paymentLink: (data: { tier_id: number; customer_id: number }) =>
    api.post('/membership/payment-link', data),
  cancel: (id: number, data?: { immediate?: boolean }) =>
    api.post(`/membership/${id}/cancel`, data || {}),
  pause: (id: number, data?: { reason?: string }) =>
    api.post(`/membership/${id}/pause`, data || {}),
  resume: (id: number) =>
    api.post(`/membership/${id}/resume`),

  // Payment history
  getPayments: (id: number) =>
    api.get(`/membership/${id}/payments`),

  // Admin: all active subscriptions
  getSubscriptions: () =>
    api.get('/membership/subscriptions'),
};

// ==================== Device Templates (audit 44.1, cross-cutting) ====================
export const deviceTemplateApi = {
  list: (params?: { category?: string; model?: string; active?: boolean }) =>
    api.get('/device-templates', { params }),
  get: (id: number) => api.get(`/device-templates/${id}`),
  create: (data: Record<string, unknown>) => api.post('/device-templates', data),
  update: (id: number, data: Record<string, unknown>) => api.put(`/device-templates/${id}`, data),
  delete: (id: number) => api.delete(`/device-templates/${id}`),
  applyToTicket: (templateId: number, ticketId: number, ticket_device_id?: number) =>
    api.post(`/device-templates/${templateId}/apply-to-ticket/${ticketId}`, { ticket_device_id }),
};

// ==================== Bench Workflow (audit 44.6, 44.10, 44.14) ====================
export const benchApi = {
  config: () => api.get('/bench/config'),
  timer: {
    current: () => api.get('/bench/timer/current'),
    start: (data: { ticket_id: number; ticket_device_id?: number; labor_rate_cents?: number }) =>
      api.post('/bench/timer/start', data),
    pause: (id: number) => api.post(`/bench/timer/${id}/pause`),
    resume: (id: number) => api.post(`/bench/timer/${id}/resume`),
    stop: (id: number, data?: { notes?: string }) => api.post(`/bench/timer/${id}/stop`, data ?? {}),
    byTicket: (ticketId: number) => api.get(`/bench/timer/by-ticket/${ticketId}`),
  },
  qc: {
    checklist: (category?: string) => api.get('/bench/qc-checklist', { params: { category } }),
    createChecklistItem: (data: { name: string; sort_order?: number; device_category?: string | null }) =>
      api.post('/bench/qc-checklist', data),
    updateChecklistItem: (id: number, data: Record<string, unknown>) =>
      api.put(`/bench/qc-checklist/${id}`, data),
    deleteChecklistItem: (id: number) => api.delete(`/bench/qc-checklist/${id}`),
    status: (ticketId: number) => api.get(`/bench/qc/status/${ticketId}`),
    signOff: (formData: FormData) =>
      api.post('/bench/qc/sign-off', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      }),
  },
  defects: {
    report: (formData: FormData) =>
      api.post('/bench/defects/report', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      }),
    stats: (days = 30) => api.get('/bench/defects/stats', { params: { days } }),
    byItem: (itemId: number) => api.get(`/bench/defects/by-item/${itemId}`),
  },
};

// ==================== CRM Enrichment (audit 49) ====================
export const crmApi = {
  healthScore: (customerId: number) => api.get(`/crm/customers/${customerId}/health-score`),
  recalculateHealth: (customerId: number) =>
    api.post(`/crm/customers/${customerId}/health-score/recalculate`),
  ltvTier: (customerId: number) => api.get(`/crm/customers/${customerId}/ltv-tier`),
  photoMementos: (customerId: number) =>
    api.get(`/crm/customers/${customerId}/photo-mementos`),
  walletPassUrl: (customerId: number) => `/api/v1/crm/customers/${customerId}/wallet-pass`,
  mintReferralCode: (customerId: number) =>
    api.post(`/crm/customers/${customerId}/referral-code`),
  createSubscription: (
    customerId: number,
    data: { plan_name: string; monthly_amount: number; next_billing_date: string; card_token?: string },
  ) => api.post(`/crm/customers/${customerId}/subscription`, data),
  listSubscriptions: (customerId: number) =>
    api.get(`/crm/customers/${customerId}/subscriptions`),

  // Customer review moderation
  listReviews: (params?: { page?: number; pagesize?: number; rating?: number; replied?: 'true' | 'false' }) =>
    api.get('/crm/reviews', { params }),
  replyToReview: (id: number, data: { response?: string; public_posted?: boolean }) =>
    api.patch(`/crm/reviews/${id}`, data),

  // Segments
  listSegments: () => api.get('/crm/segments'),
  createSegment: (data: { name: string; description?: string; rule: Record<string, unknown>; is_auto?: boolean }) =>
    api.post('/crm/segments', data),
  getSegment: (id: number) => api.get(`/crm/segments/${id}`),
  updateSegment: (id: number, data: Partial<{ name: string; description: string; rule: Record<string, unknown>; is_auto: boolean }>) =>
    api.patch(`/crm/segments/${id}`, data),
  deleteSegment: (id: number) => api.delete(`/crm/segments/${id}`),
  refreshSegment: (id: number) => api.post(`/crm/segments/${id}/refresh`),
  segmentMembers: (id: number, params?: { page?: number; pagesize?: number }) =>
    api.get(`/crm/segments/${id}/members`, { params }),
};

// ==================== Marketing Campaigns (audit 49) ====================
export const campaignsApi = {
  list: () => api.get('/campaigns'),
  get: (id: number) => api.get(`/campaigns/${id}`),
  create: (data: {
    name: string;
    type: string;
    channel: string;
    template_body: string;
    template_subject?: string;
    segment_id?: number;
    trigger_rule_json?: string;
  }) => api.post('/campaigns', data),
  update: (id: number, data: Partial<{
    name: string;
    channel: string;
    status: string;
    template_body: string;
    template_subject: string;
    segment_id: number | null;
    trigger_rule_json: string | null;
  }>) => api.patch(`/campaigns/${id}`, data),
  delete: (id: number) => api.delete(`/campaigns/${id}`),
  preview: (id: number) => api.post(`/campaigns/${id}/preview`),
  runNow: (id: number) => api.post(`/campaigns/${id}/run-now`),
  stats: (id: number) => api.get(`/campaigns/${id}/stats`),
  triggerReviewRequest: (ticketId: number) =>
    api.post('/campaigns/review-request/trigger', { ticket_id: ticketId }),
  dispatchBirthday: () => api.post('/campaigns/birthday/dispatch'),
  dispatchChurnWarning: () => api.post('/campaigns/churn-warning/dispatch'),
};

// ==================== Signup (public, no auth) ====================
// `axios` import hoisted to top of file (see @audit-fixed note there).
// @audit-fixed: extracted the duplicated `'/api/v1'` literal into a named
// constant. The original code re-typed the base URL string in two places —
// here and inside `client.ts` — making port/path migrations a search-and-
// replace footgun. The constant lives here (instead of being exported from
// client.ts) so the public axios instance stays decoupled from the
// auth-aware client.
const PUBLIC_API_BASE = '/api/v1';
const publicApi = axios.create({ baseURL: PUBLIC_API_BASE, headers: { 'Content-Type': 'application/json' } });

export const signupApi = {
  checkSlug: (slug: string) =>
    publicApi.get<{ success: boolean; data: { available: boolean; reason: string | null }; message?: string }>(`/signup/check-slug/${encodeURIComponent(slug)}`),
  createShop: (data: { slug: string; shop_name: string; admin_email: string; admin_password: string; captcha_token?: string }) =>
    publicApi.post<{ success: boolean; data: { tenant_id?: number; slug?: string; url?: string; message: string }; message?: string }>('/signup', data),
};

// ==================== Privacy / GDPR ====================
export const privacyApi = {
  eraseCustomerPii: (data: { customer_id: number; confirm_name: string }) =>
    api.post<{ success: boolean; data: { message: string }; message?: string }>('/data-export/erase-customer-pii', data),
};

// ==================== Super-Admin ====================
interface ImpersonateResponse {
  token: string;
  tenant_slug: string;
  expires_in_seconds: number;
  target_user: { id: number; username: string; role: string };
}

export interface SuperAdminTenant {
  id: number;
  slug: string;
  name: string;
  status: string;
  plan: string;
  admin_email: string;
  created_at: string;
  db_size_mb: number;
}

export const superAdminApi = {
  /** Login step 1 — returns challengeToken */
  loginPassword: (username: string, password: string) =>
    superAdminClient.post<{ success: boolean; data: { challengeToken: string; requiresPasswordSetup?: boolean; requires2faSetup?: boolean; totpEnabled?: boolean }; message?: string }>(
      '/login',
      { username, password },
    ),
  /** Login step 2 — verify TOTP, receive super-admin JWT */
  loginTotp: (challengeToken: string, code: string) =>
    superAdminClient.post<{ success: boolean; data: { token: string; admin: { id: number; username: string; email: string } }; message?: string }>(
      '/login/2fa-verify',
      { challengeToken, code },
    ),
  listTenants: (params?: { status?: string; plan?: string }) =>
    superAdminClient.get<{ success: boolean; data: { tenants: SuperAdminTenant[] } }>(
      '/tenants',
      { params },
    ),
  impersonate: (slug: string) =>
    superAdminClient.post<{ success: boolean; data: ImpersonateResponse; message?: string }>(
      `/tenants/${encodeURIComponent(slug)}/impersonate`,
    ),
};
