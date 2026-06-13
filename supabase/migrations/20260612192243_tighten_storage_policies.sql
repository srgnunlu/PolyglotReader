-- The 'pdfs' bucket is unused by any client but had anon-accessible policies.
DROP POLICY "Allow public delete from pdfs" ON storage.objects;
DROP POLICY "Allow public select from pdfs" ON storage.objects;
DROP POLICY "Allow public uploads to pdfs" ON storage.objects;
-- Redundant with the folder-scoped "Users can upload to their own folder";
-- this one let any authenticated user write into any folder.
DROP POLICY "Any authenticated user can upload" ON storage.objects;
