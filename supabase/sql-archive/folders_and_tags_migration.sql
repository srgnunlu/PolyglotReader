-- =====================================================
-- KLASÖR VE ETİKETLEME SİSTEMİ MİGRASYONU
-- PolyglotReader - Kütüphane Organizasyonu
-- =====================================================

-- 1. FOLDERS TABLOSU
CREATE TABLE IF NOT EXISTS folders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#6366F1',
    parent_id UUID REFERENCES folders(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT unique_folder_name_per_user_parent 
        UNIQUE(user_id, parent_id, name)
);

-- 2. TAGS TABLOSU
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#22C55E',
    is_auto_generated BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT unique_tag_name_per_user 
        UNIQUE(user_id, name)
);

-- 3. FILE_TAGS JUNCTION TABLOSU (Çoktan-Çoğa İlişki)
CREATE TABLE IF NOT EXISTS file_tags (
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (file_id, tag_id)
);

-- 4. FILES TABLOSUNA FOLDER_ID VE AI_CATEGORY EKLE
ALTER TABLE files 
ADD COLUMN IF NOT EXISTS folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS ai_category TEXT;

-- 5. RLS POLİTİKALARI

-- Folders
ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can CRUD own folders" ON folders;
CREATE POLICY "Users can CRUD own folders" ON folders
    FOR ALL USING (auth.uid() = user_id);

-- Tags
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can CRUD own tags" ON tags;
CREATE POLICY "Users can CRUD own tags" ON tags
    FOR ALL USING (auth.uid() = user_id);

-- File Tags
ALTER TABLE file_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own file tags" ON file_tags;
CREATE POLICY "Users can manage own file tags" ON file_tags
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM files 
            WHERE files.id = file_id 
            AND files.user_id = auth.uid()
        )
    );

-- 6. INDEXLER (Performans)
CREATE INDEX IF NOT EXISTS idx_folders_user_id ON folders(user_id);
CREATE INDEX IF NOT EXISTS idx_folders_parent_id ON folders(parent_id);
CREATE INDEX IF NOT EXISTS idx_tags_user_id ON tags(user_id);
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
CREATE INDEX IF NOT EXISTS idx_file_tags_file_id ON file_tags(file_id);
CREATE INDEX IF NOT EXISTS idx_file_tags_tag_id ON file_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_files_folder_id ON files(folder_id);

-- 7. YARDIMCI FONKSİYONLAR

-- Tag dosya sayısını hesapla
CREATE OR REPLACE FUNCTION get_tag_file_count(tag_uuid UUID)
RETURNS INTEGER AS $$
    SELECT COUNT(*)::INTEGER FROM file_tags WHERE tag_id = tag_uuid;
$$ LANGUAGE SQL STABLE;

-- Klasör dosya sayısını hesapla
CREATE OR REPLACE FUNCTION get_folder_file_count(folder_uuid UUID)
RETURNS INTEGER AS $$
    SELECT COUNT(*)::INTEGER FROM files WHERE folder_id = folder_uuid;
$$ LANGUAGE SQL STABLE;

-- Etiketleri dosya sayısıyla getir
CREATE OR REPLACE FUNCTION get_tags_with_count(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    color TEXT,
    is_auto_generated BOOLEAN,
    created_at TIMESTAMPTZ,
    file_count INTEGER
) AS $$
    SELECT 
        t.id,
        t.name,
        t.color,
        t.is_auto_generated,
        t.created_at,
        COUNT(ft.file_id)::INTEGER as file_count
    FROM tags t
    LEFT JOIN file_tags ft ON t.id = ft.tag_id
    WHERE t.user_id = p_user_id
    GROUP BY t.id, t.name, t.color, t.is_auto_generated, t.created_at
    ORDER BY file_count DESC, t.name ASC;
$$ LANGUAGE SQL STABLE;

-- Klasörleri dosya sayısıyla getir
CREATE OR REPLACE FUNCTION get_folders_with_count(p_user_id UUID, p_parent_id UUID DEFAULT NULL)
RETURNS TABLE (
    id UUID,
    name TEXT,
    color TEXT,
    parent_id UUID,
    created_at TIMESTAMPTZ,
    file_count INTEGER
) AS $$
    SELECT 
        f.id,
        f.name,
        f.color,
        f.parent_id,
        f.created_at,
        COUNT(files.id)::INTEGER as file_count
    FROM folders f
    LEFT JOIN files ON files.folder_id = f.id
    WHERE f.user_id = p_user_id
    AND (
        (p_parent_id IS NULL AND f.parent_id IS NULL)
        OR f.parent_id = p_parent_id
    )
    GROUP BY f.id, f.name, f.color, f.parent_id, f.created_at
    ORDER BY f.name ASC;
$$ LANGUAGE SQL STABLE;
