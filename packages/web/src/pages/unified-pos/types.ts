// Cart item discriminated union
export interface DeviceData {
  device_type: string;
  device_name: string;
  device_model_id: number | null;
  imei: string;
  serial: string;
  security_code: string;
  color: string;
  network: string;
  pre_conditions: string[];
  additional_notes: string;
  device_location: string;
  warranty: boolean;
  warranty_days: number;
  due_date?: string; // ISO date string for estimated completion
}

export interface PartEntry {
  _key: string;
  inventory_item_id: number;
  name: string;
  sku: string | null;
  quantity: number;
  price: number;
  taxable: boolean;
  status: 'available' | 'missing' | 'ordered';
}

export interface RepairCartItem {
  type: 'repair';
  id: string;
  device: DeviceData;
  serviceName: string;
  repairServiceId: number | null;
  selectedGradeId: number | null;
  laborPrice: number;
  lineDiscount: number;
  parts: PartEntry[];
  taxable: boolean; // labor taxable?
  sourceTicketId?: number | null; // if loaded from an existing ticket
  sourceTicketOrderId?: string | null; // e.g. "T-2908"
}

export interface ProductCartItem {
  type: 'product';
  id: string;
  inventoryItemId: number;
  name: string;
  sku: string | null;
  quantity: number;
  unitPrice: number;
  taxable: boolean;
  taxInclusive: boolean;
}

export interface MiscCartItem {
  type: 'misc';
  id: string;
  name: string;
  unitPrice: number;
  quantity: number;
  taxable: boolean;
}

export type CartItem = RepairCartItem | ProductCartItem | MiscCartItem;

export interface CustomerResult {
  id: number;
  first_name: string;
  last_name: string;
  phone: string | null;
  mobile: string | null;
  email: string | null;
  organization: string | null;
  group_name?: string;
  group_discount_pct?: number;
  group_discount_type?: string;
  group_auto_apply?: boolean;
}

// Repair drill-down state machine
export type RepairDrillState =
  | { step: 'CATEGORY' }
  | { step: 'DEVICE'; category: string }
  | { step: 'SERVICE'; category: string; deviceModelId: number; deviceName: string }
  | { step: 'DETAILS'; category: string; deviceModelId: number; deviceName: string; serviceId: number; serviceName: string; laborPrice: number; gradeId: number | null; gradeParts: PartEntry[] };

export interface TicketMeta {
  assignedTo: number | null;
  dueDate: string;
  source: string;
  internalNotes: string;
  labels: string;
  discountReason: string;
}

export const TAX_RATE = 0.08865;

export function genId(): string {
  return (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36));
}
