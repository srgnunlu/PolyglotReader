-- Create reading_progress table
CREATE TABLE IF NOT EXISTS public.reading_progress (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) NOT NULL,
    file_id uuid REFERENCES public.files(id) ON DELETE CASCADE NOT NULL,
    page integer NOT NULL DEFAULT 1,
    offset_x float8 NOT NULL DEFAULT 0,
    offset_y float8 NOT NULL DEFAULT 0,
    zoom_scale float8 NOT NULL DEFAULT 1.0,
    updated_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(user_id, file_id)
);

-- Enable RLS
ALTER TABLE public.reading_progress ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can insert their own reading progress"
    ON public.reading_progress FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own reading progress"
    ON public.reading_progress FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own reading progress"
    ON public.reading_progress FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own reading progress"
    ON public.reading_progress FOR DELETE
    USING (auth.uid() = user_id);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION public.handle_reading_progress_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_reading_progress_updated_at
    BEFORE UPDATE ON public.reading_progress
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_reading_progress_updated_at();

-- Grant permissions
GRANT ALL ON public.reading_progress TO authenticated;
GRANT ALL ON public.reading_progress TO service_role;
