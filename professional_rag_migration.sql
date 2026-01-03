-- =====================================================
-- Profesyonel RAG Sistemi Migration
-- Bu dosyayı Supabase SQL Editor'de çalıştırın
-- =====================================================

-- 1. Document Chunks tablosuna tsvector kolonu ekle (BM25 için)
-- =====================================================

-- Önce Turkish dictionary'nin var olup olmadığını kontrol et
-- Supabase'de varsayılan olarak 'turkish' config mevcut olmayabilir, 'simple' kullanacağız
ALTER TABLE document_chunks 
ADD COLUMN IF NOT EXISTS ts_content tsvector;

-- Mevcut içerikler için tsvector oluştur
UPDATE document_chunks 
SET ts_content = to_tsvector('simple', content)
WHERE ts_content IS NULL;

-- Trigger: Yeni chunk eklendiğinde otomatik tsvector oluştur
CREATE OR REPLACE FUNCTION document_chunks_tsvector_trigger()
RETURNS trigger AS $$
BEGIN
    NEW.ts_content := to_tsvector('simple', COALESCE(NEW.content, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tsvector_update ON document_chunks;
CREATE TRIGGER tsvector_update
    BEFORE INSERT OR UPDATE ON document_chunks
    FOR EACH ROW
    EXECUTE FUNCTION document_chunks_tsvector_trigger();

-- Full-text search index (GIN)
CREATE INDEX IF NOT EXISTS idx_document_chunks_ts_content 
ON document_chunks USING GIN(ts_content);

-- 2. BM25 Search RPC Fonksiyonu
-- =====================================================

CREATE OR REPLACE FUNCTION search_chunks_bm25(
    search_query text,
    target_file_id uuid,
    match_count int DEFAULT 8
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    chunk_index int,
    content text,
    page_number int,
    rank float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id,
        dc.file_id,
        dc.chunk_index,
        dc.content,
        dc.page_number,
        ts_rank(dc.ts_content, plainto_tsquery('simple', search_query))::float as rank
    FROM document_chunks dc
    WHERE dc.file_id = target_file_id
      AND dc.ts_content @@ plainto_tsquery('simple', search_query)
    ORDER BY rank DESC
    LIMIT match_count;
END;
$$;

-- RPC fonksiyonuna erişim izni
GRANT EXECUTE ON FUNCTION search_chunks_bm25(text, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION search_chunks_bm25(text, uuid, int) TO anon;

-- 3. Gelişmiş Vector Search RPC (eşik filtreli - v2)
-- =====================================================

CREATE OR REPLACE FUNCTION match_document_chunks_v2(
    query_embedding text,
    match_file_id text,
    match_count int DEFAULT 8,
    similarity_threshold float DEFAULT 0.60
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    chunk_index int,
    content text,
    page_number int,
    similarity float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    embedding_array vector(768);
    file_uuid uuid;
BEGIN
    -- Text'i vector'e çevir
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

-- RPC fonksiyonuna erişim izni
GRANT EXECUTE ON FUNCTION match_document_chunks_v2(text, text, int, float) TO authenticated;
GRANT EXECUTE ON FUNCTION match_document_chunks_v2(text, text, int, float) TO anon;

-- 4. Hybrid Search RPC (Vector + BM25 birleşik)
-- =====================================================

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
            -- RRF (Reciprocal Rank Fusion) formula
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

-- 5. Image Caption Search RPC (Görsel RAG için)
-- =====================================================

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

-- 6. Index optimizasyonları
-- =====================================================

-- Vector search için HNSW index (daha hızlı arama)
-- Not: Bu index büyük veri setlerinde önemli performans artışı sağlar
-- CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_hnsw 
-- ON document_chunks USING hnsw (embedding vector_cosine_ops);

-- Alternatif: IVFFlat index (daha az memory kullanır)
CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_ivfflat 
ON document_chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- File ID için index (sık kullanılan filtre)
CREATE INDEX IF NOT EXISTS idx_document_chunks_file_id 
ON document_chunks(file_id);

-- pdf_images tablosu için caption embedding index
CREATE INDEX IF NOT EXISTS idx_pdf_images_caption_embedding 
ON pdf_images USING ivfflat (caption_embedding vector_cosine_ops)
WITH (lists = 50);

-- =====================================================
-- Migration tamamlandı!
-- =====================================================

-- Kontrol sorguları:
-- SELECT * FROM pg_indexes WHERE tablename = 'document_chunks';
-- SELECT count(*) FROM document_chunks WHERE ts_content IS NOT NULL;
