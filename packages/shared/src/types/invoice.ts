export interface Invoice {
  id: number;
  order_id: string;
  ticket_id: number | null;
  customer_id: number;
  status: 'draft' | 'unpaid' | 'partial' | 'paid' | 'refunded' | 'void';
  subtotal: number;
  discount: number;
  discount_reason: string | null;
  total_tax: number;
  total: number;
  amount_paid: number;
  amount_due: number;
  due_date: string | null;
  notes: string | null;
  created_by: number;
  created_at: string;
  updated_at: string;
  // Joined
  customer?: { id: number; first_name: string; last_name: string; email: string | null; phone: string | null };
  line_items?: InvoiceLineItem[];
  payments?: Payment[];
}

export interface InvoiceLineItem {
  id: number;
  invoice_id: number;
  inventory_item_id: number | null;
  description: string;
  quantity: number;
  unit_price: number;
  line_discount: number;
  tax_amount: number;
  tax_class_id: number | null;
  total: number;
  notes: string | null;
}

export interface Payment {
  id: number;
  invoice_id: number;
  amount: number;
  method: string;
  method_detail: string | null;
  transaction_id: string | null;
  notes: string | null;
  user_id: number;
  created_at: string;
  user?: { id: number; first_name: string; last_name: string };
}

export interface CreateInvoiceInput {
  ticket_id?: number;
  customer_id: number;
  due_date?: string;
  discount?: number;
  discount_reason?: string;
  notes?: string;
  line_items: {
    inventory_item_id?: number;
    description: string;
    quantity: number;
    unit_price: number;
    line_discount?: number;
    tax_class_id?: number;
    notes?: string;
  }[];
}

export interface RecordPaymentInput {
  amount: number;
  method: string;
  method_detail?: string;
  transaction_id?: string;
  notes?: string;
}
