-- =====================================================
-- PolyglotReader Log Fixes Migration
-- Fixes: caption_embedding column in view, re-indexing RPC
-- =====================================================

-- 1. Update image_metadata view to include caption_embedding
-- =====================================================

DROP VIEW IF EXISTS image_metadata;

CREATE OR REPLACE VIEW image_metadata AS
SELECT 
    id,
    file_id::text as file_id,
    page_number,
    image_index,
    bounds,
    thumbnail_base64,
    caption,
    caption_embedding,  -- Added missing column
    analyzed_at,
    created_at
FROM pdf_images;

-- Grant permissions on the view
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO authenticated;

-- 2. Update INSTEAD OF INSERT trigger to handle caption_embedding
-- =====================================================

CREATE OR REPLACE FUNCTION image_metadata_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pdf_images (
        id, file_id, page_number, image_index, bounds, 
        thumbnail_base64, caption, caption_embedding, analyzed_at, created_at
    ) VALUES (
        COALESCE(NEW.id, gen_random_uuid()),
        NEW.file_id::uuid,
        NEW.page_number,
        NEW.image_index,
        NEW.bounds,
        NEW.thumbnail_base64,
        NEW.caption,
        NEW.caption_embedding,
        NEW.analyzed_at,
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (file_id, page_number, image_index) 
    DO UPDATE SET
        bounds = EXCLUDED.bounds,
        thumbnail_base64 = COALESCE(EXCLUDED.thumbnail_base64, pdf_images.thumbnail_base64),
        caption = COALESCE(EXCLUDED.caption, pdf_images.caption),
        caption_embedding = COALESCE(EXCLUDED.caption_embedding, pdf_images.caption_embedding),
        analyzed_at = COALESCE(EXCLUDED.analyzed_at, pdf_images.analyzed_at);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Update INSTEAD OF UPDATE trigger to handle caption_embedding
-- =====================================================

CREATE OR REPLACE FUNCTION image_metadata_update_trigger()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pdf_images
    SET 
        bounds = NEW.bounds,
        thumbnail_base64 = NEW.thumbnail_base64,
        caption = NEW.caption,
        caption_embedding = NEW.caption_embedding,
        analyzed_at = NEW.analyzed_at
    WHERE id = OLD.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Ensure reindex_document function exists and works correctly
-- =====================================================

CREATE OR REPLACE FUNCTION reindex_document(
    p_file_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count int;
BEGIN
    -- Delete existing chunks for this file
    DELETE FROM document_chunks WHERE file_id = p_file_id::text;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION reindex_document TO authenticated;

-- 5. Ensure search_image_captions RPC uses correct table (pdf_images, not image_metadata)
-- =====================================================

CREATE OR REPLACE FUNCTION search_image_captions(
    query_embedding text,
    target_file_id uuid,
    match_count int DEFAULT 3,
    similarity_threshold float DEFAULT 0.6
)
RETURNS TABLE (
    id uuid,
    page_number int,
    caption text,
    similarity float
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    embedding_array vector(768);
BEGIN
    embedding_array := query_embedding::vector(768);
    
    RETURN QUERY
    SELECT 
        pi.id,
        pi.page_number,
        pi.caption,
        (1 - (pi.caption_embedding <=> embedding_array))::float as similarity
    FROM pdf_images pi
    WHERE pi.file_id = target_file_id
      AND pi.caption IS NOT NULL
      AND pi.caption_embedding IS NOT NULL
      AND (1 - (pi.caption_embedding <=> embedding_array)) >= similarity_threshold
    ORDER BY pi.caption_embedding <=> embedding_array
    LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION search_image_captions(text, uuid, int, float) TO authenticated;
GRANT EXECUTE ON FUNCTION search_image_captions(text, uuid, int, float) TO anon;

-- =====================================================
-- Migration complete!
-- =====================================================

-- Verification queries:
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'pdf_images' AND column_name = 'caption_embedding';
-- SELECT * FROM image_metadata LIMIT 1;
-- SELECT routine_name FROM information_schema.routines WHERE routine_name = 'reindex_document';
