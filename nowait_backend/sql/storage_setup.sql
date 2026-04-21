-- ============================================================
-- Supabase Storage Setup for NOWAIT Shop Images
-- ============================================================
-- Run these steps ONCE in your Supabase project.
-- Bucket must be created manually via the dashboard (step 1),
-- then run the SQL below in the SQL Editor (step 2).
-- ============================================================


-- ── Step 1: Create the bucket (Dashboard only) ─────────────
-- Go to: Supabase Dashboard → Storage → New Bucket
--   Name        : shop-images
--   Public      : ON  (enables public URLs without auth)
-- Click "Create bucket"


-- ── Step 2: RLS Policies (run in SQL Editor) ───────────────

-- Allow anyone to read public bucket images
CREATE POLICY "Public read access"
ON storage.objects FOR SELECT
USING (bucket_id = 'shop-images');

-- Allow authenticated users to upload shop images
CREATE POLICY "Authenticated users can upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'shop-images');

-- Allow authenticated users to delete shop images
CREATE POLICY "Authenticated users can delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'shop-images');


-- ── Notes ──────────────────────────────────────────────────
-- Bucket name referenced in backend: app/services/shop_service.py → _STORAGE_BUCKET = "shop-images"
-- Images are stored at path: {shop_id}/{uuid}.{ext}
-- Public URL format: https://<project>.supabase.co/storage/v1/object/public/shop-images/{shop_id}/{uuid}.{ext}
-- Max images per shop: 10 (enforced in shop_service.py → MAX_SHOP_IMAGES)
