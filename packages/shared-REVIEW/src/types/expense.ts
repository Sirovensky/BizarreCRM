export interface Expense {
  id: number;
  category: string;
  amount: number;
  description: string | null;
  date: string;
  receipt_path: string | null;
  user_id: number;
  created_at: string;
}
