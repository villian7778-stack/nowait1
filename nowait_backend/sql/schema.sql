-- ============================================================
-- NOWAIT — Clean Schema Reset
-- Run this in Supabase SQL Editor to get a fully clean database.
-- WARNING: This drops all existing tables and recreates them.
--          All existing data will be lost.
-- ============================================================

-- ============================================================
-- DROP EVERYTHING (clean slate)
-- ============================================================

-- Drop old functions (v1 and v2)
DROP FUNCTION IF EXISTS join_queue(UUID, UUID, UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS join_queue_v2(UUID, UUID, UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS advance_queue(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS advance_queue_v2(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS skip_customer(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS skip_customer_v2(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;

-- Drop all tables (order matters — dependents first)
DROP TABLE IF EXISTS queue_events    CASCADE;
DROP TABLE IF EXISTS notifications   CASCADE;
DROP TABLE IF EXISTS queue_entries   CASCADE;
DROP TABLE IF EXISTS staff_members   CASCADE;
DROP TABLE IF EXISTS shop_staff      CASCADE;  -- old name, may exist
DROP TABLE IF EXISTS promotions      CASCADE;
DROP TABLE IF EXISTS subscriptions   CASCADE;
DROP TABLE IF EXISTS services        CASCADE;
DROP TABLE IF EXISTS shops           CASCADE;
DROP TABLE IF EXISTS profiles        CASCADE;

-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL DEFAULT '',
    phone       TEXT UNIQUE NOT NULL,
    state       TEXT DEFAULT '',
    city        TEXT DEFAULT '',
    role        TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'owner')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE shops (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id        UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL,
    address         TEXT NOT NULL,
    city            TEXT NOT NULL,
    state           TEXT DEFAULT '',
    is_open         BOOLEAN NOT NULL DEFAULT FALSE,
    avg_wait_minutes INTEGER NOT NULL DEFAULT 10,
    opening_hours   TEXT,
    images          TEXT[] DEFAULT '{}',
    rating          DECIMAL(3,2) DEFAULT 0.0,
    review_count    INTEGER DEFAULT 0,
    description     TEXT DEFAULT '',
    queue_paused    BOOLEAN NOT NULL DEFAULT FALSE,
    max_queue_size  INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE services (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT DEFAULT '',
    price       DECIMAL(10,2) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE subscriptions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    plan        TEXT NOT NULL CHECK (plan IN ('basic', 'premium')),
    status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(shop_id)
);

CREATE TABLE promotions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    description TEXT NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Staff members — informational only, shown to customers on shop page
CREATE TABLE staff_members (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id         UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES profiles(id) ON DELETE SET NULL,
    display_name    TEXT NOT NULL,
    is_owner_staff  BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    added_by        UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Single FIFO queue per shop — no staff routing
CREATE TABLE queue_entries (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id      UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token_number INTEGER NOT NULL,
    status       TEXT NOT NULL DEFAULT 'waiting'
                     CHECK (status IN ('waiting', 'serving', 'completed', 'skipped', 'cancelled')),
    service_id   UUID REFERENCES services(id) ON DELETE SET NULL,
    coming_at    TIMESTAMPTZ,
    joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    served_at    TIMESTAMPTZ,
    UNIQUE(shop_id, token_number)
);

CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    type        TEXT NOT NULL CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'queue_update', 'coming')),
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    shop_name   TEXT NOT NULL,
    shop_id     UUID REFERENCES shops(id) ON DELETE SET NULL,
    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Queue events log (used by analytics)
CREATE TABLE queue_events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    entry_id    UUID REFERENCES queue_entries(id) ON DELETE SET NULL,
    event_type  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- Prevent duplicate active queue entry per user per shop
CREATE UNIQUE INDEX idx_active_queue_per_user_shop
    ON queue_entries(shop_id, user_id)
    WHERE status IN ('waiting', 'serving');

CREATE INDEX idx_queue_entries_shop_status  ON queue_entries(shop_id, status, token_number);
CREATE INDEX idx_queue_entries_user         ON queue_entries(user_id, status);
CREATE INDEX idx_shops_city_category        ON shops(city, category);
CREATE INDEX idx_notifications_user         ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_subscriptions_shop         ON subscriptions(shop_id, status, expires_at);
CREATE INDEX idx_staff_members_shop         ON staff_members(shop_id, is_active);

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_shops_updated_at
    BEFORE UPDATE ON shops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_promotions_updated_at
    BEFORE UPDATE ON promotions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- QUEUE FUNCTIONS
-- ============================================================

-- Atomic join — single FIFO queue per shop
CREATE OR REPLACE FUNCTION join_queue_v2(
    p_shop_id   UUID,
    p_user_id   UUID,
    p_staff_id  UUID DEFAULT NULL,    -- ignored, kept for API compatibility
    p_service_id UUID DEFAULT NULL
)
RETURNS queue_entries AS $$
DECLARE
    v_shop  shops%ROWTYPE;
    v_token INTEGER;
    v_entry queue_entries%ROWTYPE;
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

    INSERT INTO queue_entries (shop_id, user_id, token_number, status, service_id)
    VALUES (p_shop_id, p_user_id, v_token, 'waiting', p_service_id)
    RETURNING * INTO v_entry;

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Advance queue — pure FIFO, no staff filtering
CREATE OR REPLACE FUNCTION advance_queue_v2(
    p_shop_id  UUID,
    p_staff_id UUID DEFAULT NULL    -- ignored, kept for API compatibility
)
RETURNS TABLE(completed_entry queue_entries, next_entry queue_entries) AS $$
DECLARE
    v_completed queue_entries%ROWTYPE;
    v_next      queue_entries%ROWTYPE;
BEGIN
    UPDATE queue_entries
    SET status = 'completed', served_at = NOW()
    WHERE shop_id = p_shop_id AND status = 'serving'
    RETURNING * INTO v_completed;

    SELECT * INTO v_next
    FROM queue_entries
    WHERE shop_id = p_shop_id AND status = 'waiting'
    ORDER BY token_number ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF FOUND THEN
        UPDATE queue_entries
        SET status = 'serving'
        WHERE id = v_next.id
        RETURNING * INTO v_next;
    END IF;

    RETURN QUERY SELECT v_completed, v_next;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Skip a specific customer
CREATE OR REPLACE FUNCTION skip_customer_v2(
    p_entry_id UUID,
    p_staff_id UUID DEFAULT NULL    -- ignored, kept for API compatibility
)
RETURNS queue_entries AS $$
DECLARE
    v_entry queue_entries%ROWTYPE;
BEGIN
    SELECT * INTO v_entry
    FROM queue_entries
    WHERE id = p_entry_id AND status IN ('waiting', 'serving');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Entry not found or not skippable';
    END IF;

    UPDATE queue_entries
    SET status = 'skipped', served_at = NOW()
    WHERE id = p_entry_id
    RETURNING * INTO v_entry;

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE shops           ENABLE ROW LEVEL SECURITY;
ALTER TABLE services        ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_entries   ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications   ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_members   ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_events    ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY "profiles_read_all"   ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Shops
CREATE POLICY "shops_read_all"    ON shops FOR SELECT USING (true);
CREATE POLICY "shops_insert_owner" ON shops FOR INSERT WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "shops_update_owner" ON shops FOR UPDATE USING (auth.uid() = owner_id);
CREATE POLICY "shops_delete_owner" ON shops FOR DELETE USING (auth.uid() = owner_id);

-- Services
CREATE POLICY "services_read_all"     ON services FOR SELECT USING (true);
CREATE POLICY "services_modify_owner" ON services FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Queue entries
CREATE POLICY "queue_read_own" ON queue_entries FOR SELECT USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "queue_insert_customer"  ON queue_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "queue_update_own_cancel" ON queue_entries FOR UPDATE USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Notifications
CREATE POLICY "notifications_read_own"   ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notifications_update_own" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- Subscriptions
CREATE POLICY "subscriptions_read_owner"   ON subscriptions FOR SELECT USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "subscriptions_insert_owner" ON subscriptions FOR INSERT WITH CHECK (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "subscriptions_update_owner" ON subscriptions FOR UPDATE USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Promotions
CREATE POLICY "promotions_read_all"    ON promotions FOR SELECT USING (true);
CREATE POLICY "promotions_modify_owner" ON promotions FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Staff members — readable by everyone, writable by shop owner only
CREATE POLICY "staff_read_all"    ON staff_members FOR SELECT USING (true);
CREATE POLICY "staff_modify_owner" ON staff_members FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Queue events — readable by shop owner only
CREATE POLICY "queue_events_read_owner" ON queue_events FOR SELECT USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
