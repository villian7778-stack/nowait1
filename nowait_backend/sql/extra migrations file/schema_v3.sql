-- ============================================================
-- NOWAIT Schema V3 — Run after schema_v2.sql
-- Allows virtual staff members (added by name, no app account).
-- ============================================================

-- Drop FK constraint and NOT NULL so user_id can be NULL for virtual staff
ALTER TABLE staff_members DROP CONSTRAINT IF EXISTS staff_members_user_id_fkey;
ALTER TABLE staff_members ALTER COLUMN user_id DROP NOT NULL;

-- Update UNIQUE constraint: a shop can have multiple virtual staff
-- (NULL = virtual, non-NULL = real user, each real user unique per shop)
ALTER TABLE staff_members DROP CONSTRAINT IF EXISTS staff_members_shop_id_user_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_members_shop_real_user
    ON staff_members(shop_id, user_id)
    WHERE user_id IS NOT NULL;

-- queue_entries.staff_id references staff_members implicitly via service logic.
-- No schema change needed there — staff_id stores the staff_members.user_id
-- or NULL when unassigned. Virtual staff queues are not supported for now.
