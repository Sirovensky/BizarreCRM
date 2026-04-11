/**
 * Portal v2 API client — talks to `/portal/api/v2/*` endpoints added by
 * portal-enrich.routes.ts. Reuses the same session token as portalApi.ts
 * (sessionStorage.portal_token).
 */
import axios from 'axios';

const client = axios.create({
  baseURL: '/portal/api/v2',
  headers: { 'Content-Type': 'application/json' },
});

client.interceptors.request.use((config) => {
  const token = sessionStorage.getItem('portal_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export interface TimelineEvent {
  action: string;
  label: string;
  from: string | null;
  to: string | null;
  at: string;
}

export interface QueueData {
  enabled: boolean;
  reason?: 'disabled' | 'phones_only';
  mode?: 'none' | 'phones' | 'all';
  position?: number;
  eta_hours_min?: number;
  eta_hours_max?: number;
  closed?: boolean;
}

export interface TechData {
  visible: boolean;
  reason?: string;
  first_name?: string;
  avatar_url?: string | null;
}

export interface PortalPhoto {
  path: string;
  is_before: boolean;
  uploaded_at: string;
  deletable: boolean;
}

export interface PortalPhotos {
  photos: PortalPhoto[];
  delete_window_hours: number;
}

export interface LoyaltyData {
  enabled: boolean;
  points: number;
  rate_per_dollar?: number;
  history?: Array<{
    points: number;
    reason: string | null;
    reference_type: string | null;
    created_at: string;
  }>;
}

export interface PortalConfig {
  portal_queue_mode?: string;
  portal_show_tech?: string;
  portal_sla_enabled?: string;
  portal_sla_message?: string;
  portal_loyalty_enabled?: string;
  portal_loyalty_rate?: string;
  portal_referral_reward?: string;
  portal_review_threshold?: string;
  portal_google_review_url?: string;
  portal_after_photo_delete_hours?: string;
  store_name?: string;
  store_phone?: string;
  store_address?: string;
  store_city?: string;
  store_state?: string;
  store_zip?: string;
  store_hours?: string;
  store_website?: string;
}

interface ApiEnvelope<T> {
  success: boolean;
  data: T;
  message?: string;
}

async function unwrap<T>(promise: Promise<{ data: ApiEnvelope<T> }>): Promise<T> {
  const res = await promise;
  if (!res.data?.success) {
    throw new Error(res.data?.message || 'Request failed');
  }
  return res.data.data;
}

export function getTimeline(ticketId: number): Promise<{ events: TimelineEvent[] }> {
  return unwrap(client.get(`/ticket/${ticketId}/timeline`));
}

export function getQueuePosition(ticketId: number): Promise<QueueData> {
  return unwrap(client.get(`/ticket/${ticketId}/queue-position`));
}

export function getTech(ticketId: number): Promise<TechData> {
  return unwrap(client.get(`/ticket/${ticketId}/tech`));
}

export function getPortalPhotos(ticketId: number): Promise<PortalPhotos> {
  return unwrap(client.get(`/ticket/${ticketId}/photos`));
}

export function hidePortalPhoto(
  ticketId: number,
  photoPath: string,
): Promise<{ hidden: boolean }> {
  return unwrap(
    client.delete(`/ticket/${ticketId}/photos`, { data: { photo_path: photoPath } }),
  );
}

export function getReceiptUrl(ticketId: number): string {
  return `/portal/api/v2/ticket/${ticketId}/receipt.pdf`;
}

export function getWarrantyUrl(ticketId: number): string {
  return `/portal/api/v2/ticket/${ticketId}/warranty.pdf`;
}

export function submitReview(
  ticketId: number,
  rating: number,
  comment: string,
): Promise<{ stored: boolean; forward_url: string | null }> {
  return unwrap(client.post(`/ticket/${ticketId}/review`, { rating, comment }));
}

export function getLoyalty(customerId: number): Promise<LoyaltyData> {
  return unwrap(client.get(`/customer/${customerId}/loyalty`));
}

export function getReferralCode(
  customerId: number,
): Promise<{ code: string; created: boolean }> {
  return unwrap(client.post(`/customer/${customerId}/referral-code`, {}));
}

export function getPortalConfig(): Promise<PortalConfig> {
  return unwrap(client.get(`/config`));
}
