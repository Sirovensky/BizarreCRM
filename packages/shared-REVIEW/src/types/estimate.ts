export interface Estimate {
  id: number;
  order_id: string;
  customer_id: number;
  status: 'draft' | 'sent' | 'approved' | 'rejected' | 'converted';
  subtotal: number;
  discount: number;
  total_tax: number;
  total: number;
  valid_until: string | null;
  notes: string | null;
  approval_token: string | null;
  approved_at: string | null;
  converted_ticket_id: number | null;
  created_by: number;
  created_at: string;
  updated_at: string;
  customer?: { id: number; first_name: string; last_name: string; email: string | null; phone: string | null };
  line_items?: EstimateLineItem[];
}

export interface EstimateLineItem {
  id: number;
  estimate_id: number;
  inventory_item_id: number | null;
  description: string;
  quantity: number;
  unit_price: number;
  tax_amount: number;
  total: number;
}

export interface CreateEstimateInput {
  customer_id: number;
  valid_until?: string;
  discount?: number;
  notes?: string;
  line_items: {
    inventory_item_id?: number;
    description: string;
    quantity: number;
    unit_price: number;
    tax_class_id?: number;
  }[];
}
