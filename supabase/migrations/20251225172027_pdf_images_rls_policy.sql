-- RLS aktif et
ALTER TABLE pdf_images ENABLE ROW LEVEL SECURITY;

-- RLS politikası - UUID karşılaştırma ile
CREATE POLICY "Users can access their own pdf images"
ON pdf_images FOR ALL
USING (
    file_id IN (
        SELECT f.id FROM files f WHERE f.user_id = auth.uid()
    )
);

-- İzinler
GRANT SELECT, INSERT, UPDATE, DELETE ON pdf_images TO authenticated;
