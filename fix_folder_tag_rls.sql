-- =====================================================
-- KLASÖR VE ETİKET RLS/RPC DÜZELTMESİ
-- Problem: RPC fonksiyonları SECURITY INVOKER olarak çalışıyor
-- Bu, RLS politikalarının uygulanmasına neden oluyor ve
-- fonksiyon parametresi ile auth.uid() eşleşmediği için sonuçlar boş dönüyor.
-- 
-- Çözüm: RPC fonksiyonlarını SECURITY DEFINER olarak güncelleyerek
-- RLS bypass edilir ve fonksiyon kendi parametresiyle çalışır.
-- =====================================================

-- 1. get_folders_with_count fonksiyonunu SECURITY DEFINER olarak yeniden oluştur
DROP FUNCTION IF EXISTS get_folders_with_count(UUID, UUID);

CREATE OR REPLACE FUNCTION get_folders_with_count(p_user_id UUID, p_parent_id UUID DEFAULT NULL)
RETURNS TABLE (
    id UUID,
    name TEXT,
    color TEXT,
    parent_id UUID,
    created_at TIMESTAMPTZ,
    file_count INTEGER
) 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id,
        f.name,
        f.color,
        f.parent_id,
        f.created_at,
        COALESCE(COUNT(files.id), 0)::INTEGER as file_count
    FROM folders f
    LEFT JOIN files ON files.folder_id = f.id
    WHERE f.user_id = p_user_id
    AND (
        (p_parent_id IS NULL AND f.parent_id IS NULL)
        OR f.parent_id = p_parent_id
    )
    GROUP BY f.id, f.name, f.color, f.parent_id, f.created_at
    ORDER BY f.name ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. get_tags_with_count fonksiyonunu SECURITY DEFINER olarak yeniden oluştur
DROP FUNCTION IF EXISTS get_tags_with_count(UUID);

CREATE OR REPLACE FUNCTION get_tags_with_count(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    color TEXT,
    is_auto_generated BOOLEAN,
    created_at TIMESTAMPTZ,
    file_count INTEGER
) 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.name,
        t.color,
        t.is_auto_generated,
        t.created_at,
        COALESCE(COUNT(ft.file_id), 0)::INTEGER as file_count
    FROM tags t
    LEFT JOIN file_tags ft ON t.id = ft.tag_id
    WHERE t.user_id = p_user_id
    GROUP BY t.id, t.name, t.color, t.is_auto_generated, t.created_at
    ORDER BY file_count DESC, t.name ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Yardımcı fonksiyonları da SECURITY DEFINER olarak güncelle
DROP FUNCTION IF EXISTS get_folder_file_count(UUID);
DROP FUNCTION IF EXISTS get_tag_file_count(UUID);

CREATE OR REPLACE FUNCTION get_folder_file_count(folder_uuid UUID)
RETURNS INTEGER 
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(COUNT(*)::INTEGER, 0) FROM files WHERE folder_id = folder_uuid;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION get_tag_file_count(tag_uuid UUID)
RETURNS INTEGER 
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(COUNT(*)::INTEGER, 0) FROM file_tags WHERE tag_id = tag_uuid;
$$ LANGUAGE SQL STABLE;

-- 4. RPC fonksiyonları için yetkileri ver
GRANT EXECUTE ON FUNCTION get_folders_with_count(UUID, UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_tags_with_count(UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_folder_file_count(UUID) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_tag_file_count(UUID) TO postgres, anon, authenticated, service_role;

-- 5. Doğrulama sorgusu (bu satırı çalıştırarak test edebilirsiniz)
-- SELECT * FROM get_folders_with_count('KULLANICI_UUID_BURAYA');
-- SELECT * FROM get_tags_with_count('KULLANICI_UUID_BURAYA');
