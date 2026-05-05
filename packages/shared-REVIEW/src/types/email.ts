export interface EmailMessage {
  id: number;
  from_address: string;
  to_address: string;
  subject: string;
  body: string;
  status: string;
  entity_type: string | null;
  entity_id: number | null;
  user_id: number | null;
  created_at: string;
}
