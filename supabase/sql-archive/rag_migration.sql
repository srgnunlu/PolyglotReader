-- =====================================================
-- RAG (Retrieval-Augmented Generation) Migration Script
-- PolyglotReader için pgvector tabanlı doküman chunk sistemi
-- =====================================================

-- 1. pgvector extension'ı aktif et
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. document_chunks tablosu oluştur
CREATE TABLE IF NOT EXISTS document_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id TEXT NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    page_number INTEGER,
    embedding vector(768),  -- Gemini text-embedding-004 boyutu: 768
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(file_id, chunk_index)
);

-- 3. Vektör araması için index oluştur
-- ivfflat daha hızlı arama sağlar, lists parametresi chunk sayısına göre ayarlanabilir
CREATE INDEX IF NOT EXISTS document_chunks_embedding_idx 
ON document_chunks 
USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100);

-- 4. file_id için index (hızlı silme ve filtreleme)
CREATE INDEX IF NOT EXISTS document_chunks_file_id_idx 
ON document_chunks(file_id);

-- 5. RLS (Row Level Security) politikası
ALTER TABLE document_chunks ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar sadece kendi dosyalarının chunk'larına erişebilir
CREATE POLICY "Users can access their own document chunks"
ON document_chunks FOR ALL
USING (
    file_id IN (
        SELECT id FROM files WHERE user_id = auth.uid()::text
    )
);

-- 6. Vektör benzerlik araması için RPC fonksiyonu
CREATE OR REPLACE FUNCTION match_document_chunks(
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
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- 7. Grant permissions
GRANT EXECUTE ON FUNCTION match_document_chunks TO authenticated;
GRANT SELECT, INSERT, DELETE ON document_chunks TO authenticated;

-- =====================================================
-- V2 GÜNCELLEMELER - Benzerlik Eşiği + Görsel Sistemi
-- =====================================================

-- 8. Geliştirilmiş vektör benzerlik araması (eşik filtreli)
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

-- =====================================================
-- PDF GÖRSEL METADATA SİSTEMİ
-- =====================================================

-- 9. pdf_images tablosu oluştur
CREATE TABLE IF NOT EXISTS pdf_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    page_number INT NOT NULL,
    image_index INT NOT NULL DEFAULT 0,       -- Aynı sayfada birden fazla görsel
    bounds JSONB,                              -- {x, y, width, height}
    thumbnail_base64 TEXT,                     -- Küçük önizleme (lazy, nullable)
    caption TEXT,                              -- AI tarafından oluşturulan açıklama
    caption_embedding vector(768),             -- Caption için embedding (arama için)
    analyzed_at TIMESTAMP WITH TIME ZONE,      -- Analiz yapıldı mı
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(file_id, page_number, image_index)
);

-- 10. Görsel araması için indexler
CREATE INDEX IF NOT EXISTS pdf_images_file_id_idx ON pdf_images(file_id);
CREATE INDEX IF NOT EXISTS pdf_images_page_idx ON pdf_images(file_id, page_number);

-- 11. Caption embedding için vektör index
CREATE INDEX IF NOT EXISTS pdf_images_caption_embedding_idx 
ON pdf_images 
USING ivfflat (caption_embedding vector_cosine_ops) 
WITH (lists = 50);

-- 12. RLS politikası
ALTER TABLE pdf_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can access their own pdf images"
ON pdf_images FOR ALL
USING (
    file_id IN (
        SELECT id::uuid FROM files WHERE user_id = auth.uid()::text
    )
);

-- 13. Sayfa bazlı görsel sorgulama fonksiyonu
CREATE OR REPLACE FUNCTION get_page_images(
    target_file_id uuid,
    target_page int
)
RETURNS TABLE (
    id uuid,
    page_number int,
    image_index int,
    bounds jsonb,
    thumbnail_base64 text,
    caption text,
    analyzed_at timestamp with time zone
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pi.id,
        pi.page_number,
        pi.image_index,
        pi.bounds,
        pi.thumbnail_base64,
        pi.caption,
        pi.analyzed_at
    FROM pdf_images pi
    WHERE pi.file_id = target_file_id
      AND pi.page_number = target_page
    ORDER BY pi.image_index;
END;
$$;

GRANT EXECUTE ON FUNCTION get_page_images TO authenticated;

-- 14. Görsel caption'larında arama
CREATE OR REPLACE FUNCTION search_image_captions(
    query_embedding vector(768),
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
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pi.id,
        pi.page_number,
        pi.caption,
        1 - (pi.caption_embedding <=> query_embedding) as similarity
    FROM pdf_images pi
    WHERE pi.file_id = target_file_id
      AND pi.caption_embedding IS NOT NULL
      AND (1 - (pi.caption_embedding <=> query_embedding)) >= similarity_threshold
    ORDER BY pi.caption_embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION search_image_captions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON pdf_images TO authenticated;
