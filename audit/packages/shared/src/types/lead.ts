export interface Lead {
  id: number;
  order_id: string;
  customer_id: number | null;
  first_name: string;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  zip_code: string | null;
  address: string | null;
  status: 'new' | 'contacted' | 'scheduled' | 'converted' | 'lost';
  referred_by: string | null;
  assigned_to: number | null;
  source: string | null;
  notes: string | null;
  created_by: number | null;
  created_at: string;
  updated_at: string;
  devices?: LeadDevice[];
  assigned_user?: { id: number; first_name: string; last_name: string };
}

export interface LeadDevice {
  id: number;
  lead_id: number;
  device_name: string;
  repair_type: 'repair' | 'warranty';
  service_type: 'mail_in' | 'walk_in' | 'on_site' | 'pick_up' | 'drop_off';
  service_id: number | null;
  price: number;
  tax: number;
  problem: string | null;
  customer_notes: string | null;
  security_code: string | null;
  start_time: string | null;
  end_time: string | null;
}

export interface Appointment {
  id: number;
  lead_id: number | null;
  customer_id: number | null;
  title: string;
  start_time: string;
  end_time: string;
  assigned_to: number | null;
  status: 'scheduled' | 'confirmed' | 'completed' | 'no_show' | 'cancelled';
  notes: string | null;
  created_at: string;
  customer?: { id: number; first_name: string; last_name: string; phone: string | null };
  assigned_user?: { id: number; first_name: string; last_name: string };
}
