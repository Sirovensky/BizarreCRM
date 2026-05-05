export interface Automation {
  id: number;
  name: string;
  is_active: boolean;
  trigger_type: 'status_change' | 'time_elapsed' | 'ticket_created' | 'ticket_closed';
  trigger_config: Record<string, unknown>;
  action_type: 'send_sms' | 'send_email' | 'change_status' | 'assign_to' | 'notify';
  action_config: Record<string, unknown>;
  sort_order: number;
  created_at: string;
}

export interface CustomFieldDefinition {
  id: number;
  entity_type: 'ticket' | 'customer' | 'inventory' | 'invoice';
  field_name: string;
  field_type: 'text' | 'number' | 'date' | 'select' | 'checkbox' | 'textarea';
  options: string[] | null;
  is_required: boolean;
  sort_order: number;
  created_at: string;
}

export interface CustomFieldValue {
  id: number;
  definition_id: number;
  entity_type: string;
  entity_id: number;
  value: string | null;
}
