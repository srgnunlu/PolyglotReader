-- Trash / soft delete: deleting a file in the library now only stamps
-- deleted_at; storage, chunks and tags survive so the file can be restored
-- from "Son Silinenler". Permanent purge (user action or 30-day client-side
-- sweep) still removes the row + storage as before.
ALTER TABLE files ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Trash listing is per-user and rare; partial index keeps it cheap without
-- taxing the main (deleted_at IS NULL) library queries.
CREATE INDEX IF NOT EXISTS idx_files_deleted_at
    ON files (user_id, deleted_at)
    WHERE deleted_at IS NOT NULL;
