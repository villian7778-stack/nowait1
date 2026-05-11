-- ============================================================
-- NOWAIT — Full Migration (up to and including Reviews)
-- Run this ONCE in Supabase SQL Editor on a fresh database
-- that already has the base schema (schema.sql) applied.
--
-- This file consolidates every incremental migration in order:
--   1.  profiles.state column
--   2.  shops.state column
--   3.  shops.opening_hours column
--   4.  shops latitude / longitude columns + index
--   5.  profiles.queue_ban_until column
--   6.  One-active-queue-per-user unique index
--   7.  services.duration_minutes column
--   8.  queue_entries service columns (service_ids, total_duration_minutes)
--   9.  join_queue_v2 stored function (service-aware atomic join)
--   10. shop_reviews table + indexes + RLS policies
--
-- Every statement uses IF NOT EXISTS / OR REPLACE so it is
-- safe to re-run on a database where some steps already exist.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. profiles: state column (state/city dropdown on registration)
-- ────────────────────────────────────────────────────────────
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';


-- ────────────────────────────────────────────────────────────
-- 2. shops: state column (state/city dropdown on shop create/edit)
-- ────────────────────────────────────────────────────────────
ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';


-- ────────────────────────────────────────────────────────────
-- 3. shops: opening_hours column (display on shop cards/detail)
-- ────────────────────────────────────────────────────────────
ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS opening_hours TEXT;


-- ────────────────────────────────────────────────────────────
-- 4. shops: latitude / longitude (map picker + directions chip)
-- ────────────────────────────────────────────────────────────
ALTER TABLE shops
    ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

CREATE INDEX IF NOT EXISTS idx_shops_location
    ON shops (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;


-- ────────────────────────────────────────────────────────────
-- 5. profiles: queue_ban_until (2-hour cooldown after cancel)
-- ────────────────────────────────────────────────────────────
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS queue_ban_until TIMESTAMPTZ;


-- ────────────────────────────────────────────────────────────
-- 6. queue_entries: one active entry per user across ALL shops
--    (prevents joining multiple shop queues simultaneously)
-- ────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_queue_per_user
    ON queue_entries(user_id)
    WHERE status IN ('waiting', 'serving');


-- ────────────────────────────────────────────────────────────
-- 7. services: duration_minutes (per-service estimated time)
-- ────────────────────────────────────────────────────────────
ALTER TABLE services
    ADD COLUMN IF NOT EXISTS duration_minutes INTEGER NOT NULL DEFAULT 15;


-- ────────────────────────────────────────────────────────────
-- 8. queue_entries: multi-service columns
-- ────────────────────────────────────────────────────────────
ALTER TABLE queue_entries
    ADD COLUMN IF NOT EXISTS service_ids UUID[] NOT NULL DEFAULT '{}';

ALTER TABLE queue_entries
    ADD COLUMN IF NOT EXISTS total_duration_minutes INTEGER;


-- ────────────────────────────────────────────────────────────
-- 9. join_queue_v2: atomic queue-join function (service-aware)
--    Replaces the original join_queue function with support for
--    multiple service_ids and total_duration_minutes.
--    Backwards-compatible: all new params have safe defaults.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION join_queue_v2(
    p_shop_id                UUID,
    p_user_id                UUID,
    p_staff_id               UUID    DEFAULT NULL,
    p_service_id             UUID    DEFAULT NULL,
    p_service_ids            UUID[]  DEFAULT '{}',
    p_total_duration_minutes INTEGER DEFAULT NULL
)
RETURNS queue_entries AS $$
DECLARE
    v_shop   shops%ROWTYPE;
    v_token  INTEGER;
    v_entry  queue_entries%ROWTYPE;
    v_sid    UUID;
BEGIN
    SELECT * INTO v_shop FROM shops WHERE id = p_shop_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SHOP_NOT_FOUND: Shop does not exist';
    END IF;

    IF NOT v_shop.is_open THEN
        RAISE EXCEPTION 'SHOP_CLOSED: Shop is currently closed';
    END IF;

    IF v_shop.queue_paused THEN
        RAISE EXCEPTION 'QUEUE_PAUSED: Queue is currently paused';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE shop_id = p_shop_id
          AND status = 'active'
          AND expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'NO_SUBSCRIPTION: Shop does not have an active subscription';
    END IF;

    IF EXISTS (
        SELECT 1 FROM queue_entries
        WHERE shop_id = p_shop_id
          AND user_id = p_user_id
          AND status IN ('waiting', 'serving')
    ) THEN
        RAISE EXCEPTION 'ALREADY_IN_QUEUE: User is already in this queue';
    END IF;

    IF v_shop.max_queue_size IS NOT NULL THEN
        IF (
            SELECT COUNT(*) FROM queue_entries
            WHERE shop_id = p_shop_id AND status IN ('waiting', 'serving')
        ) >= v_shop.max_queue_size THEN
            RAISE EXCEPTION 'QUEUE_FULL: Queue has reached its maximum capacity';
        END IF;
    END IF;

    SELECT COALESCE(MAX(token_number), 0) + 1
    INTO v_token
    FROM queue_entries
    WHERE shop_id = p_shop_id;

    -- Prefer explicit p_service_id; fall back to first element of array
    v_sid := COALESCE(
        p_service_id,
        CASE WHEN array_length(p_service_ids, 1) > 0 THEN p_service_ids[1] ELSE NULL END
    );

    INSERT INTO queue_entries (
        shop_id, user_id, token_number, status,
        service_id, service_ids, total_duration_minutes
    )
    VALUES (
        p_shop_id, p_user_id, v_token, 'waiting',
        v_sid, p_service_ids, p_total_duration_minutes
    )
    RETURNING * INTO v_entry;

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 10. shop_reviews table: star ratings + optional text reviews
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shop_reviews (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id        UUID        NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id        UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    queue_entry_id UUID        REFERENCES queue_entries(id) ON DELETE SET NULL,
    rating         INTEGER     NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review         TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Enforce one review per completed visit
    UNIQUE (user_id, queue_entry_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_reviews_shop_id
    ON shop_reviews(shop_id);

CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id
    ON shop_reviews(user_id);

CREATE INDEX IF NOT EXISTS idx_shop_reviews_created_at
    ON shop_reviews(created_at DESC);

-- Row Level Security
ALTER TABLE shop_reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read reviews (shown publicly on shop cards and detail pages)
CREATE POLICY "Public read reviews"
    ON shop_reviews FOR SELECT
    USING (true);

-- Authenticated users can only insert reviews under their own user_id
CREATE POLICY "Users insert own reviews"
    ON shop_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own reviews
CREATE POLICY "Users delete own reviews"
    ON shop_reviews FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================
-- Done. All migrations applied.
-- ============================================================
