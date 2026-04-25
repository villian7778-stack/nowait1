-- Migration: add state column to profiles
-- Run this in Supabase SQL Editor if you already have an existing database
-- (i.e. you ran schema.sql before this change was added).
-- Safe to run multiple times — ALTER TABLE ... ADD COLUMN IF NOT EXISTS is idempotent.

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';
