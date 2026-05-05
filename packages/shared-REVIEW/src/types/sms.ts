export interface SmsMessage {
  id: number;
  from_number: string;
  to_number: string;
  conv_phone: string;
  message: string | null;
  status: 'sent' | 'delivered' | 'failed' | 'received';
  direction: 'inbound' | 'outbound';
  error: string | null;
  provider: string | null;
  entity_type: string | null;
  entity_id: number | null;
  user_id: number | null;
  created_at: string;
}

export interface SmsConversation {
  conv_phone: string;
  customer_name: string | null;
  customer_id: number | null;
  last_message: string | null;
  last_message_at: string;
  last_direction: 'inbound' | 'outbound';
  unread_count: number;
}

export interface SmsTemplate {
  id: number;
  name: string;
  content: string;
  category: string | null;
  is_active: boolean;
  created_at: string;
}

export interface Snippet {
  id: number;
  shortcode: string;
  title: string;
  content: string;
  category: string | null;
  created_by: number | null;
  created_at: string;
}

export interface SendSmsInput {
  to: string;
  message: string;
  entity_type?: string;
  entity_id?: number;
}
