-- =====================================================
-- Fix Ambiguous Column Reference in RAG Functions
-- =====================================================

-- Fix match_chunks - use parameter prefix to avoid ambiguity
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
        dc.id,
        dc.content,
        (1 - (dc.embedding <=> query_embedding))::float as similarity,
        dc.page_number
    FROM document_chunks dc
    WHERE 
        dc.file_id = match_chunks.file_id::uuid
        AND (1 - (dc.embedding <=> query_embedding)) > match_chunks.match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_chunks.match_count;
END;
$$;

-- Fix search_chunks_bm25 - use parameter prefix
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
        dc.id,
        dc.content,
        ts_rank(dc.ts_content, plainto_tsquery('simple', search_chunks_bm25.search_query))::float as rank,
        dc.page_number
    FROM document_chunks dc
    WHERE 
        dc.file_id = search_chunks_bm25.search_file_id::uuid
        AND dc.ts_content @@ plainto_tsquery('simple', search_chunks_bm25.search_query)
    ORDER BY rank DESC
    LIMIT search_chunks_bm25.match_count;
END;
$$;

-- =====================================================
-- Migration complete!
-- =====================================================
