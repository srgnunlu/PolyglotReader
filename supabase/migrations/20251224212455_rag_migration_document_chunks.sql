-- =====================================================
-- RAG (Retrieval-Augmented Generation) Migration Script
-- PolyglotReader için pgvector tabanlı doküman chunk sistemi
-- =====================================================

-- 1. pgvector extension'ı aktif et
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. document_chunks tablosu oluştur
CREATE TABLE IF NOT EXISTS document_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
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
        SELECT id FROM files WHERE user_id = auth.uid()
    )
);

-- 6. Vektör benzerlik araması için RPC fonksiyonu
CREATE OR REPLACE FUNCTION match_document_chunks(
    query_embedding vector(768),
    match_file_id uuid,
    match_count int DEFAULT 5
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
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dc.id,
        dc.file_id,
        dc.chunk_index,
        dc.content,
        dc.page_number,
        (1 - (dc.embedding <=> query_embedding))::float as similarity
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
