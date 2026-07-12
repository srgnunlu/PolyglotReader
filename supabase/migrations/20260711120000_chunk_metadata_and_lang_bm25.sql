-- Persist chunk metadata + language-aware BM25 with stored, indexed tsvectors.
--
-- 1) The iOS chunker computes section_title / content_type / contains_table /
--    contains_list / image_refs but they were never written to the DB, so
--    search results always came back with defaults and the table/section
--    boosts in the context builder never fired.
-- 2) BM25 only ever used to_tsvector('simple') — no Turkish/English stemming.
--    search_chunks_bm25_lang computed to_tsvector at runtime (no index, full
--    scan). Generated columns + GIN indexes fix both.

-- ---------------------------------------------------------------------------
-- Chunk metadata columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.document_chunks
    ADD COLUMN IF NOT EXISTS section_title text,
    ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'text',
    ADD COLUMN IF NOT EXISTS contains_table boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS contains_list boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS image_refs jsonb;

COMMENT ON COLUMN public.document_chunks.embedding IS
    'gemini-embedding-001, outputDimensionality=768 (text-embedding-004 retired)';

-- ---------------------------------------------------------------------------
-- Stemmed full-text columns (stored + indexed; ''simple'' stays for fallback)
-- ---------------------------------------------------------------------------
ALTER TABLE public.document_chunks
    ADD COLUMN IF NOT EXISTS ts_content_tr tsvector
        GENERATED ALWAYS AS (to_tsvector('turkish', content)) STORED,
    ADD COLUMN IF NOT EXISTS ts_content_en tsvector
        GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;

CREATE INDEX IF NOT EXISTS idx_document_chunks_ts_content_tr
    ON public.document_chunks USING gin (ts_content_tr);
CREATE INDEX IF NOT EXISTS idx_document_chunks_ts_content_en
    ON public.document_chunks USING gin (ts_content_en);

-- ---------------------------------------------------------------------------
-- match_chunks: return metadata (return type changes -> drop first)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.match_chunks(vector, float, int, text);

CREATE FUNCTION public.match_chunks(
    query_embedding vector(768),
    match_threshold float,
    match_count int,
    file_id text
)
RETURNS TABLE (
    id uuid,
    content text,
    similarity float,
    page_number int,
    chunk_index int,
    section_title text,
    content_type text,
    contains_table boolean,
    contains_list boolean
)
LANGUAGE sql STABLE
AS $$
    SELECT
        dc.id,
        dc.content,
        1 - (dc.embedding <=> query_embedding) AS similarity,
        dc.page_number,
        dc.chunk_index,
        dc.section_title,
        dc.content_type,
        dc.contains_table,
        dc.contains_list
    FROM public.document_chunks dc
    WHERE dc.file_id = match_chunks.file_id::uuid
      AND 1 - (dc.embedding <=> query_embedding) > match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
$$;

GRANT EXECUTE ON FUNCTION public.match_chunks(vector, float, int, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- search_chunks_bm25: language-aware via stored columns + metadata returns.
-- search_language has a DEFAULT so existing 3-arg callers keep working.
-- Separate IF branches (not CASE inside WHERE) keep each query GIN-indexable.
-- ---------------------------------------------------------------------------
-- Two historical overloads may coexist: (text,text,int) from 20260103 and a
-- resurrected (text,uuid,int) from 20260109. Drop both so the name is unique.
DROP FUNCTION IF EXISTS public.search_chunks_bm25(text, text, int);
DROP FUNCTION IF EXISTS public.search_chunks_bm25(text, uuid, int);

CREATE FUNCTION public.search_chunks_bm25(
    search_file_id text,
    search_query text,
    match_count int,
    search_language text DEFAULT 'simple'
)
RETURNS TABLE (
    id uuid,
    content text,
    rank float,
    page_number int,
    chunk_index int,
    section_title text,
    content_type text,
    contains_table boolean,
    contains_list boolean
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    lang text := lower(coalesce(search_language, 'simple'));
BEGIN
    IF lang = 'turkish' THEN
        RETURN QUERY
        SELECT dc.id, dc.content,
               ts_rank(dc.ts_content_tr, plainto_tsquery('turkish', search_query))::float,
               dc.page_number, dc.chunk_index,
               dc.section_title, dc.content_type, dc.contains_table, dc.contains_list
        FROM public.document_chunks dc
        WHERE dc.file_id = search_file_id::uuid
          AND dc.ts_content_tr @@ plainto_tsquery('turkish', search_query)
        ORDER BY 3 DESC
        LIMIT match_count;
    ELSIF lang = 'english' THEN
        RETURN QUERY
        SELECT dc.id, dc.content,
               ts_rank(dc.ts_content_en, plainto_tsquery('english', search_query))::float,
               dc.page_number, dc.chunk_index,
               dc.section_title, dc.content_type, dc.contains_table, dc.contains_list
        FROM public.document_chunks dc
        WHERE dc.file_id = search_file_id::uuid
          AND dc.ts_content_en @@ plainto_tsquery('english', search_query)
        ORDER BY 3 DESC
        LIMIT match_count;
    ELSE
        RETURN QUERY
        SELECT dc.id, dc.content,
               ts_rank(dc.ts_content, plainto_tsquery('simple', search_query))::float,
               dc.page_number, dc.chunk_index,
               dc.section_title, dc.content_type, dc.contains_table, dc.contains_list
        FROM public.document_chunks dc
        WHERE dc.file_id = search_file_id::uuid
          AND dc.ts_content @@ plainto_tsquery('simple', search_query)
        ORDER BY 3 DESC
        LIMIT match_count;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_chunks_bm25(text, text, int, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- search_chunks_bm25_lang: keep the web-facing signature, delegate to the
-- indexed implementation above (was an unindexed runtime-tsvector full scan).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.search_chunks_bm25_lang(text, uuid, int, text);

CREATE FUNCTION public.search_chunks_bm25_lang(
    search_query text,
    target_file_id uuid,
    match_count int DEFAULT 8,
    search_language text DEFAULT 'simple'
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    chunk_index int,
    content text,
    page_number int,
    rank float
)
LANGUAGE sql STABLE
AS $$
    SELECT b.id, target_file_id, b.chunk_index, b.content, b.page_number, b.rank
    FROM public.search_chunks_bm25(
        target_file_id::text, search_query, match_count, search_language
    ) b;
$$;

GRANT EXECUTE ON FUNCTION public.search_chunks_bm25_lang(text, uuid, int, text) TO authenticated;
