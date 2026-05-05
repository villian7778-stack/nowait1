-- ============================================================
-- Migration: Queue Restrictions
-- Run this in Supabase SQL Editor on an existing database.
-- Safe to re-run (all statements use IF NOT EXISTS / IF EXISTS).
-- ============================================================

-- 1. Enforce one active queue entry per user across ALL shops.
--    The existing idx_active_queue_per_user_shop only prevents
--    duplicate entries within the same shop. This new index prevents
--    a user from being in queues at multiple shops simultaneously.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_queue_per_user
    ON queue_entries(user_id)
    WHERE status IN ('waiting', 'serving');

-- 2. Store the timestamp until which a user is banned from joining
--    any queue (set automatically on cancellation, 2-hour cooldown).
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS queue_ban_until TIMESTAMPTZ;
