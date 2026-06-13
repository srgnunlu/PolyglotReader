-- 1. Check for duplicates and cleanup (safe effort)
-- We will keep 'pdf_images_file_page_index_key' as the canonical one
ALTER TABLE pdf_images DROP CONSTRAINT IF EXISTS pdf_images_file_id_page_number_image_index_key;

-- 2. Ensure columns are NOT NULL to guarantee uniqueness works for ON CONFLICT
ALTER TABLE pdf_images 
ALTER COLUMN file_id SET NOT NULL,
ALTER COLUMN page_number SET NOT NULL,
ALTER COLUMN image_index SET NOT NULL;

-- 3. Update the INSERT trigger to explicitly use the constraint name
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
    -- Explicitly specify the constraint to avoid ambiguity and type inference issues
    ON CONFLICT ON CONSTRAINT pdf_images_file_page_index_key 
    DO UPDATE SET
        bounds = EXCLUDED.bounds,
        thumbnail_base64 = COALESCE(EXCLUDED.thumbnail_base64, pdf_images.thumbnail_base64),
        caption = COALESCE(EXCLUDED.caption, pdf_images.caption),
        caption_embedding = COALESCE(EXCLUDED.caption_embedding, pdf_images.caption_embedding),
        analyzed_at = COALESCE(EXCLUDED.analyzed_at, pdf_images.analyzed_at);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
