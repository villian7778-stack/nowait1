-- Migration: Email/password authentication replaces phone OTP
-- Run this in the Supabase SQL Editor. Safe to re-run.
--
-- Adds profiles.email for the new email/password + Google login system.
-- The mobile number column (profiles.phone) is untouched — it remains
-- required, unique, and stored on the profile, just no longer used for
-- authentication.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
