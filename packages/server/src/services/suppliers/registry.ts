import { mobilesentrixSource } from './mobilesentrix.js';
import { phoneLcdPartsSource } from './phoneLcdParts.js';
import type { CatalogSource, SupplierSource } from './types.js';

export const supplierSources = [
  mobilesentrixSource,
  phoneLcdPartsSource,
] as const satisfies readonly SupplierSource[];

export const supplierSourceRegistry = Object.freeze(
  Object.fromEntries(supplierSources.map((source) => [source.slug, source])),
) as Readonly<Record<CatalogSource, SupplierSource>>;

export const CATALOG_SOURCES = supplierSources.map((source) => source.slug) as CatalogSource[];

export function getSupplierSource(slug: CatalogSource): SupplierSource {
  const source = (supplierSourceRegistry as Readonly<Partial<Record<string, SupplierSource>>>)[slug];
  if (!source) throw new Error(`Unknown supplier source: ${slug}`);
  return source;
}
