-- =====================================================
-- RAG Search Functions - Create match_chunks and fix search_chunks_bm25
-- =====================================================

-- 1. Create match_chunks function for vector similarity search
CREATE OR REPLACE FUNCTION match_chunks(
    query_embedding vector(768),
    match_threshold float,
    match_count int,
    file_id text
)
RETURNS TABLE (
    id uuid,
    content text,
    similarity float,
    page_number int
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        document_chunks.id,
        document_chunks.content,
        1 - (document_chunks.embedding <=> query_embedding) as similarity,
        document_chunks.page_number
    FROM document_chunks
    WHERE 
        document_chunks.file_id = file_id::uuid
        AND 1 - (document_chunks.embedding <=> query_embedding) > match_threshold
    ORDER BY document_chunks.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION match_chunks TO authenticated;

-- 2. Drop old search_chunks_bm25 and create new one with correct signature
DROP FUNCTION IF EXISTS search_chunks_bm25(text, uuid, integer);

CREATE OR REPLACE FUNCTION search_chunks_bm25(
    search_file_id text,
    search_query text,
    match_count int
)
RETURNS TABLE (
    id uuid,
    content text,
    rank float,
    page_number int
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        document_chunks.id,
        document_chunks.content,
        ts_rank(document_chunks.ts_content, plainto_tsquery('simple', search_query))::float as rank,
        document_chunks.page_number
    FROM document_chunks
    WHERE 
        document_chunks.file_id = search_file_id::uuid
        AND document_chunks.ts_content @@ plainto_tsquery('simple', search_query)
    ORDER BY rank DESC
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION search_chunks_bm25 TO authenticated;

-- 3. Ensure ts_content column and index exist
DO $$ 
BEGIN
    -- Add ts_content column if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'document_chunks' AND column_name = 'ts_content'
    ) THEN
        ALTER TABLE document_chunks ADD COLUMN ts_content tsvector;
    END IF;
END $$;

-- Create trigger function for auto-updating ts_content
CREATE OR REPLACE FUNCTION document_chunks_ts_content_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW.ts_content := to_tsvector('simple', NEW.content);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS document_chunks_ts_content_update ON document_chunks;
CREATE TRIGGER document_chunks_ts_content_update
    BEFORE INSERT OR UPDATE OF content ON document_chunks
    FOR EACH ROW
    EXECUTE FUNCTION document_chunks_ts_content_trigger();

-- Create index if missing
CREATE INDEX IF NOT EXISTS document_chunks_ts_content_idx 
    ON document_chunks USING gin(ts_content);

-- Update existing rows
UPDATE document_chunks 
SET ts_content = to_tsvector('simple', content) 
WHERE ts_content IS NULL;

-- =====================================================
-- Migration complete!
-- =====================================================
