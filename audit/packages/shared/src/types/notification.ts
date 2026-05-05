export interface Notification {
  id: number;
  user_id: number;
  type: string;
  title: string;
  message: string | null;
  entity_type: string | null;
  entity_id: number | null;
  is_read: boolean;
  created_at: string;
}
