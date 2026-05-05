export interface StoreConfig {
  store_name: string;
  address: string;
  phone: string;
  email: string;
  timezone: string;
  currency: string;
  logo_url: string | null;
  receipt_header: string | null;
  receipt_footer: string | null;
  hours: string | null;
  sms_provider: string;
  default_tax_class_id: number | null;
}

export interface TaxClass {
  id: number;
  name: string;
  rate: number;
  is_default: boolean;
  created_at: string;
}

export interface PaymentMethod {
  id: number;
  name: string;
  is_active: boolean;
  sort_order: number;
}

export interface ReferralSource {
  id: number;
  name: string;
  sort_order: number;
}

export interface LoanerDevice {
  id: number;
  name: string;
  serial: string | null;
  imei: string | null;
  condition: string | null;
  status: 'available' | 'loaned' | 'retired';
  notes: string | null;
  created_at: string;
}
