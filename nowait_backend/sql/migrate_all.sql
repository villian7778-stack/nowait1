-- ============================================================
-- NOWAIT — Combined migration
-- Run this once in Supabase SQL Editor on any existing database
-- that was created before these columns were added.
-- Every statement uses IF NOT EXISTS so it is safe to re-run.
-- ============================================================

-- 1. Add state to profiles (registration state/city dropdowns)
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';

-- 2. Add state to shops (create/edit shop state/city dropdowns)
ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';

-- 3. Add opening_hours to shops (opening & closing time display)
ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS opening_hours TEXT;
