-- Duplicate match_document_chunks_v2 fonksiyonlarını temizle
-- vector parametre alan eski versiyonu sil
DROP FUNCTION IF EXISTS match_document_chunks_v2(vector, text, integer, double precision);

-- Text parametre alan versiyonu tut (yeni versiyon)
