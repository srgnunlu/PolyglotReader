-- =====================================================
-- Fix image_metadata view - file_id should be UUID not TEXT
-- =====================================================

-- Drop the old view
DROP VIEW IF EXISTS image_metadata;

-- Recreate with correct types
CREATE OR REPLACE VIEW image_metadata AS
SELECT 
    id,
    file_id,  -- Keep as UUID, not TEXT
    page_number,
    image_index,
    bounds,
    thumbnail_base64,
    caption,
    analyzed_at,
    created_at
FROM pdf_images;

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO authenticated;

-- Update the insert trigger to handle UUID properly
CREATE OR REPLACE FUNCTION image_metadata_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pdf_images (
        id, file_id, page_number, image_index, bounds, 
        thumbnail_base64, caption, analyzed_at, created_at
    ) VALUES (
        COALESCE(NEW.id, gen_random_uuid()),
        NEW.file_id,  -- Already UUID, no cast needed
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
        analyzed_at = COALESCE(EXCLUDED.analyzed_at, pdf_images.analyzed_at)
    RETURNING * INTO NEW;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger
DROP TRIGGER IF EXISTS image_metadata_insert_instead ON image_metadata;
CREATE TRIGGER image_metadata_insert_instead
INSTEAD OF INSERT ON image_metadata
FOR EACH ROW
EXECUTE FUNCTION image_metadata_insert_trigger();

-- =====================================================
-- Migration complete!
-- =====================================================
