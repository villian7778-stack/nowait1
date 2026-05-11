-- ============================================================
-- Migration: Add 'scheme' notification type
-- Run this in the Supabase SQL Editor.
-- Safe to re-run.
-- ============================================================

-- Drop the existing CHECK constraint on notifications.type and
-- replace it with one that also allows 'scheme'.
ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications
    ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'scheme', 'queue_update', 'coming'));
