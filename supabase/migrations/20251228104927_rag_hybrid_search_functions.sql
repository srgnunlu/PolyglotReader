-- =====================================================
-- Hybrid Search ve Image Caption Search Fonksiyonları
-- =====================================================

-- 1. Hybrid Search RPC (Vector + BM25 birleşik)
CREATE OR REPLACE FUNCTION hybrid_search_chunks(
    query_embedding text,
    search_query text,
    target_file_id uuid,
    vector_weight float DEFAULT 0.7,
    bm25_weight float DEFAULT 0.3,
    match_count int DEFAULT 8,
    similarity_threshold float DEFAULT 0.55
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    chunk_index int,
    content text,
    page_number int,
    vector_score float,
    bm25_score float,
    combined_score float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    embedding_array vector(768);
BEGIN
    embedding_array := query_embedding::vector(768);
    
    RETURN QUERY
    WITH vector_results AS (
        SELECT 
            dc.id,
            dc.file_id,
            dc.chunk_index,
            dc.content,
            dc.page_number,
            (1 - (dc.embedding <=> embedding_array))::float as v_score,
            ROW_NUMBER() OVER (ORDER BY dc.embedding <=> embedding_array) as v_rank
        FROM document_chunks dc
        WHERE dc.file_id = target_file_id
          AND (1 - (dc.embedding <=> embedding_array)) >= similarity_threshold
        LIMIT match_count * 2
    ),
    bm25_results AS (
        SELECT 
            dc.id,
            ts_rank(dc.ts_content, plainto_tsquery('simple', search_query))::float as b_score,
            ROW_NUMBER() OVER (ORDER BY ts_rank(dc.ts_content, plainto_tsquery('simple', search_query)) DESC) as b_rank
        FROM document_chunks dc
        WHERE dc.file_id = target_file_id
          AND dc.ts_content @@ plainto_tsquery('simple', search_query)
        LIMIT match_count * 2
    ),
    combined AS (
        SELECT 
            vr.id,
            vr.file_id,
            vr.chunk_index,
            vr.content,
            vr.page_number,
            vr.v_score as vector_score,
            COALESCE(br.b_score, 0) as bm25_score,
            (vector_weight * (1.0 / (60 + vr.v_rank))) + 
            (bm25_weight * (1.0 / (60 + COALESCE(br.b_rank, 1000)))) as combined_score
        FROM vector_results vr
        LEFT JOIN bm25_results br ON vr.id = br.id
        
        UNION
        
        SELECT 
            dc.id,
            dc.file_id,
            dc.chunk_index,
            dc.content,
            dc.page_number,
            0 as vector_score,
            br.b_score as bm25_score,
            bm25_weight * (1.0 / (60 + br.b_rank)) as combined_score
        FROM bm25_results br
        JOIN document_chunks dc ON dc.id = br.id
        WHERE br.id NOT IN (SELECT vr2.id FROM vector_results vr2)
    )
    SELECT 
        c.id,
        c.file_id,
        c.chunk_index,
        c.content,
        c.page_number,
        c.vector_score,
        c.bm25_score,
        c.combined_score
    FROM combined c
    ORDER BY c.combined_score DESC
    LIMIT match_count;
END;
$$;

-- RPC fonksiyonuna erişim izni
GRANT EXECUTE ON FUNCTION hybrid_search_chunks(text, text, uuid, float, float, int, float) TO authenticated;
GRANT EXECUTE ON FUNCTION hybrid_search_chunks(text, text, uuid, float, float, int, float) TO anon;

-- 2. Image Caption Search RPC (Görsel RAG için)
CREATE OR REPLACE FUNCTION search_image_captions(
    query_embedding text,
    target_file_id uuid,
    match_count int DEFAULT 3,
    similarity_threshold float DEFAULT 0.6
)
RETURNS TABLE (
    id uuid,
    page_number int,
    caption text,
    similarity float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    embedding_array vector(768);
BEGIN
    embedding_array := query_embedding::vector(768);
    
    RETURN QUERY
    SELECT 
        pi.id,
        pi.page_number,
        pi.caption,
        (1 - (pi.caption_embedding <=> embedding_array))::float as similarity
    FROM pdf_images pi
    WHERE pi.file_id = target_file_id
      AND pi.caption IS NOT NULL
      AND pi.caption_embedding IS NOT NULL
      AND (1 - (pi.caption_embedding <=> embedding_array)) >= similarity_threshold
    ORDER BY pi.caption_embedding <=> embedding_array
    LIMIT match_count;
END;
$$;

-- RPC fonksiyonuna erişim izni
GRANT EXECUTE ON FUNCTION search_image_captions(text, uuid, int, float) TO authenticated;
GRANT EXECUTE ON FUNCTION search_image_captions(text, uuid, int, float) TO anon;
