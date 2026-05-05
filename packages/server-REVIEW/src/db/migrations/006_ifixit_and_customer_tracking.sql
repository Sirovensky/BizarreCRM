-- Migration 006: Add iFixit URL to device_models + customer group discounts
-- ============================================================================

-- Add iFixit URL to device_models for linking to repair guides
ALTER TABLE device_models ADD COLUMN ifixit_url TEXT;

-- Add discount fields to customer_groups for auto-applying member discounts
ALTER TABLE customer_groups ADD COLUMN discount_type TEXT NOT NULL DEFAULT 'percentage'; -- 'percentage' or 'fixed'
ALTER TABLE customer_groups ADD COLUMN auto_apply INTEGER NOT NULL DEFAULT 1; -- auto-apply on checkout
