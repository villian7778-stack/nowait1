-- ============================================================
-- NOWAIT — Final Consolidated Schema
--
-- Safe to run on EITHER a brand-new empty Supabase project OR an
-- existing NOWAIT database at any prior migration state. Every
-- statement is idempotent (IF NOT EXISTS / OR REPLACE / DROP-then-
-- CREATE for policies & triggers), so re-running this file is a
-- no-op past the first successful run. Nothing is ever dropped.
--
-- This supersedes running schema.sql / final_schema.sql followed by
-- migrate_all.sql, migrate_location.sql, migrate_service_queue.sql,
-- migrate_full_till_reviews.sql, migrate_scheme_notif.sql,
-- migrate_restrictions.sql, migrate_reviews.sql, migrate_payments.sql
-- one at a time — this file is the union of all of them.
-- ============================================================

-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- for gen_random_uuid()

-- ============================================================
-- TABLES (full modern column set — for a fresh install)
-- ============================================================

CREATE TABLE IF NOT EXISTS profiles (
    id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name                 TEXT NOT NULL DEFAULT '',
    phone                TEXT UNIQUE NOT NULL,
    email                TEXT,
    state                TEXT DEFAULT '',
    city                 TEXT DEFAULT '',
    role                 TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'owner')),
    queue_ban_until      TIMESTAMPTZ,
    queue_ban_categories JSONB DEFAULT '{}',
    fcm_token            TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shops (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    category         TEXT NOT NULL,
    address          TEXT NOT NULL,
    city             TEXT NOT NULL,
    state            TEXT DEFAULT '',
    is_open          BOOLEAN NOT NULL DEFAULT FALSE,
    avg_wait_minutes INTEGER NOT NULL DEFAULT 10,
    opening_hours    TEXT,
    images           TEXT[] DEFAULT '{}',
    rating           DECIMAL(3,2) DEFAULT 0.0,
    review_count     INTEGER DEFAULT 0,
    description      TEXT DEFAULT '',
    queue_paused     BOOLEAN NOT NULL DEFAULT FALSE,
    max_queue_size   INTEGER,
    latitude         DOUBLE PRECISION,
    longitude        DOUBLE PRECISION,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS services (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id          UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    description      TEXT DEFAULT '',
    price            DECIMAL(10,2) NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 15,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id    UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    plan       TEXT NOT NULL CHECK (plan IN ('basic', 'premium')),
    status     TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(shop_id)
);

CREATE TABLE IF NOT EXISTS promotions (
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
CREATE TABLE IF NOT EXISTS staff_members (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id        UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id        UUID REFERENCES profiles(id) ON DELETE SET NULL,
    display_name   TEXT NOT NULL,
    is_owner_staff BOOLEAN NOT NULL DEFAULT FALSE,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    added_by       UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Single FIFO queue per shop — service-aware (no per-staff routing)
CREATE TABLE IF NOT EXISTS queue_entries (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id                UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id                UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token_number           INTEGER NOT NULL,
    status                 TEXT NOT NULL DEFAULT 'waiting'
                               CHECK (status IN ('waiting', 'serving', 'completed', 'skipped', 'cancelled')),
    service_id             UUID REFERENCES services(id) ON DELETE SET NULL,
    service_ids            UUID[] NOT NULL DEFAULT '{}',
    total_duration_minutes INTEGER,
    coming_at              TIMESTAMPTZ,
    joined_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    served_at              TIMESTAMPTZ,
    UNIQUE(shop_id, token_number)
);

CREATE TABLE IF NOT EXISTS notifications (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    type       TEXT NOT NULL CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'scheme', 'queue_update', 'coming')),
    title      TEXT NOT NULL,
    body       TEXT NOT NULL,
    shop_name  TEXT NOT NULL,
    shop_id    UUID REFERENCES shops(id) ON DELETE SET NULL,
    is_read    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Queue events log (used by analytics)
CREATE TABLE IF NOT EXISTS queue_events (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id    UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    entry_id   UUID REFERENCES queue_entries(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Star ratings + optional text reviews for a completed visit
CREATE TABLE IF NOT EXISTS shop_reviews (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id        UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    queue_entry_id UUID REFERENCES queue_entries(id) ON DELETE SET NULL,
    rating         INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review         TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, queue_entry_id)
);

-- Razorpay order/payment ledger for subscription & promotion purchases
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
    UNIQUE (razorpay_order_id)
);

-- ============================================================
-- ADDITIVE COLUMNS (no-op on a fresh install; fills gaps on an
-- existing database created before these were introduced)
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS state                TEXT DEFAULT '';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email                TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS queue_ban_until      TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS queue_ban_categories JSONB DEFAULT '{}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token            TEXT;

ALTER TABLE shops ADD COLUMN IF NOT EXISTS state         TEXT DEFAULT '';
ALTER TABLE shops ADD COLUMN IF NOT EXISTS opening_hours TEXT;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS latitude      DOUBLE PRECISION;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS longitude     DOUBLE PRECISION;

ALTER TABLE services ADD COLUMN IF NOT EXISTS duration_minutes INTEGER NOT NULL DEFAULT 15;

ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS service_ids            UUID[] NOT NULL DEFAULT '{}';
ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS total_duration_minutes INTEGER;

-- Widen the notifications.type check to include 'scheme' (added after 'promotion')
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'scheme', 'queue_update', 'coming'));

-- ============================================================
-- INDEXES
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_active_queue_per_user_shop
    ON queue_entries(shop_id, user_id)
    WHERE status IN ('waiting', 'serving');

-- One active queue entry per user across ALL shops (supersedes the
-- per-shop index above, kept alongside it — both are harmless together)
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_queue_per_user
    ON queue_entries(user_id)
    WHERE status IN ('waiting', 'serving');

CREATE INDEX IF NOT EXISTS idx_queue_entries_shop_status ON queue_entries(shop_id, status, token_number);
CREATE INDEX IF NOT EXISTS idx_queue_entries_user        ON queue_entries(user_id, status);
CREATE INDEX IF NOT EXISTS idx_shops_city_category       ON shops(city, category);
CREATE INDEX IF NOT EXISTS idx_shops_location            ON shops(latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_user        ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_subscriptions_shop        ON subscriptions(shop_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_staff_members_shop        ON staff_members(shop_id, is_active);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_shop_id       ON shop_reviews(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id       ON shop_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_created_at    ON shop_reviews(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_shop_id  ON payment_transactions(shop_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_owner_id ON payment_transactions(owner_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status   ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_profiles_email                ON profiles(email);

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

DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_shops_updated_at ON shops;
CREATE TRIGGER update_shops_updated_at
    BEFORE UPDATE ON shops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS update_promotions_updated_at ON promotions;
CREATE TRIGGER update_promotions_updated_at
    BEFORE UPDATE ON promotions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- QUEUE FUNCTIONS (latest service-aware versions)
-- ============================================================

CREATE OR REPLACE FUNCTION join_queue_v2(
    p_shop_id                UUID,
    p_user_id                UUID,
    p_staff_id               UUID    DEFAULT NULL,   -- ignored, kept for API compat
    p_service_id             UUID    DEFAULT NULL,
    p_service_ids            UUID[]  DEFAULT '{}',
    p_total_duration_minutes INTEGER DEFAULT NULL
)
RETURNS queue_entries AS $$
DECLARE
    v_shop  shops%ROWTYPE;
    v_token INTEGER;
    v_entry queue_entries%ROWTYPE;
    v_sid   UUID;
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

ALTER TABLE profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE shops               ENABLE ROW LEVEL SECURITY;
ALTER TABLE services             ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_entries        ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_members        ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_reviews         ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- Profiles
DROP POLICY IF EXISTS "profiles_read_all"   ON profiles;
CREATE POLICY "profiles_read_all"   ON profiles FOR SELECT USING (true);
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE USING (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Shops
DROP POLICY IF EXISTS "shops_read_all" ON shops;
CREATE POLICY "shops_read_all"     ON shops FOR SELECT USING (true);
DROP POLICY IF EXISTS "shops_insert_owner" ON shops;
CREATE POLICY "shops_insert_owner" ON shops FOR INSERT WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "shops_update_owner" ON shops;
CREATE POLICY "shops_update_owner" ON shops FOR UPDATE USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "shops_delete_owner" ON shops;
CREATE POLICY "shops_delete_owner" ON shops FOR DELETE USING (auth.uid() = owner_id);

-- Services
DROP POLICY IF EXISTS "services_read_all" ON services;
CREATE POLICY "services_read_all"     ON services FOR SELECT USING (true);
DROP POLICY IF EXISTS "services_modify_owner" ON services;
CREATE POLICY "services_modify_owner" ON services FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Queue entries
DROP POLICY IF EXISTS "queue_read_own" ON queue_entries;
CREATE POLICY "queue_read_own" ON queue_entries FOR SELECT USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
DROP POLICY IF EXISTS "queue_insert_customer" ON queue_entries;
CREATE POLICY "queue_insert_customer"   ON queue_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "queue_update_own_cancel" ON queue_entries;
CREATE POLICY "queue_update_own_cancel" ON queue_entries FOR UPDATE USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Notifications
DROP POLICY IF EXISTS "notifications_read_own" ON notifications;
CREATE POLICY "notifications_read_own"   ON notifications FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "notifications_update_own" ON notifications;
CREATE POLICY "notifications_update_own" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- Subscriptions
DROP POLICY IF EXISTS "subscriptions_read_owner" ON subscriptions;
CREATE POLICY "subscriptions_read_owner"   ON subscriptions FOR SELECT USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
DROP POLICY IF EXISTS "subscriptions_insert_owner" ON subscriptions;
CREATE POLICY "subscriptions_insert_owner" ON subscriptions FOR INSERT WITH CHECK (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
DROP POLICY IF EXISTS "subscriptions_update_owner" ON subscriptions;
CREATE POLICY "subscriptions_update_owner" ON subscriptions FOR UPDATE USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Promotions
DROP POLICY IF EXISTS "promotions_read_all" ON promotions;
CREATE POLICY "promotions_read_all"     ON promotions FOR SELECT USING (true);
DROP POLICY IF EXISTS "promotions_modify_owner" ON promotions;
CREATE POLICY "promotions_modify_owner" ON promotions FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Staff members
DROP POLICY IF EXISTS "staff_read_all" ON staff_members;
CREATE POLICY "staff_read_all"     ON staff_members FOR SELECT USING (true);
DROP POLICY IF EXISTS "staff_modify_owner" ON staff_members;
CREATE POLICY "staff_modify_owner" ON staff_members FOR ALL USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Queue events
DROP POLICY IF EXISTS "queue_events_read_owner" ON queue_events;
CREATE POLICY "queue_events_read_owner" ON queue_events FOR SELECT USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- Shop reviews — public read, owner-of-review write/delete
DROP POLICY IF EXISTS "Public read reviews" ON shop_reviews;
CREATE POLICY "Public read reviews"
    ON shop_reviews FOR SELECT
    USING (true);
DROP POLICY IF EXISTS "Users insert own reviews" ON shop_reviews;
CREATE POLICY "Users insert own reviews"
    ON shop_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users delete own reviews" ON shop_reviews;
CREATE POLICY "Users delete own reviews"
    ON shop_reviews FOR DELETE
    USING (auth.uid() = user_id);

-- Payment transactions — shop owner can read their own; all writes go
-- through the backend's service-role key after signature verification.
DROP POLICY IF EXISTS "Owners read own transactions" ON payment_transactions;
CREATE POLICY "Owners read own transactions"
    ON payment_transactions FOR SELECT
    USING (auth.uid() = owner_id);

-- ============================================================
-- Done. Every table, column, index, function, trigger, and RLS
-- policy in the current NOWAIT backend is now present.
-- ============================================================
