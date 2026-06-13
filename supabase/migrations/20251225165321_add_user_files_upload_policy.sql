-- user_files bucket için kullanıcıya özel upload politikası
CREATE POLICY "Users can upload to their own folder"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'user_files' 
    AND lower((storage.foldername(name))[1]) = lower((auth.uid())::text)
);

-- user_files bucket için UPDATE politikası
CREATE POLICY "Users can update their own objects"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'user_files' 
    AND lower((storage.foldername(name))[1]) = lower((auth.uid())::text)
)
WITH CHECK (
    bucket_id = 'user_files' 
    AND lower((storage.foldername(name))[1]) = lower((auth.uid())::text)
);
