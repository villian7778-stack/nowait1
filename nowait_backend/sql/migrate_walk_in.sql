-- Walk-in customers (owner adds a customer at the counter, with no account).
-- Safe to run more than once. Also included in final_consolidated.sql.

-- Walk-in customers: added by the owner at the counter. They have no account, so user_id is
-- NULL for them (and only for them - the check below), is_walk_in marks them in queue lists.
-- The partial UNIQUE indexes on user_id treat NULLs as distinct, so walk-ins never clash.
ALTER TABLE queue_entries ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE queue_entries ADD COLUMN IF NOT EXISTS is_walk_in BOOLEAN NOT NULL DEFAULT FALSE;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'queue_entries_walk_in_user') THEN
    ALTER TABLE queue_entries ADD CONSTRAINT queue_entries_walk_in_user
      CHECK ((is_walk_in AND user_id IS NULL) OR (NOT is_walk_in AND user_id IS NOT NULL));
  END IF;
END $$;


-- Owner adds a walk-in customer. Same shop-row lock and the same token sequence as
-- join_queue_v2, so an online join at the same moment can never get the same token.
-- Allowed while the queue is paused (pause only stops online joins) and past the queue limit
-- (the owner decides in person); the shop must be open and subscribed.
CREATE OR REPLACE FUNCTION add_walk_in_v1(
    p_shop_id                UUID,
    p_service_ids            UUID[]  DEFAULT '{}',
    p_total_duration_minutes INTEGER DEFAULT NULL
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

    IF NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE shop_id = p_shop_id
          AND status = 'active'
          AND expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'NO_SUBSCRIPTION: Shop does not have an active subscription';
    END IF;

    SELECT COALESCE(MAX(token_number), 0) + 1
    INTO v_token
    FROM queue_entries
    WHERE shop_id = p_shop_id;

    INSERT INTO queue_entries (
        shop_id, user_id, is_walk_in, token_number, status,
        service_id, service_ids, total_duration_minutes
    )
    VALUES (
        p_shop_id, NULL, TRUE, v_token, 'waiting',
        CASE WHEN array_length(p_service_ids, 1) > 0 THEN p_service_ids[1] ELSE NULL END,
        p_service_ids, p_total_duration_minutes
    )
    RETURNING * INTO v_entry;

    RETURN v_entry;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'add_walk_in_v1'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;
