-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can view their own objects" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own objects" ON storage.objects;

-- Recreate with case-insensitive comparison (using LOWER())
CREATE POLICY "Users can view their own objects" ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'user_files' 
  AND LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
);

CREATE POLICY "Users can delete their own objects" ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'user_files' 
  AND LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
);
