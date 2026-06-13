-- Duplicate indexleri temizle
DROP INDEX IF EXISTS idx_document_chunks_file_id;
DROP INDEX IF EXISTS idx_document_chunks_embedding_ivfflat;
DROP INDEX IF EXISTS idx_pdf_images_file_page;
