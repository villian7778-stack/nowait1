-- ============================================================
-- LOCKDOWN: make the backend the ONLY way to touch the database
-- ============================================================
-- Why: the Supabase ANON key ships inside the mobile app, and logged-in users also
-- hold a JWT. With the old permissive RLS policies, anyone could skip the FastAPI
-- backend and call Supabase's REST API directly, e.g.
--   * read every profile (names, phones, emails)        -- profiles_read_all
--   * insert their own subscription row for free        -- subscriptions_insert_owner
--   * create a paid "Featured Promotion" for free       -- promotions_modify_owner
--   * join queues / edit shops bypassing business rules -- queue_*/shops_* policies
--   * upload/delete any shop image in Storage
-- The Flutter app only uses Supabase for sign-in (auth); every data call goes through
-- the backend, which uses the service_role key (that key bypasses RLS by design).
--
-- This script is idempotent and safe to re-run. Run it once in Supabase -> SQL Editor.
-- After it runs: RLS stays ON for every table with NO policies (= deny all for
-- anon/authenticated); only the backend (service_role) can read/write.
-- ============================================================

-- 1. Drop every policy on the app's tables (whatever it was named) ---------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles','shops','services','subscriptions','promotions',
                        'queue_entries','notifications','staff_members','queue_events',
                        'shop_reviews','payment_transactions','shop_staff','reviews')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- 2. Make sure RLS is enabled everywhere (idempotent) ----------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['profiles','shops','services','subscriptions','promotions',
                           'queue_entries','notifications','staff_members','queue_events',
                           'shop_reviews','payment_transactions']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    END IF;
  END LOOP;
END $$;

-- 3. Belt and braces: client roles get no table privileges at all ----------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;

-- 4. The queue functions are SECURITY DEFINER: only the backend may call them ----
--    (otherwise anyone could POST /rest/v1/rpc/join_queue_v2 as any user).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('join_queue','join_queue_v2','advance_queue_v2','skip_customer_v2')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
    -- pin the search_path so a SECURITY DEFINER function can't be hijacked
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;

-- 5. Storage: only the backend uploads/deletes shop images -----------------------
--    (public READ stays: the bucket is public so image URLs load in the app.)
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete" ON storage.objects;

-- ============================================================
-- Verify (optional): should return no rows for the public tables above
--   SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public';
-- ============================================================
