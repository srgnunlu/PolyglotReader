-- Dosya bazlı annotation sayılarını getiren RPC fonksiyonu
CREATE OR REPLACE FUNCTION get_file_annotation_counts(p_user_id TEXT)
RETURNS TABLE (
    file_id TEXT,
    file_name TEXT,
    annotation_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT 
        f.id::TEXT as file_id,
        f.name as file_name,
        COUNT(a.id)::BIGINT as annotation_count
    FROM files f
    LEFT JOIN annotations a ON f.id = a.file_id
    WHERE f.user_id = p_user_id::UUID
    GROUP BY f.id, f.name
    HAVING COUNT(a.id) > 0
    ORDER BY COUNT(a.id) DESC;
$$;
