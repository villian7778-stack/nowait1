-- ============================================================
-- NOWAIT Schema V2 — Run in Supabase SQL Editor AFTER schema.sql
-- Adds: staff management, queue controls, analytics, city/history
-- ============================================================

-- ============================================================
-- COLUMN ADDITIONS (backward-compatible — all nullable/default)
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT DEFAULT NULL;

ALTER TABLE shops ADD COLUMN IF NOT EXISTS queue_paused BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS max_queue_size INTEGER DEFAULT NULL;

ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS staff_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS service_id UUID REFERENCES services(id) ON DELETE SET NULL;
ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS actual_service_minutes INTEGER DEFAULT NULL;
ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS coming_at TIMESTAMPTZ DEFAULT NULL;

-- Update notifications type CHECK to include 'coming'
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'queue_update', 'coming'));

-- ============================================================
-- NEW TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS staff_members (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id      UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    added_by     UUID NOT NULL REFERENCES profiles(id),
    display_name TEXT DEFAULT '',
    is_owner_staff BOOLEAN NOT NULL DEFAULT FALSE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    avg_service_minutes DECIMAL(5,2) DEFAULT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(shop_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_staff_members_shop   ON staff_members(shop_id, is_active);
CREATE INDEX IF NOT EXISTS idx_staff_members_user   ON staff_members(user_id, is_active);

CREATE TABLE IF NOT EXISTS queue_events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    staff_id    UUID REFERENCES profiles(id) ON DELETE SET NULL,
    entry_id    UUID REFERENCES queue_entries(id) ON DELETE SET NULL,
    event_type  TEXT NOT NULL CHECK (event_type IN (
                    'joined','serving_started','completed','skipped',
                    'cancelled','paused','resumed')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_queue_events_shop_time ON queue_events(shop_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_queue_events_staff     ON queue_events(staff_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_queue_entries_shop_date ON queue_entries(shop_id, joined_at, status);
CREATE INDEX IF NOT EXISTS idx_queue_entries_staff    ON queue_entries(staff_id, status, token_number);

-- ============================================================
-- RLS FOR NEW TABLES
-- ============================================================

ALTER TABLE staff_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_events   ENABLE ROW LEVEL SECURITY;

-- staff_members: shop owner can manage; staff can read their own row
CREATE POLICY "staff_read_own_shop" ON staff_members FOR SELECT USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "staff_insert_owner" ON staff_members FOR INSERT WITH CHECK (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "staff_update_owner" ON staff_members FOR UPDATE USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);
CREATE POLICY "staff_delete_owner" ON staff_members FOR DELETE USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id)
);

-- queue_events: shop owner and staff of the shop can read
CREATE POLICY "events_read_shop" ON queue_events FOR SELECT USING (
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id) OR
    EXISTS (SELECT 1 FROM staff_members sm WHERE sm.shop_id = queue_events.shop_id AND sm.user_id = auth.uid() AND sm.is_active)
);
CREATE POLICY "events_insert_service" ON queue_events FOR INSERT WITH CHECK (true);

-- Update queue_entries RLS so active staff of the shop can also read/update
DROP POLICY IF EXISTS "queue_read_own" ON queue_entries;
CREATE POLICY "queue_read_own" ON queue_entries FOR SELECT USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id) OR
    EXISTS (SELECT 1 FROM staff_members sm WHERE sm.shop_id = queue_entries.shop_id AND sm.user_id = auth.uid() AND sm.is_active)
);

DROP POLICY IF EXISTS "queue_update_own_cancel" ON queue_entries;
CREATE POLICY "queue_update_own_cancel" ON queue_entries FOR UPDATE USING (
    auth.uid() = user_id OR
    auth.uid() = (SELECT owner_id FROM shops WHERE id = shop_id) OR
    EXISTS (SELECT 1 FROM staff_members sm WHERE sm.shop_id = queue_entries.shop_id AND sm.user_id = auth.uid() AND sm.is_active)
);

-- ============================================================
-- NEW / UPDATED QUEUE FUNCTIONS
-- ============================================================

-- join_queue_v2: adds staff_id, max_queue_size and queue_paused checks
CREATE OR REPLACE FUNCTION join_queue_v2(
    p_shop_id   UUID,
    p_user_id   UUID,
    p_staff_id  UUID DEFAULT NULL,
    p_service_id UUID DEFAULT NULL
)
RETURNS queue_entries AS $$
DECLARE
    v_shop    shops%ROWTYPE;
    v_staff   staff_members%ROWTYPE;
    v_token   INTEGER;
    v_count   INTEGER;
    v_entry   queue_entries%ROWTYPE;
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

    -- Check max queue size (shop-level)
    IF v_shop.max_queue_size IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM queue_entries
        WHERE shop_id = p_shop_id AND status IN ('waiting', 'serving');

        IF v_count >= v_shop.max_queue_size THEN
            RAISE EXCEPTION 'QUEUE_FULL: Queue has reached its maximum capacity';
        END IF;
    END IF;

    -- If staff_id given, verify staff is active and not paused
    IF p_staff_id IS NOT NULL THEN
        SELECT * INTO v_staff FROM staff_members
        WHERE shop_id = p_shop_id AND user_id = p_staff_id AND is_active = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'INVALID_STAFF: Staff member not found or inactive';
        END IF;
    END IF;

    SELECT COALESCE(MAX(token_number), 0) + 1
    INTO v_token
    FROM queue_entries
    WHERE shop_id = p_shop_id;

    INSERT INTO queue_entries (shop_id, user_id, token_number, status, staff_id, service_id)
    VALUES (p_shop_id, p_user_id, v_token, 'waiting', p_staff_id, p_service_id)
    RETURNING * INTO v_entry;

    -- Log event
    INSERT INTO queue_events(shop_id, staff_id, entry_id, event_type)
    VALUES (p_shop_id, p_staff_id, v_entry.id, 'joined');

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- advance_queue_v2: actor can be owner or staff (auth checked in service layer)
CREATE OR REPLACE FUNCTION advance_queue_v2(p_shop_id UUID, p_staff_id UUID DEFAULT NULL)
RETURNS TABLE(completed_entry queue_entries, next_entry queue_entries) AS $$
DECLARE
    v_completed queue_entries%ROWTYPE;
    v_next      queue_entries%ROWTYPE;
    v_actual    INTEGER;
BEGIN
    -- Mark current serving as completed
    IF p_staff_id IS NOT NULL THEN
        UPDATE queue_entries
        SET status = 'completed', served_at = NOW()
        WHERE shop_id = p_shop_id AND status = 'serving' AND staff_id = p_staff_id
        RETURNING * INTO v_completed;
    ELSE
        UPDATE queue_entries
        SET status = 'completed', served_at = NOW()
        WHERE shop_id = p_shop_id AND status = 'serving'
        RETURNING * INTO v_completed;
    END IF;

    -- Log completion
    IF v_completed.id IS NOT NULL THEN
        INSERT INTO queue_events(shop_id, staff_id, entry_id, event_type)
        VALUES (p_shop_id, p_staff_id, v_completed.id, 'completed');
    END IF;

    -- Get next waiting entry for this staff (or unassigned if no staff)
    IF p_staff_id IS NOT NULL THEN
        SELECT * INTO v_next
        FROM queue_entries
        WHERE shop_id = p_shop_id AND status = 'waiting' AND staff_id = p_staff_id
        ORDER BY token_number ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED;
    ELSE
        SELECT * INTO v_next
        FROM queue_entries
        WHERE shop_id = p_shop_id AND status = 'waiting'
        ORDER BY token_number ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED;
    END IF;

    IF FOUND THEN
        UPDATE queue_entries
        SET status = 'serving'
        WHERE id = v_next.id
        RETURNING * INTO v_next;

        INSERT INTO queue_events(shop_id, staff_id, entry_id, event_type)
        VALUES (p_shop_id, p_staff_id, v_next.id, 'serving_started');
    END IF;

    RETURN QUERY SELECT v_completed, v_next;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- skip_customer_v2: no owner check — auth done in service layer
CREATE OR REPLACE FUNCTION skip_customer_v2(p_entry_id UUID, p_staff_id UUID DEFAULT NULL)
RETURNS queue_entries AS $$
DECLARE
    v_entry queue_entries%ROWTYPE;
BEGIN
    UPDATE queue_entries
    SET status = 'skipped', served_at = NOW()
    WHERE id = p_entry_id AND status IN ('waiting', 'serving')
    RETURNING * INTO v_entry;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Entry not found or not skippable';
    END IF;

    INSERT INTO queue_events(shop_id, staff_id, entry_id, event_type)
    VALUES (v_entry.shop_id, p_staff_id, p_entry_id, 'skipped');

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger: auto-update staff avg_service_minutes when entry completes
CREATE OR REPLACE FUNCTION update_staff_avg_service()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND NEW.actual_service_minutes IS NOT NULL AND NEW.staff_id IS NOT NULL THEN
        UPDATE staff_members
        SET avg_service_minutes = (
            SELECT AVG(actual_service_minutes::DECIMAL)
            FROM queue_entries
            WHERE staff_id = NEW.staff_id
              AND status = 'completed'
              AND actual_service_minutes IS NOT NULL
        )
        WHERE user_id = NEW.staff_id AND shop_id = NEW.shop_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_staff_avg_service ON queue_entries;
CREATE TRIGGER trigger_staff_avg_service
    AFTER UPDATE ON queue_entries
    FOR EACH ROW EXECUTE FUNCTION update_staff_avg_service();
