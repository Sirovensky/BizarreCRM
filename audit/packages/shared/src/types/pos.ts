export interface PosTransaction {
  id: number;
  invoice_id: number | null;
  customer_id: number | null;
  total: number;
  payment_method: string;
  user_id: number;
  register_id: string | null;
  created_at: string;
}

export interface CashRegisterEntry {
  id: number;
  type: 'cash_in' | 'cash_out';
  amount: number;
  reason: string | null;
  user_id: number;
  created_at: string;
}
