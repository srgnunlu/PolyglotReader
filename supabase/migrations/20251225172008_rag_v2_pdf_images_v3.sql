-- V2 Fonksiyon (Benzerlik Eşikli)
CREATE OR REPLACE FUNCTION match_document_chunks_v2(
    query_embedding vector(768),
    match_file_id text,
    match_count int DEFAULT 8,
    similarity_threshold float DEFAULT 0.65
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
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id,
        dc.file_id,
        dc.chunk_index,
        dc.content,
        dc.page_number,
        1 - (dc.embedding <=> query_embedding) as similarity
    FROM document_chunks dc
    WHERE dc.file_id = match_file_id
      AND dc.embedding IS NOT NULL
      AND (1 - (dc.embedding <=> query_embedding)) >= similarity_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION match_document_chunks_v2 TO authenticated;
