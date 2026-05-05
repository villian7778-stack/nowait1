-- ============================================================
-- Migration: Shop Location Coordinates
-- Run this in the Supabase SQL Editor on an existing database.
-- Safe to re-run (uses IF NOT EXISTS / IF EXISTS guards).
-- ============================================================

-- Add latitude and longitude columns to the shops table.
-- Nullable so existing shops without coordinates are unaffected.

ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Optional: index for geo-proximity queries in the future.
CREATE INDEX IF NOT EXISTS idx_shops_location
    ON shops (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
