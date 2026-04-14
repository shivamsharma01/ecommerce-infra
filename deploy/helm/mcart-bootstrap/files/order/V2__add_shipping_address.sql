-- Snapshot delivery address on orders so receipts/order details remain stable.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS shipping_address_id uuid NULL,
  ADD COLUMN IF NOT EXISTS shipping_address_json jsonb NULL;

