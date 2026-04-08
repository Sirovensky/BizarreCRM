import axios from 'axios';

const portalClient = axios.create({
  baseURL: '/api/v1/portal',
  headers: { 'Content-Type': 'application/json' },
});

// Attach portal token to every request
portalClient.interceptors.request.use((config) => {
  const token = sessionStorage.getItem('portal_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export interface QuickTrackResponse {
  token: string;
  ticket: TicketDetail;
}

export interface LoginResponse {
  token: string;
  customer: { first_name: string };
  scope: 'full';
}

export interface VerifyResponse {
  valid: boolean;
  customer_first_name?: string;
  scope?: 'ticket' | 'full';
  ticket_id?: number;
  has_account?: boolean;
}

export interface DashboardData {
  customer: { first_name: string; last_name: string };
  total_tickets: number;
  open_tickets: number;
  pending_estimates: number;
  outstanding_invoices: number;
  outstanding_balance: number;
  store: Record<string, string>;
}

export interface TicketSummary {
  id: number;
  order_id: string;
  status: { name: string; color: string; is_closed: boolean };
  devices: { name: string; type: string }[];
  due_on: string | null;
  created_at: string;
  updated_at: string;
}

export interface TicketDetail {
  id: number;
  order_id: string;
  status: { name: string; color: string; is_closed: boolean };
  customer_first_name: string | null;
  due_on: string | null;
  created_at: string;
  updated_at: string;
  checkin_notes: string | null;
  devices: {
    id: number;
    name: string;
    type: string;
    service: string | null;
    imei: string | null;
    serial: string | null;
    status: string | null;
    price: number | null;
    total: number | null;
    due_on: string | null;
    notes: string | null;
  }[];
  timeline: {
    type: string;
    description: string;
    detail?: string;
    created_at: string;
  }[];
  messages: {
    id: number;
    content: string;
    type: string;
    created_at: string;
    author: string | null;
  }[];
  invoice: {
    order_id: string;
    status: string;
    subtotal: number;
    discount: number;
    tax: number;
    total: number;
    amount_paid: number;
    amount_due: number;
    line_items: { description: string; quantity: number; unit_price: number; discount: number; tax: number; total: number }[];
    payments: { amount: number; method: string; date: string }[];
  } | null;
  feedback: { rating: number; comment: string | null; responded_at: string } | null;
  store: Record<string, string>;
}

export interface EstimateSummary {
  id: number;
  order_id: string;
  status: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  valid_until: string | null;
  notes: string | null;
  created_at: string;
  approved_at: string | null;
  line_items: { description: string; quantity: number; unit_price: number; discount: number; tax: number; total: number }[];
}

export interface InvoiceSummary {
  id: number;
  order_id: string;
  status: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  amount_paid: number;
  amount_due: number;
  created_at: string;
  ticket_order_id: string | null;
}

export interface InvoiceDetail extends InvoiceSummary {
  line_items: { description: string; quantity: number; unit_price: number; discount: number; tax: number; total: number }[];
  payments: { amount: number; method: string; date: string }[];
}

export interface EmbedConfig {
  name: string;
  phone: string;
  address: string;
  logo: string | null;
  hours: string;
}

// ---- API Functions ----

export async function quickTrack(order_id: string, phone_last4: string): Promise<QuickTrackResponse> {
  const res = await portalClient.post('/quick-track', { order_id, phone_last4 });
  return res.data.data;
}

export async function portalLogin(phone: string, pin: string): Promise<LoginResponse> {
  const res = await portalClient.post('/login', { phone, pin });
  return res.data.data;
}

export async function sendVerificationCode(phone: string): Promise<void> {
  await portalClient.post('/register/send-code', { phone });
}

export async function verifyAndRegister(phone: string, code: string, pin: string): Promise<LoginResponse> {
  const res = await portalClient.post('/register/verify', { phone, code, pin });
  return res.data.data;
}

export async function verifySession(token: string): Promise<VerifyResponse> {
  const res = await portalClient.get('/verify', {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.data.data;
}

export async function portalLogout(): Promise<void> {
  await portalClient.post('/logout');
}

export async function getDashboard(): Promise<DashboardData> {
  const res = await portalClient.get('/dashboard');
  return res.data.data;
}

export async function getTickets(): Promise<TicketSummary[]> {
  const res = await portalClient.get('/tickets');
  return res.data.data;
}

export async function getTicketDetail(id: number): Promise<TicketDetail> {
  const res = await portalClient.get(`/tickets/${id}`);
  return res.data.data;
}

export async function submitFeedback(ticketId: number, rating: number, comment?: string): Promise<void> {
  await portalClient.post(`/tickets/${ticketId}/feedback`, { rating, comment });
}

export async function getEstimates(): Promise<EstimateSummary[]> {
  const res = await portalClient.get('/estimates');
  return res.data.data;
}

export async function approveEstimate(id: number): Promise<void> {
  await portalClient.post(`/estimates/${id}/approve`);
}

export async function getInvoices(): Promise<InvoiceSummary[]> {
  const res = await portalClient.get('/invoices');
  return res.data.data;
}

export async function getInvoiceDetail(id: number): Promise<InvoiceDetail> {
  const res = await portalClient.get(`/invoices/${id}`);
  return res.data.data;
}

export async function getEmbedConfig(): Promise<EmbedConfig> {
  const res = await portalClient.get('/embed/config');
  return res.data.data;
}
