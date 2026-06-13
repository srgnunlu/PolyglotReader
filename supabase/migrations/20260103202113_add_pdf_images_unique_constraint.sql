-- Add missing unique constraint for UPSERT operations
ALTER TABLE pdf_images
ADD CONSTRAINT pdf_images_file_page_index_key UNIQUE (file_id, page_number, image_index);
