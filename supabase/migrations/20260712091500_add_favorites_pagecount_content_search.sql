-- Faz 4 (library): favorites, reading-progress display, and library-wide
-- content search.
--
-- 1) files.is_favorite  — star/favorite flag, filterable in the library.
-- 2) files.page_count   — total pages, needed to render "page 12/30" and a
--    progress bar next to reading_progress.page. Set at upload; backfilled
--    lazily for legacy files.
-- 3) search_files_by_content(...) — cross-file BM25 over document_chunks so
--    the library search box can match PDF contents, not just names/tags.
--    SECURITY INVOKER: RLS on document_chunks keeps results per-user.

ALTER TABLE files ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE files ADD COLUMN IF NOT EXISTS page_count INTEGER;

CREATE OR REPLACE FUNCTION public.search_files_by_content(
    search_query text,
    match_count integer DEFAULT 20
)
RETURNS TABLE(file_id uuid, best_rank real)
LANGUAGE sql
STABLE
AS $$
    SELECT dc.file_id,
           MAX(GREATEST(
               COALESCE(ts_rank(dc.ts_content_tr, plainto_tsquery('turkish', search_query)), 0),
               COALESCE(ts_rank(dc.ts_content_en, plainto_tsquery('english', search_query)), 0)
           ))::real AS best_rank
    FROM public.document_chunks dc
    WHERE dc.ts_content_tr @@ plainto_tsquery('turkish', search_query)
       OR dc.ts_content_en @@ plainto_tsquery('english', search_query)
    GROUP BY dc.file_id
    ORDER BY best_rank DESC
    LIMIT match_count;
$$;
