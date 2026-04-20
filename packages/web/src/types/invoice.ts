// Minimal typed shape for the GET /invoices/:id response.
// Server handler: invoices.routes.ts getInvoiceDetail() →
//   res.json({ success: true, data: { ...invoice_row, line_items, payments, deposit_invoices } })
// The flat invoice object is returned directly — no extra `.invoice` nesting.

export interface InvoiceLineItem {
  id: number;
  invoice_id: number;
  description: string;
  quantity: number;
  unit_price: number;
  tax_amount: number;
  total: number;
  notes?: string | null;
  inventory_item_id?: number | null;
}

export interface InvoicePayment {
  id: number;
  invoice_id: number;
  amount: number;
  method: string;
  method_detail?: string | null;
  notes?: string | null;
  created_at: string;
  recorded_by?: string | null;
}

export interface InvoiceDepositRef {
  id: number;
  order_id: string;
  is_deposit: number;
  deposit_amount: number | null;
  total: number;
  amount_paid: number;
  status: string;
}

export interface InvoiceDetail {
  id: number;
  order_id: string;
  customer_id: number;
  ticket_id?: number | null;
  status: string;
  subtotal: number;
  discount: number;
  discount_reason?: string | null;
  total_tax: number;
  total: number;
  amount_paid: number;
  amount_due: number;
  notes?: string | null;
  created_at: string;
  updated_at: string;
  // Joined customer fields
  first_name?: string | null;
  last_name?: string | null;
  organization?: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  created_by_name?: string | null;
  // Related collections
  line_items: InvoiceLineItem[];
  payments: InvoicePayment[];
  deposit_invoices: InvoiceDepositRef[];
}
