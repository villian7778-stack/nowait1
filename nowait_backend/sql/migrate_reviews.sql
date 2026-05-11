-- Migration: Add shop_reviews table
-- Run this in the Supabase SQL Editor

CREATE TABLE IF NOT EXISTS shop_reviews (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id          UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  queue_entry_id   UUID REFERENCES queue_entries(id) ON DELETE SET NULL,
  rating           INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review           TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One review per visit (queue entry)
  UNIQUE (user_id, queue_entry_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_reviews_shop_id ON shop_reviews(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id ON shop_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_created_at ON shop_reviews(created_at DESC);

-- Row Level Security
ALTER TABLE shop_reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read reviews
CREATE POLICY "Public read reviews"
  ON shop_reviews FOR SELECT
  USING (true);

-- Authenticated users can insert their own reviews
CREATE POLICY "Users insert own reviews"
  ON shop_reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own reviews
CREATE POLICY "Users delete own reviews"
  ON shop_reviews FOR DELETE
  USING (auth.uid() = user_id);
