-- Migration: Add payment_transactions table (Razorpay subscription & promotion payments)
-- Run this in the Supabase SQL Editor

CREATE TABLE IF NOT EXISTS payment_transactions (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id              UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  owner_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  purpose              TEXT NOT NULL CHECK (purpose IN ('subscription', 'promotion')),
  razorpay_order_id    TEXT NOT NULL,
  razorpay_payment_id  TEXT,
  razorpay_signature   TEXT,
  amount_paise         INTEGER NOT NULL,
  currency             TEXT NOT NULL DEFAULT 'INR',
  status               TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid', 'failed')),
  metadata             JSONB,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One row per Razorpay order
  UNIQUE (razorpay_order_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_shop_id ON payment_transactions(shop_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_owner_id ON payment_transactions(owner_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);

-- Row Level Security
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- Shop owners can read their own transactions. All writes go through the
-- backend (service_role key, bypasses RLS) after Razorpay signature
-- verification — no INSERT/UPDATE policy is granted to authenticated users
-- so a payment record can never be forged directly via the Supabase client.
CREATE POLICY "Owners read own transactions"
  ON payment_transactions FOR SELECT
  USING (auth.uid() = owner_id);
