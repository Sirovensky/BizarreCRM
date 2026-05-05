export interface Manufacturer {
  id: number;
  name: string;
  slug: string;
  logo_url: string | null;
  created_at: string;
}

export interface DeviceModel {
  id: number;
  manufacturer_id: number;
  name: string;
  slug: string;
  category: 'phone' | 'tablet' | 'laptop' | 'console' | 'other';
  release_year: number | null;
  is_popular: boolean;
  created_at: string;
  manufacturer_name?: string;
}

export interface SupplierCatalogItem {
  id: number;
  source: 'mobilesentrix' | 'phonelcdparts';
  external_id: string | null;
  sku: string | null;
  name: string;
  description: string | null;
  category: string | null;
  price: number;
  compare_price: number | null;
  image_url: string | null;
  product_url: string | null;
  tags: string | null;
  compatible_devices: string | null;
  in_stock: boolean;
  last_synced: string;
  created_at: string;
}

export interface PartsOrderQueueItem {
  id: number;
  source: string;
  catalog_item_id: number | null;
  inventory_item_id: number | null;
  name: string;
  sku: string | null;
  supplier_url: string | null;
  image_url: string | null;
  unit_price: number;
  quantity_needed: number;
  status: 'pending' | 'ordered' | 'received' | 'cancelled';
  notes: string | null;
  created_at: string;
  updated_at: string;
}
