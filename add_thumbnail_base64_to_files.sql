-- Phase B performance: store a small pre-rendered first-page thumbnail on the
-- file row so the library grid no longer downloads the entire PDF per card
-- just to draw a preview. Mirrors the iOS thumbnail convention (base64 PNG).
-- Nullable + idempotent: existing rows fall back to live rendering until their
-- next thumbnail is generated.
ALTER TABLE public.files ADD COLUMN IF NOT EXISTS thumbnail_base64 text;
