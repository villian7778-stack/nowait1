-- Owner "New customer joined" notification + push. Safe to run more than once.
-- Also included in final_consolidated.sql.

-- New notification type for the shop owner when a customer joins the queue online
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('your_turn', 'almost_there', 'skipped', 'promotion', 'scheme', 'queue_update', 'coming', 'new_customer'));

-- The owner's on/off choice for that push (the bell switch on the owner Profile tab)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS new_customer_alerts BOOLEAN NOT NULL DEFAULT TRUE;
