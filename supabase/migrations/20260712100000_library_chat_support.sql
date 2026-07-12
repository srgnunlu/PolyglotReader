-- Library-wide (multi-document) chat support.
--
-- 1) chats.file_id becomes nullable: library conversations belong to the
--    user, not to a single file (NULL file_id = library chat). Existing
--    per-file rows and RLS policies (user_id based) are unaffected; deleting
--    a file still cascades only its own chat rows.
-- 2) Cross-file search RPCs so iOS can query all (or a subset of) the user's
--    documents in ONE call instead of the per-file client loop the web used.
--    Both run as invoker, so document_chunks RLS still applies on top of the
--    explicit file_ids scope.

ALTER TABLE public.chats ALTER COLUMN file_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chats_library
    ON public.chats (user_id, created_at, seq)
    WHERE file_id IS NULL;

-- ---------------------------------------------------------------------------
-- Vector search across a set of files
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.match_chunks_library(
    query_embedding vector(768),
    match_threshold float,
    match_count int,
    file_ids uuid[]
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    content text,
    similarity float,
    page_number int,
    chunk_index int,
    section_title text,
    contains_table boolean
)
LANGUAGE sql STABLE
AS $$
    SELECT
        dc.id,
        dc.file_id,
        dc.content,
        1 - (dc.embedding <=> query_embedding) AS similarity,
        dc.page_number,
        dc.chunk_index,
        dc.section_title,
        dc.contains_table
    FROM public.document_chunks dc
    WHERE dc.file_id = ANY(file_ids)
      AND 1 - (dc.embedding <=> query_embedding) > match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
$$;

GRANT EXECUTE ON FUNCTION public.match_chunks_library(vector, float, int, uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- BM25 across a set of files (language-aware, stored tsvector columns)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.search_chunks_bm25_library(
    search_query text,
    file_ids uuid[],
    match_count int,
    search_language text DEFAULT 'simple'
)
RETURNS TABLE (
    id uuid,
    file_id uuid,
    content text,
    rank float,
    page_number int,
    chunk_index int
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    lang text := lower(coalesce(search_language, 'simple'));
BEGIN
    IF lang = 'turkish' THEN
        RETURN QUERY
        SELECT dc.id, dc.file_id, dc.content,
               ts_rank(dc.ts_content_tr, plainto_tsquery('turkish', search_query))::float,
               dc.page_number, dc.chunk_index
        FROM public.document_chunks dc
        WHERE dc.file_id = ANY(file_ids)
          AND dc.ts_content_tr @@ plainto_tsquery('turkish', search_query)
        ORDER BY 4 DESC
        LIMIT match_count;
    ELSIF lang = 'english' THEN
        RETURN QUERY
        SELECT dc.id, dc.file_id, dc.content,
               ts_rank(dc.ts_content_en, plainto_tsquery('english', search_query))::float,
               dc.page_number, dc.chunk_index
        FROM public.document_chunks dc
        WHERE dc.file_id = ANY(file_ids)
          AND dc.ts_content_en @@ plainto_tsquery('english', search_query)
        ORDER BY 4 DESC
        LIMIT match_count;
    ELSE
        RETURN QUERY
        SELECT dc.id, dc.file_id, dc.content,
               ts_rank(dc.ts_content, plainto_tsquery('simple', search_query))::float,
               dc.page_number, dc.chunk_index
        FROM public.document_chunks dc
        WHERE dc.file_id = ANY(file_ids)
          AND dc.ts_content @@ plainto_tsquery('simple', search_query)
        ORDER BY 4 DESC
        LIMIT match_count;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_chunks_bm25_library(text, uuid[], int, text) TO authenticated;
