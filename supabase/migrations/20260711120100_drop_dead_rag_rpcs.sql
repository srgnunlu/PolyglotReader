-- Remove RAG RPCs that no client calls anymore.
--
-- hybrid_search_chunks: RRF fusion moved client-side on both platforms.
-- search_image_captions: superseded by match_image_captions (image_metadata).
-- match_document_chunks / _v2: web's RPC fallback chain now calls only
-- match_chunks (same function iOS uses).
--
-- Dropped via pg_proc so every overload goes regardless of signature drift
-- across environments.
DO $$
DECLARE
    fn record;
BEGIN
    FOR fn IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.proname IN (
              'hybrid_search_chunks',
              'search_image_captions',
              'match_document_chunks',
              'match_document_chunks_v2'
          )
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %s', fn.sig);
    END LOOP;
END $$;
