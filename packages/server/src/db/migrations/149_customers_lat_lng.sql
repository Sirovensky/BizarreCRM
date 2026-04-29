-- WEB-S6-011: Add lat/lng to customers for field-service map routing.
-- Geocoded on create/update via Nominatim when an address is present.
ALTER TABLE customers ADD COLUMN lat REAL;
ALTER TABLE customers ADD COLUMN lng REAL;
