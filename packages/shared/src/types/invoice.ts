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
  /**
   * Booked as a deposit ledger entry (server validates against ['payment','deposit']
   * — invoices.routes.ts:687-689). Defaults to 'payment' on the server when omitted.
   * Added 2026-04-24 (WEB-FN-002): the server already supported this field but the
   * shared input type omitted it, so the deposit-vs-payment split was unselectable
   * from the web client.
   */
  payment_type?: 'payment' | 'deposit';
  /**
   * Optional cross-check against the invoice's customer (server reads it at
   * invoices.routes.ts:674-679 to reject mis-routed payments). Pass it whenever
   * the caller already has the customer id loaded — server returns 400 on mismatch.
   */
  customer_id?: number;
}
