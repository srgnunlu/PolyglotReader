-- Consolidate vector indexes on document_chunks.embedding.
--
-- History: 20251224 created document_chunks_embedding_idx (ivfflat),
-- 20251228 dropped idx_document_chunks_embedding_ivfflat (a name that did not
-- exist yet), 20260109 then created idx_document_chunks_embedding_ivfflat.
-- Depending on which migrations a database has applied it may hold zero, one
-- or two vector indexes. This migration leaves exactly one.
--
-- HNSW instead of ivfflat: needs no list tuning or post-insert ANALYZE to keep
-- recall (ivfflat lists=100 is oversized for per-user document counts), and
-- pgvector ships it on all current Supabase instances.
DROP INDEX IF EXISTS public.document_chunks_embedding_idx;
DROP INDEX IF EXISTS public.idx_document_chunks_embedding_ivfflat;

CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_hnsw
    ON public.document_chunks USING hnsw (embedding vector_cosine_ops);

-- Ensure the file_id filter index survives under one canonical name
-- (20251228 dropped idx_document_chunks_file_id without recreating it).
DROP INDEX IF EXISTS public.document_chunks_file_id_idx;
CREATE INDEX IF NOT EXISTS idx_document_chunks_file_id
    ON public.document_chunks (file_id);
