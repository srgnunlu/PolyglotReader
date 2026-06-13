
-- Recreate function with proper type cast for file_id comparison
CREATE FUNCTION match_document_chunks(
    query_embedding vector(768),
    match_file_id text,
    match_count int DEFAULT 5
)
RETURNS TABLE (
    id uuid,
    file_id text,
    chunk_index int,
    content text,
    page_number int,
    similarity float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id,
        dc.file_id::text,
        dc.chunk_index,
        dc.content,
        dc.page_number,
        (1 - (dc.embedding <=> query_embedding))::float as similarity
    FROM document_chunks dc
    WHERE dc.file_id::text = match_file_id
      AND dc.embedding IS NOT NULL
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION match_document_chunks TO authenticated;
GRANT EXECUTE ON FUNCTION match_document_chunks TO anon;
