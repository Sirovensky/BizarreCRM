export interface User {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: 'admin' | 'manager' | 'technician' | 'cashier';
  avatar_url: string | null;
  is_active: boolean;
  permissions: Record<string, boolean> | null;
  created_at: string;
  updated_at: string;
}

export interface ClockEntry {
  id: number;
  user_id: number;
  clock_in: string;
  clock_out: string | null;
  total_hours: number | null;
  notes: string | null;
  user?: { id: number; first_name: string; last_name: string };
}

export interface Commission {
  id: number;
  user_id: number;
  ticket_id: number | null;
  invoice_id: number | null;
  amount: number;
  type: 'repair' | 'sale';
  created_at: string;
}

export interface LoginInput {
  username: string;
  password: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  user: User;
}
