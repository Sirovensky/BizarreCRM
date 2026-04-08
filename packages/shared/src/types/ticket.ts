export interface TicketStatus {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  is_default: boolean;
  is_closed: boolean;
  is_cancelled: boolean;
  notify_customer: boolean;
  notification_template: string | null;
  created_at: string;
}

export interface Ticket {
  id: number;
  order_id: string;
  customer_id: number;
  status_id: number;
  assigned_to: number | null;
  subtotal: number;
  discount: number;
  discount_reason: string | null;
  total_tax: number;
  total: number;
  source: string | null;
  referral_source: string | null;
  signature: string | null;
  labels: string[];
  due_on: string | null;
  invoice_id: number | null;
  estimate_id: number | null;
  is_deleted: boolean;
  created_by: number;
  created_at: string;
  updated_at: string;
  // Joined
  customer?: { id: number; first_name: string; last_name: string; phone: string | null; mobile: string | null; email: string | null; organization: string | null };
  status?: TicketStatus;
  assigned_user?: { id: number; first_name: string; last_name: string };
  devices?: TicketDevice[];
  notes?: TicketNote[];
  history?: TicketHistory[];
}

export interface TicketDevice {
  id: number;
  ticket_id: number;
  device_name: string;
  device_type: string | null;
  imei: string | null;
  serial: string | null;
  security_code: string | null;
  color: string | null;
  network: string | null;
  status_id: number | null;
  assigned_to: number | null;
  service_id: number | null;
  price: number;
  line_discount: number;
  tax_amount: number;
  tax_class_id: number | null;
  tax_inclusive: boolean;
  total: number;
  warranty: boolean;
  warranty_days: number;
  due_on: string | null;
  collected_date: string | null;
  device_location: string | null;
  additional_notes: string | null;
  pre_conditions: string[] | null;
  post_conditions: string[] | null;
  device_model_id: number | null;
  loaner_device_id: number | null;
  created_at: string;
  updated_at: string;
  // Joined
  status?: TicketStatus;
  assigned_user?: { id: number; first_name: string; last_name: string };
  service?: { id: number; name: string };
  parts?: TicketDevicePart[];
  photos?: TicketPhoto[];
  checklist?: TicketChecklist | null;
}

export interface TicketDevicePart {
  id: number;
  ticket_device_id: number;
  inventory_item_id: number;
  quantity: number;
  price: number;
  warranty: boolean;
  serial: string | null;
  status: string | null;
  catalog_item_id: number | null;
  supplier_url: string | null;
  item_name?: string;
  item_sku?: string;
}

export interface TicketPhoto {
  id: number;
  ticket_device_id: number;
  type: 'pre' | 'post';
  file_path: string;
  caption: string | null;
  created_at: string;
}

export interface TicketNote {
  id: number;
  ticket_id: number;
  ticket_device_id: number | null;
  user_id: number;
  type: 'internal' | 'diagnostic' | 'email';
  content: string;
  is_flagged: boolean;
  parent_id: number | null;
  created_at: string;
  user?: { id: number; first_name: string; last_name: string; avatar_url: string | null };
}

export interface TicketHistory {
  id: number;
  ticket_id: number;
  user_id: number | null;
  action: string;
  description: string;
  old_value: string | null;
  new_value: string | null;
  created_at: string;
  user?: { id: number; first_name: string; last_name: string };
}

export interface TicketChecklist {
  id: number;
  ticket_device_id: number;
  checklist_template_id: number;
  items: ChecklistItem[];
  created_at: string;
  updated_at: string;
}

export interface ChecklistItem {
  label: string;
  required: boolean;
  completed: boolean;
  completed_by: string | null;
  completed_at: string | null;
}

export interface ChecklistTemplate {
  id: number;
  name: string;
  device_type: string | null;
  items: { label: string; required: boolean }[];
  created_at: string;
}

export interface CreateTicketInput {
  customer_id: number;
  status_id?: number;
  assigned_to?: number;
  source?: string;
  referral_source?: string;
  labels?: string[];
  due_on?: string;
  discount?: number;
  discount_reason?: string;
  devices: CreateTicketDeviceInput[];
}

export interface CreateTicketDeviceInput {
  device_name: string;
  device_type?: string;
  imei?: string;
  serial?: string;
  security_code?: string;
  color?: string;
  network?: string;
  status_id?: number;
  assigned_to?: number;
  service_id?: number;
  price?: number;
  line_discount?: number;
  tax_class_id?: number;
  tax_inclusive?: boolean;
  warranty?: boolean;
  warranty_days?: number;
  due_on?: string;
  device_location?: string;
  additional_notes?: string;
  pre_conditions?: string[];
  parts?: { inventory_item_id: number; quantity: number; price: number; warranty?: boolean; serial?: string }[];
}
