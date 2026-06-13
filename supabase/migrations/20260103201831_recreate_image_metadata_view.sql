-- Drop valid view first to allow structural changes
DROP VIEW IF EXISTS image_metadata CASCADE;

-- Recreate view with correct columns and types
CREATE VIEW image_metadata AS
SELECT 
    id,
    file_id::text as file_id, -- Ensures TEXT type for compatibility
    page_number,
    image_index,
    bounds,
    thumbnail_base64,
    caption,
    caption_embedding, -- Added missing column
    analyzed_at,
    created_at
FROM pdf_images;

-- Re-grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO authenticated;

-- Recreate Insert Trigger
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

CREATE TRIGGER image_metadata_insert_instead
INSTEAD OF INSERT ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_insert_trigger();

-- Recreate Update Trigger
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

CREATE TRIGGER image_metadata_update_instead
INSTEAD OF UPDATE ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_update_trigger();

-- Recreate Delete Trigger
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
