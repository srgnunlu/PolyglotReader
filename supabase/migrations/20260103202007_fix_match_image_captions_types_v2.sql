-- Function matching Swift's SupabaseImageSearchParams for image caption search
CREATE OR REPLACE FUNCTION match_image_captions(
    target_file_id text,
    query_embedding text,
    match_threshold float DEFAULT 0.5,
    match_count int DEFAULT 5
)
RETURNS TABLE (
    id uuid,
    file_id text,
    page_number int,
    image_index int,
    bounds jsonb,
    thumbnail_base64 text,
    caption text,
    caption_embedding vector(768),
    analyzed_at timestamp with time zone,
    created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    embedding_array vector(768);
BEGIN
    -- Cast embedding only
    embedding_array := query_embedding::vector(768);
    
    RETURN QUERY
    SELECT 
        im.id,
        im.file_id, -- Already text from view
        im.page_number,
        im.image_index,
        im.bounds,
        im.thumbnail_base64,
        im.caption,
        im.caption_embedding,
        im.analyzed_at,
        im.created_at
    FROM image_metadata im
    WHERE im.file_id = target_file_id -- Text = Text comparison
      AND im.caption IS NOT NULL
      AND im.caption_embedding IS NOT NULL
      AND (1 - (im.caption_embedding <=> embedding_array)) >= match_threshold
    ORDER BY im.caption_embedding <=> embedding_array
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION match_image_captions(text, text, float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION match_image_captions(text, text, float, int) TO anon;
