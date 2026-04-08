export interface InventoryItem {
  id: number;
  sku: string | null;
  upc: string | null;
  name: string;
  description: string | null;
  item_type: 'product' | 'part' | 'service';
  category: string | null;
  manufacturer: string | null;
  device_type: string | null;
  cost_price: number;
  retail_price: number;
  in_stock: number;
  reorder_level: number;
  stock_warning: number;
  tax_class_id: number | null;
  tax_inclusive: boolean;
  is_serialized: boolean;
  supplier_id: number | null;
  image_url: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  // Joined
  supplier?: Supplier;
  serials?: InventorySerial[];
  group_prices?: InventoryGroupPrice[];
}

export interface InventorySerial {
  id: number;
  inventory_item_id: number;
  serial_number: string;
  status: 'in_stock' | 'sold' | 'returned' | 'defective';
  created_at: string;
}

export interface InventoryGroupPrice {
  id: number;
  inventory_item_id: number;
  customer_group_id: number;
  price: number;
  group_name?: string;
}

export interface StockMovement {
  id: number;
  inventory_item_id: number;
  type: 'purchase' | 'sale' | 'adjustment' | 'return' | 'transfer';
  quantity: number;
  reference_type: string | null;
  reference_id: number | null;
  notes: string | null;
  user_id: number | null;
  created_at: string;
}

export interface Supplier {
  id: number;
  name: string;
  contact_name: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  notes: string | null;
  created_at: string;
}

export interface PurchaseOrder {
  id: number;
  order_id: string;
  supplier_id: number;
  status: 'draft' | 'sent' | 'partial' | 'received' | 'cancelled';
  paid_status: string;
  subtotal: number;
  tax: number;
  total: number;
  notes: string | null;
  expected_date: string | null;
  received_date: string | null;
  created_by: number;
  created_at: string;
  updated_at: string;
  supplier?: Supplier;
  items?: PurchaseOrderItem[];
}

export interface PurchaseOrderItem {
  id: number;
  purchase_order_id: number;
  inventory_item_id: number;
  quantity_ordered: number;
  quantity_received: number;
  cost_price: number;
  item_name?: string;
  item_sku?: string;
}

export interface CreateInventoryInput {
  sku?: string;
  upc?: string;
  name: string;
  description?: string;
  item_type: 'product' | 'part' | 'service';
  category?: string;
  manufacturer?: string;
  device_type?: string;
  cost_price?: number;
  retail_price: number;
  in_stock?: number;
  reorder_level?: number;
  stock_warning?: number;
  tax_class_id?: number;
  tax_inclusive?: boolean;
  is_serialized?: boolean;
  supplier_id?: number;
}
