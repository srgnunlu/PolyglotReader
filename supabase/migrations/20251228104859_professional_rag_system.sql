-- =====================================================
-- Profesyonel RAG Sistemi Migration
-- =====================================================

-- 1. Document Chunks tablosuna tsvector kolonu ekle (BM25 için)
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

-- 4. File ID için index
CREATE INDEX IF NOT EXISTS idx_document_chunks_file_id 
ON document_chunks(file_id);
