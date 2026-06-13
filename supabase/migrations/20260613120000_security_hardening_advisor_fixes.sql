-- Security hardening based on Supabase advisor findings (2026-06-13).
-- Three groups of fixes, all low-risk and aligned with the existing
-- least-privilege RLS model. No application flow depends on the anon role
-- calling these RPCs (the app and server proxy authenticate every request).

-- 1. Drop the orphaned legacy `books` table.
--    It predates `files`, has no user_id column (cannot be user-scoped),
--    is referenced by no client, and only held 2 stale prototype rows.
--    Its world-readable policy was already dropped (20260612192334),
--    leaving it in a default-deny state and flagged as rls_enabled_no_policy.
DROP TABLE IF EXISTS public.books;

-- 2. Pin search_path on our own functions so a malicious session-level
--    search_path cannot hijack unqualified object references.
ALTER FUNCTION public.document_chunks_tsvector_trigger() SET search_path = public, pg_temp;
ALTER FUNCTION public.document_chunks_ts_content_trigger() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_reading_progress_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.image_metadata_insert_trigger() SET search_path = public, pg_temp;
ALTER FUNCTION public.image_metadata_update_trigger() SET search_path = public, pg_temp;
ALTER FUNCTION public.image_metadata_delete_trigger() SET search_path = public, pg_temp;
ALTER FUNCTION public.match_chunks(public.vector, double precision, integer, text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_file_annotation_counts(text) SET search_path = public, pg_temp;
ALTER FUNCTION public.search_chunks_bm25(text, text, integer) SET search_path = public, pg_temp;

-- 3. SECURITY DEFINER RPCs bypass RLS by design. Revoke EXECUTE from the
--    anon role (and PUBLIC) so an unauthenticated caller cannot invoke them
--    with a guessed file_id and read another user's data. Authenticated
--    users and the server (service_role) retain access.
DO $$
DECLARE
  fn text;
  sigs text[] := ARRAY[
    'public.get_file_annotation_counts(text)',
    'public.get_folder_file_count(uuid)',
    'public.get_folders_with_count(uuid, uuid)',
    'public.get_tag_file_count(uuid)',
    'public.get_tags_with_count(uuid)',
    'public.hybrid_search_chunks(text, text, uuid, double precision, double precision, integer, double precision)',
    'public.match_document_chunks(public.vector, text, integer)',
    'public.match_document_chunks_v2(text, text, integer, double precision)',
    'public.match_image_captions(text, text, double precision, integer)',
    'public.reindex_document(uuid)',
    'public.search_chunks_bm25(text, uuid, integer)',
    'public.search_chunks_bm25_lang(text, uuid, integer, text)',
    'public.search_image_captions(text, uuid, integer, double precision)',
    'public.upsert_document_chunk(uuid, integer, text, integer, public.vector)'
  ];
BEGIN
  FOREACH fn IN ARRAY sigs LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon;', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role;', fn);
  END LOOP;
END $$;
