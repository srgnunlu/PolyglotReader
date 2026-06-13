-- Files tablosu için UPDATE politikası ekle
CREATE POLICY "Users can update their own files"
ON files FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
