-- PDF Görseller Tablosu
CREATE TABLE IF NOT EXISTS pdf_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    page_number INT NOT NULL,
    image_index INT NOT NULL DEFAULT 0,
    bounds JSONB,
    thumbnail_base64 TEXT,
    caption TEXT,
    caption_embedding vector(768),
    analyzed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(file_id, page_number, image_index)
);

CREATE INDEX IF NOT EXISTS pdf_images_file_id_idx ON pdf_images(file_id);
CREATE INDEX IF NOT EXISTS pdf_images_page_idx ON pdf_images(file_id, page_number);
