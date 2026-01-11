-- =====================================================
-- Database Fix Migration
-- Fixes: image_metadata table naming and duplicate chunk handling
-- =====================================================

-- Ensure pdf_images has a unique index for ON CONFLICT upserts
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'pdf_images'
    ) THEN
        CREATE UNIQUE INDEX IF NOT EXISTS pdf_images_file_page_image_idx
        ON pdf_images (file_id, page_number, image_index);
    END IF;
END $$;

-- 1. Create image_metadata as an alias/view to pdf_images
-- This maintains backwards compatibility with existing code
CREATE OR REPLACE VIEW image_metadata AS
SELECT 
    id,
    file_id::text as file_id,  -- Convert UUID to TEXT for compatibility
    page_number,
    image_index,
    bounds,
    thumbnail_base64,
    caption,
    analyzed_at,
    created_at
FROM pdf_images;

-- Grant permissions on the view
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO authenticated;

-- 2. Create INSTEAD OF triggers for the view to handle DML operations
CREATE OR REPLACE FUNCTION image_metadata_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pdf_images (
        id, file_id, page_number, image_index, bounds, 
        thumbnail_base64, caption, analyzed_at, created_at
    ) VALUES (
        COALESCE(NEW.id, gen_random_uuid()),
        NEW.file_id::uuid,
        NEW.page_number,
        NEW.image_index,
        NEW.bounds,
        NEW.thumbnail_base64,
        NEW.caption,
        NEW.analyzed_at,
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (file_id, page_number, image_index) 
    DO UPDATE SET
        bounds = EXCLUDED.bounds,
        thumbnail_base64 = COALESCE(EXCLUDED.thumbnail_base64, pdf_images.thumbnail_base64),
        caption = COALESCE(EXCLUDED.caption, pdf_images.caption),
        analyzed_at = COALESCE(EXCLUDED.analyzed_at, pdf_images.analyzed_at);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER image_metadata_insert_instead
INSTEAD OF INSERT ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_insert_trigger();

CREATE OR REPLACE FUNCTION image_metadata_update_trigger()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pdf_images
    SET 
        bounds = NEW.bounds,
        thumbnail_base64 = NEW.thumbnail_base64,
        caption = NEW.caption,
        analyzed_at = NEW.analyzed_at
    WHERE id = OLD.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER image_metadata_update_instead
INSTEAD OF UPDATE ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_update_trigger();

CREATE OR REPLACE FUNCTION image_metadata_delete_trigger()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM pdf_images WHERE id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER image_metadata_delete_instead
INSTEAD OF DELETE ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_delete_trigger();

-- 3. Add helper function for safe chunk upsert
-- This prevents duplicate key errors during re-indexing
CREATE OR REPLACE FUNCTION upsert_document_chunk(
    p_file_id uuid,
    p_chunk_index int,
    p_content text,
    p_page_number int,
    p_embedding vector(768)
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chunk_id uuid;
BEGIN
    INSERT INTO document_chunks (
        file_id, chunk_index, content, page_number, embedding
    ) VALUES (
        p_file_id, p_chunk_index, p_content, p_page_number, p_embedding
    )
    ON CONFLICT (file_id, chunk_index)
    DO UPDATE SET
        content = EXCLUDED.content,
        page_number = EXCLUDED.page_number,
        embedding = EXCLUDED.embedding,
        ts_content = to_tsvector('simple', EXCLUDED.content)
    RETURNING id INTO chunk_id;
    
    RETURN chunk_id;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_document_chunk TO authenticated;

-- 4. Add function to safely re-index a document
-- Deletes old chunks and inserts new ones atomically
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
    DELETE FROM document_chunks WHERE file_id = p_file_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION reindex_document TO authenticated;

-- =====================================================
-- Migration complete!
-- =====================================================

-- Verification queries:
-- SELECT * FROM image_metadata LIMIT 5;
-- SELECT count(*) FROM document_chunks;
