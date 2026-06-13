-- =====================================================
-- RAG Index Optimizasyonları
-- =====================================================

-- 1. Vector search için IVFFlat index (hızlı arama)
-- Not: Embedding kolonu zaten varsa bu index oluşturulur
DO $$
BEGIN
    -- Check if embedding column exists and create index
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'document_chunks' AND column_name = 'embedding'
    ) THEN
        CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_ivfflat 
        ON document_chunks USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100);
    END IF;
END $$;

-- 2. pdf_images tablosu için caption embedding index (varsa)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'pdf_images' AND column_name = 'caption_embedding'
    ) THEN
        CREATE INDEX IF NOT EXISTS idx_pdf_images_caption_embedding 
        ON pdf_images USING ivfflat (caption_embedding vector_cosine_ops)
        WITH (lists = 50);
    END IF;
END $$;

-- 3. Composite index for file_id + page_number queries
CREATE INDEX IF NOT EXISTS idx_document_chunks_file_page 
ON document_chunks(file_id, page_number);

-- 4. pdf_images için file_id + page_number index
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'pdf_images') THEN
        CREATE INDEX IF NOT EXISTS idx_pdf_images_file_page 
        ON pdf_images(file_id, page_number);
    END IF;
END $$;
