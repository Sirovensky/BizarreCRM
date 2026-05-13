export interface Customer {
  id: number;
  code: string | null;
  first_name: string;
  last_name: string;
  title: string | null;
  organization: string | null;
  type: 'individual' | 'business';
  email: string | null;
  phone: string | null;
  mobile: string | null;
  address1: string | null;
  address2: string | null;
  city: string | null;
  state: string | null;
  postcode: string | null;
  country?: string | null;
  contact_person: string | null;
  contact_relation: string | null;
  driving_license: string | null;
  license_image: string | null;
  id_type: string | null;
  id_number: string | null;
  referred_by: string | null;
  customer_group_id: number | null;
  customer_group_name: string | null;
  tax_number: string | null;
  tax_class_id: number | null;
  email_opt_in: boolean;
  sms_opt_in: boolean;
  comments: string | null;
  avatar_url: string | null;
  source: string | null;
  tags: string[];
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
  // Joined
  phones?: CustomerPhone[];
  emails?: CustomerEmail[];
  ticket_count?: number;
}

export interface CustomerPhone {
  id: number;
  customer_id: number;
  phone: string;
  label: string;
  is_primary: boolean;
}

export interface CustomerEmail {
  id: number;
  customer_id: number;
  email: string;
  label: string;
  is_primary: boolean;
}

export interface CustomerAddress {
  id: string;
  customer_id: number;
  type: 'primary' | 'billing' | 'shipping' | 'other';
  label: string;
  is_primary: boolean;
  address1: string | null;
  address2: string | null;
  city: string | null;
  state: string | null;
  postcode: string | null;
  country: string | null;
  formatted: string;
  source?: string;
  updated_at?: string | null;
}

export interface CustomerGroup {
  id: number;
  name: string;
  discount_pct: number;
  description: string | null;
  created_at: string;
}

export interface CustomerAsset {
  id: number;
  customer_id: number;
  name: string;
  device_type: string | null;
  serial: string | null;
  imei: string | null;
  color: string | null;
  notes: string | null;
  created_at: string;
}

export interface CreateCustomerInput {
  first_name: string;
  last_name?: string;
  title?: string;
  organization?: string;
  type?: 'individual' | 'business';
  email?: string;
  phone?: string;
  mobile?: string;
  address1?: string;
  address2?: string;
  city?: string;
  state?: string;
  postcode?: string;
  country?: string;
  contact_person?: string;
  contact_relation?: string;
  referred_by?: string;
  customer_group_id?: number;
  tax_number?: string;
  tax_class_id?: number;
  // WEB-UIUX-765: per-customer tax-exempt flag. 0/1 int matches the SQLite
  // CHECK constraint; `tax_exempt_reason` is free-form (resale cert / state code).
  tax_exempt?: 0 | 1 | boolean;
  tax_exempt_reason?: string;
  // ID-on-file (driver's license / passport / state ID) — schema-supported
  // since the original customer table; missing from this type kept POS
  // and CustomerCreatePage from sending it. Surfacing now so the rich POS
  // create-customer panel can capture ID at intake.
  id_type?: string;
  id_number?: string;
  driving_license?: string;
  email_opt_in?: boolean;
  sms_opt_in?: boolean;
  comments?: string;
  source?: string;
  tags?: string[];
  phones?: { phone: string; label: string; is_primary?: boolean }[];
  emails?: { email: string; label: string; is_primary?: boolean }[];
  force_create?: boolean;
}

export type UpdateCustomerInput = Partial<CreateCustomerInput>;
