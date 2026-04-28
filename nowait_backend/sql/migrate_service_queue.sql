-- ============================================================
-- Migration: Service-Based Queue System
-- Apply this in Supabase SQL Editor (safe — uses IF NOT EXISTS).
-- Existing data is preserved.
-- ============================================================

-- 1. Add duration_minutes to services
ALTER TABLE services
    ADD COLUMN IF NOT EXISTS duration_minutes INTEGER NOT NULL DEFAULT 15;

-- 2. Add service_ids array and total_duration_minutes to queue_entries
ALTER TABLE queue_entries
    ADD COLUMN IF NOT EXISTS service_ids UUID[] NOT NULL DEFAULT '{}';

ALTER TABLE queue_entries
    ADD COLUMN IF NOT EXISTS total_duration_minutes INTEGER;

-- 3. Update join_queue_v2 to accept and store service_ids + total_duration_minutes
--    New optional params are backwards-compatible (all default to empty/null).
CREATE OR REPLACE FUNCTION join_queue_v2(
    p_shop_id                UUID,
    p_user_id                UUID,
    p_staff_id               UUID    DEFAULT NULL,        -- ignored, kept for API compat
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

    -- Resolve single service_id: prefer explicit p_service_id, else first element of array
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
