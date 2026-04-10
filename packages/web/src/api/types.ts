/** Typed request body interfaces for the API layer.
 *  Each interface matches the fields read by the corresponding backend route handler. */

// ─── Customers ───────────────────────────────────────────────────────────────

export interface ImportCustomerItem {
  first_name: string;
  last_name?: string;
  email?: string;
  phone?: string;
  mobile?: string;
  address1?: string;
  address2?: string;
  city?: string;
  state?: string;
  postcode?: string;
  country?: string;
  organization?: string;
  tax_number?: string;
  customer_group_id?: number;
  comments?: string;
  source?: string;
  tags?: string;
}

// ─── Tickets ─────────────────────────────────────────────────────────────────

export interface AddDeviceInput {
  device_name: string;
  device_type?: string;
  imei?: string;
  serial?: string;
  color?: string;
  network?: string;
  service_id?: number;
  price?: number;
  warranty?: string;
  warranty_days?: number;
}

export interface UpdateDeviceInput {
  device_name?: string;
  device_type?: string;
  imei?: string;
  serial?: string;
  color?: string;
  network?: string;
  service_id?: number;
  price?: number;
  warranty?: string;
  warranty_days?: number;
}

export interface AddPartInput {
  inventory_item_id?: number;
  name?: string;
  price: number;
  quantity?: number;
  status?: string;
  supplier_url?: string;
}

export interface ChecklistItem {
  id?: number;
  label: string;
  is_checked?: boolean;
  sort_order?: number;
}

// ─── Invoices ────────────────────────────────────────────────────────────────

export interface UpdateInvoiceInput {
  notes?: string;
  due_date?: string;
  due_on?: string;
  discount?: number;
  discount_reason?: string;
  payment_plan?: {
    installments?: number;
    frequency?: 'weekly' | 'monthly';
    amount_per?: number;
  };
}

// ─── Inventory ───────────────────────────────────────────────────────────────

export interface ImportInventoryItem {
  name: string;
  description?: string;
  item_type?: 'product' | 'part' | 'service';
  category?: string;
  manufacturer?: string;
  sku?: string;
  cost_price: number;
  retail_price: number;
  in_stock?: number;
  reorder_level?: number;
  supplier_id?: number;
}

export interface CreateSupplierInput {
  name: string;
  contact_name?: string;
  email?: string;
  phone?: string;
  address?: string;
  website?: string;
  rating?: number;
  notes?: string;
}

export interface UpdateSupplierInput {
  name?: string;
  contact_name?: string;
  email?: string;
  phone?: string;
  address?: string;
  website?: string;
  rating?: number;
  notes?: string;
}

export interface ListPurchaseOrdersParams {
  page?: number;
  pagesize?: number;
  status?: string;
  supplier_id?: number;
}

export interface CreatePurchaseOrderInput {
  supplier_id: number;
  items: Array<{
    inventory_item_id: number;
    quantity: number;
    cost_price: number;
  }>;
  notes?: string;
}

export interface ReceivePurchaseOrderInput {
  items?: Array<{
    id: number;
    quantity_received: number;
  }>;
  notes?: string;
}

// ─── Settings ────────────────────────────────────────────────────────────────

export interface CreateStatusInput {
  name: string;
  color?: string;
  sort_order?: number;
  is_default?: boolean;
  is_closed?: boolean;
  is_cancelled?: boolean;
  notify_customer?: boolean;
  notification_template?: string;
}

export interface UpdateStatusInput {
  name?: string;
  color?: string;
  sort_order?: number;
  is_default?: boolean;
  is_closed?: boolean;
  is_cancelled?: boolean;
  notify_customer?: boolean;
  notification_template?: string;
}

export interface UpdateStoreInput {
  store_name?: string;
  address?: string;
  phone?: string;
  email?: string;
  timezone?: string;
  currency?: string;
  receipt_header?: string;
  receipt_footer?: string;
  logo_url?: string;
  business_hours?: string;
  store_logo?: string;
}

export interface CreateTaxClassInput {
  name: string;
  rate: number;
  is_default?: number;
}

export interface UpdateTaxClassInput {
  name?: string;
  rate?: number;
  is_default?: number;
}

export interface CreatePaymentMethodInput {
  name: string;
  sort_order?: number;
}

export interface CreateReferralSourceInput {
  name: string;
  sort_order?: number;
}

export interface CreateUserInput {
  username: string;
  email?: string;
  password?: string;
  first_name: string;
  last_name: string;
  role?: 'admin' | 'technician' | 'manager';
  pin?: string;
}

export interface UpdateUserInput {
  email?: string;
  first_name?: string;
  last_name?: string;
  role?: string;
  pin?: string;
  password?: string;
  is_active?: number | boolean;
}

export interface UpdateNotificationTemplateInput {
  subject?: string;
  body?: string;
  sms_message?: string;
  template_vars?: Record<string, string>;
}

export interface CreateChecklistTemplateInput {
  name: string;
  category?: string;
  items?: Array<{
    label: string;
    sort_order?: number;
  }>;
}

export interface UpdateChecklistTemplateInput {
  name?: string;
  category?: string;
  items?: Array<{
    label: string;
    sort_order?: number;
  }>;
}

// ─── Reports ─────────────────────────────────────────────────────────────────

export interface ReportParams {
  from_date?: string;
  to_date?: string;
  employee_id?: number;
  category?: string;
  status?: string;
  group_by?: string;
}

// ─── SMS ─────────────────────────────────────────────────────────────────────

export interface CreateSmsTemplateInput {
  name: string;
  template: string;
  template_vars?: string[];
  category?: string;
}

export interface UpdateSmsTemplateInput {
  name?: string;
  template?: string;
  template_vars?: string[];
  category?: string;
}

// ─── POS ─────────────────────────────────────────────────────────────────────

export interface PosTransactionInput {
  customer_id?: number;
  items: Array<{
    inventory_item_id: number;
    quantity: number;
    unit_price?: number;
  }>;
  payment_method?: string;
  payment_amount?: number;
  payments?: Array<{
    method: string;
    amount: number;
  }>;
  notes?: string;
  discount?: number;
  tip?: number;
}

export interface GetTransactionsParams {
  page?: number;
  pagesize?: number;
  from_date?: string;
  to_date?: string;
}

export interface CheckoutWithTicketInput {
  mode?: string;
  ticket_id?: number;
  existing_ticket_id?: number | null;
  customer_id?: number | null;
  signature_file?: string;
  ticket?: Record<string, unknown>;
  product_items?: unknown[];
  misc_items?: unknown[];
  payment_method?: string | null;
  payment_amount?: number;
  payments?: Array<{ method: string; amount: number; reference?: string }>;
  tip?: number;
  discount?: number;
  notes?: string;
}

// ─── Catalog ─────────────────────────────────────────────────────────────────

export interface BulkImportItem {
  name: string;
  sku?: string;
  cost_price?: number;
  retail_price?: number;
  category?: string;
  manufacturer?: string;
}

// ─── Leads ───────────────────────────────────────────────────────────────────

export interface CreateLeadInput {
  customer_id?: number;
  first_name: string;
  last_name?: string;
  email?: string;
  phone?: string;
  zip_code?: string;
  address?: string;
  status?: string;
  referred_by?: string;
  assigned_to?: number;
  source?: string;
  notes?: string;
  devices?: Array<{
    device_name?: string;
    repair_type?: string;
    service_type?: string;
    service_id?: number;
    price?: number;
    tax?: number;
    problem?: string;
    customer_notes?: string;
    security_code?: string;
  }>;
}

export interface UpdateLeadInput {
  first_name?: string;
  last_name?: string;
  email?: string;
  phone?: string;
  zip_code?: string;
  address?: string;
  status?: string;
  referred_by?: string;
  assigned_to?: number;
  source?: string;
  notes?: string;
}

export interface CreateAppointmentInput {
  lead_id?: number;
  start_time: string;
  end_time?: string;
  notes?: string;
  assigned_to?: number;
}

export interface UpdateAppointmentInput {
  start_time?: string;
  end_time?: string;
  notes?: string;
  assigned_to?: number;
}

// ─── Estimates ───────────────────────────────────────────────────────────────

export interface CreateEstimateInput {
  customer_id: number;
  status?: string;
  discount?: number;
  notes?: string;
  valid_until?: string;
  line_items?: Array<{
    inventory_item_id?: number;
    description?: string;
    quantity?: number;
    unit_price?: number;
    tax_amount?: number;
  }>;
}

export interface UpdateEstimateInput {
  status?: string;
  discount?: number;
  notes?: string;
  valid_until?: string;
  line_items?: Array<{
    inventory_item_id?: number;
    description?: string;
    quantity?: number;
    unit_price?: number;
    tax_amount?: number;
  }>;
}

// ─── Preferences ─────────────────────────────────────────────────────────────

export type PreferenceValue = string | number | boolean | Record<string, unknown> | unknown[] | null;

// ─── Repair Pricing ──────────────────────────────────────────────────────────

export interface CreateServiceInput {
  name: string;
  category?: string;
  description?: string;
  default_price?: number;
}

export interface UpdateServiceInput {
  name?: string;
  category?: string;
  description?: string;
  default_price?: number;
}

export interface CreateRepairPriceInput {
  device_model_id: number;
  repair_service_id: number;
  base_price: number;
  category?: string;
}

export interface UpdateRepairPriceInput {
  device_model_id?: number;
  repair_service_id?: number;
  base_price?: number;
  category?: string;
}

export interface AddGradeInput {
  grade: string;
  price_modifier?: number;
  description?: string;
}

export interface UpdateGradeInput {
  grade?: string;
  price_modifier?: number;
  description?: string;
}
