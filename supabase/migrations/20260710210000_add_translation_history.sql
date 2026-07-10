-- Translation history: every completed quick-translation is kept per user so
-- the Notebook can offer a "Çeviriler" category for spaced review. Deduped by
-- a hash of the source text per file, so re-translating the same selection
-- (e.g. via the local cache) never creates duplicate rows.
CREATE TABLE IF NOT EXISTS translation_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    source_text TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    source_hash TEXT GENERATED ALWAYS AS (md5(source_text)) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_translation_history_entry UNIQUE (user_id, file_id, source_hash)
);

CREATE INDEX IF NOT EXISTS idx_translation_history_user_created
    ON translation_history (user_id, created_at DESC);

ALTER TABLE translation_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own translation history"
    ON translation_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own translation history"
    ON translation_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own translation history"
    ON translation_history FOR DELETE
    USING (auth.uid() = user_id);
