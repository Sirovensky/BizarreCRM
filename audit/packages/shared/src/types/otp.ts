export interface DeviceOtp {
  id: number;
  ticket_id: number;
  ticket_device_id: number;
  code: string;
  phone: string;
  is_verified: boolean;
  expires_at: string;
  created_at: string;
}
