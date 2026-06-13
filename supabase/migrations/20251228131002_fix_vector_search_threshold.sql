-- match_document_chunks_v2 fonksiyonunu düzelt
-- Similarity threshold'u düşür (0.50 -> 0.35)
DROP FUNCTION IF EXISTS match_document_chunks_v2(text, text, integer, double precision);

CREATE OR REPLACE FUNCTION match_document_chunks_v2(
    query_embedding text,
    match_file_id text,
    match_count integer DEFAULT 16,
    similarity_threshold double precision DEFAULT 0.35
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    chunk_index integer,
    content text,
    page_number integer,
    similarity double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    embedding_array vector(768);
    file_uuid uuid;
BEGIN
    embedding_array := query_embedding::vector(768);
    file_uuid := match_file_id::uuid;
    
    RETURN QUERY
    SELECT 
        dc.id,
        dc.file_id,
        dc.chunk_index,
        dc.content,
        dc.page_number,
        (1 - (dc.embedding <=> embedding_array))::float as similarity
    FROM document_chunks dc
    WHERE dc.file_id = file_uuid
      AND (1 - (dc.embedding <=> embedding_array)) >= similarity_threshold
    ORDER BY dc.embedding <=> embedding_array
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION match_document_chunks_v2 TO authenticated;
GRANT EXECUTE ON FUNCTION match_document_chunks_v2 TO anon;
