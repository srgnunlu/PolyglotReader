-- Grant permissions for RPC functions to be callable from the API
GRANT EXECUTE ON FUNCTION get_folder_file_count(UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_tag_file_count(UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_folders_with_count(UUID, UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_tags_with_count(UUID) TO postgres, anon, authenticated, service_role;

-- Ensure RLS is active and correct (just in case, though the previous migration handled it)
ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE file_tags ENABLE ROW LEVEL SECURITY;
