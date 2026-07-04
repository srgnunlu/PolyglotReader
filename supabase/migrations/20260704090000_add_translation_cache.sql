-- Translation cache: stores per-user Gemini translation results keyed by a hash of
-- (normalized source text + target language) so repeated selections resolve instantly
-- and sync across devices.
CREATE TABLE IF NOT EXISTS translation_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source_hash TEXT NOT NULL,
    source_text TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    target_lang TEXT NOT NULL DEFAULT 'tr',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_translation_per_user UNIQUE (user_id, source_hash)
);

CREATE INDEX IF NOT EXISTS idx_translation_cache_user_hash
    ON translation_cache (user_id, source_hash);

ALTER TABLE translation_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own translations"
    ON translation_cache FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own translations"
    ON translation_cache FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own translations"
    ON translation_cache FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own translations"
    ON translation_cache FOR DELETE
    USING (auth.uid() = user_id);
