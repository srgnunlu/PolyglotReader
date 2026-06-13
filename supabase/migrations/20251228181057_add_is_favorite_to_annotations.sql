-- Add is_favorite column to annotations table
ALTER TABLE annotations 
ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT false;

-- Create index for faster favorite queries
CREATE INDEX IF NOT EXISTS idx_annotations_is_favorite 
ON annotations(user_id, is_favorite) 
WHERE is_favorite = true;
