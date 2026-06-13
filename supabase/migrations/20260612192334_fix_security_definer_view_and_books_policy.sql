-- image_metadata bypassed pdf_images RLS for every querying user.
ALTER VIEW public.image_metadata SET (security_invoker = true);
-- Legacy 'books' table is unused by any client; this always-true policy
-- made it world-readable/writable. Default-deny now applies.
DROP POLICY "Allow public access to books" ON public.books;
