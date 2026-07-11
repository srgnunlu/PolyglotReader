import { getSupabase } from './supabase';

// MARK: - RAG Configuration
// NOT: Bu değerler iOS RAGConfig.swift ile eşitlendi — iki platform aynı
// soruya aynı chunk setini getirsin. Birini değiştirirsen diğerini de değiştir.
const RAG_CONFIG = {
    similarityThreshold: 0.35,      // iOS ile aynı (cross-lingual recall bandı)
    bm25Weight: 0.35,               // Keyword matching ağırlığı
    vectorWeight: 0.65,             // Semantic search ağırlığı
    rrfK: 60,                       // RRF k parametresi
    topK: 12,                       // iOS ile aynı aday sayısı
    rerankTopK: 8,                  // Context'e dahil edilecek chunk (iOS ile aynı)
};

type DocumentLanguage = 'turkish' | 'english' | 'simple';

const documentLanguageCache = new Map<string, DocumentLanguage>();
const turkishCharRegex = /[çğıöşüÇĞİÖŞÜ]/g;
const turkishStopWords = new Set([
    've', 'bir', 'bu', 'şu', 'için', 'ile', 'ama', 'daha', 'gibi', 'olan',
    'olarak', 'ki', 'mı', 'mi', 'mu', 'mü', 'da', 'de', 'en', 'çok', 'az'
]);
const englishStopWords = new Set([
    'the', 'and', 'or', 'with', 'for', 'from', 'that', 'this', 'is', 'are',
    'was', 'were', 'to', 'of', 'in', 'on', 'by', 'as', 'it', 'be', 'not',
    'can', 'may', 'should', 'also', 'more', 'less'
]);

function estimateLanguage(text: string): DocumentLanguage {
    const normalized = text.toLowerCase();
    const turkishCharCount = (normalized.match(turkishCharRegex) || []).length;
    const words = normalized
        .split(/[^a-zA-ZçğıöşüÇĞİÖŞÜ]+/)
        .filter(Boolean)
        .slice(0, 200);

    if (words.length === 0) {
        return turkishCharCount > 0 ? 'turkish' : 'simple';
    }

    let turkishScore = turkishCharCount * 2;
    let englishScore = 0;

    for (const word of words) {
        if (turkishStopWords.has(word)) turkishScore += 1;
        if (englishStopWords.has(word)) englishScore += 1;
    }

    if (turkishScore === 0 && englishScore === 0) {
        return turkishCharCount > 0 ? 'turkish' : 'english';
    }

    if (turkishScore >= englishScore + 2) return 'turkish';
    if (englishScore >= turkishScore + 2) return 'english';
    return turkishCharCount > 0 ? 'turkish' : 'english';
}

async function getDocumentLanguage(fileId: string): Promise<DocumentLanguage> {
    const cached = documentLanguageCache.get(fileId);
    if (cached) return cached;

    const supabase = getSupabase();
    const { data, error } = await supabase
        .from('document_chunks')
        .select('content')
        .eq('file_id', fileId)
        .order('chunk_index', { ascending: true })
        .limit(4);

    if (error) {
        return 'simple';
    }

    const sampleText = (data || [])
        .map((chunk: { content: string }) => chunk.content)
        .join(' ');

    const detected = estimateLanguage(sampleText);
    documentLanguageCache.set(fileId, detected);
    return detected;
}

export interface BM25SearchResult {
    id: string;
    file_id: string;
    chunk_index: number;
    content: string;
    page_number: number | null;
    rank: number;
}

export interface VectorSearchResult {
    id: string;
    file_id: string;
    chunk_index: number;
    content: string;
    page_number: number | null;
    similarity: number;
}

export interface ScoredChunk {
    id: string;
    content: string;
    page_number: number | null;
    chunk_index: number;
    vectorScore: number;
    bm25Score: number;
    rrfScore: number;
}

interface ChunkResult {
    content: string;
    page_number: number | null;
    chunk_index: number;
}

/**
 * BM25 arama kullanarak sorguyla ilgili döküman parçalarını getirir.
 * Bu fonksiyon, AI chat için context oluşturmak amacıyla kullanılır.
 * 
 * @param fileId - Aranacak dökümanın ID'si
 * @param query - Kullanıcının sorusu veya arama terimi
 * @param limit - Getirilecek maksimum chunk sayısı (varsayılan: 20)
 * @returns İlgili chunk içeriklerinin birleştirilmiş metni
 */
export async function searchRelevantChunks(
    fileId: string,
    query: string,
    limit: number = 20
): Promise<string> {
    try {
        // Never log query text — user questions are PII.
        console.log(`BM25 search: fileId="${fileId}"`);

        const results = await bm25Search(fileId, query, limit);
        console.log(`BM25 search returned ${results?.length || 0} results`);

        if (!results || results.length === 0) {
            console.log('No BM25 results, fetching broad context');
            return await getBroadContext(fileId, limit);
        }

        // Chunk'ları chunk_index'e göre sırala
        const sortedResults = results.sort((a, b) => a.chunk_index - b.chunk_index);

        return sortedResults
            .map(chunk => {
                const pageInfo = chunk.page_number ? `[Sayfa ${chunk.page_number}] ` : '';
                return `${pageInfo}${chunk.content}`;
            })
            .join('\n\n---\n\n');

    } catch (err) {
        console.error('RAG search error:', err);
        return await getBroadContext(fileId, limit);
    }
}



/**
 * Tekrar eden chunk'ları kaldırır
 */
function removeDuplicates(chunks: ChunkResult[]): ChunkResult[] {
    const seen = new Set<number>();
    return chunks.filter(chunk => {
        if (seen.has(chunk.chunk_index)) return false;
        seen.add(chunk.chunk_index);
        return true;
    });
}

/**
 * Dökümanın farklı bölümlerinden geniş bir context getirir
 */
async function getBroadContext(fileId: string, limit: number): Promise<string> {
    const supabase = getSupabase();

    // Toplam chunk sayısını al
    const { count } = await supabase
        .from('document_chunks')
        .select('*', { count: 'exact', head: true })
        .eq('file_id', fileId);

    const totalChunks = count || 0;
    console.log(`Total chunks in document: ${totalChunks}`);

    if (totalChunks === 0) {
        return '';
    }

    // Dökümanın farklı bölümlerinden chunk'lar al
    // Başından, ortasından ve sonundan örnekler
    const chunks: ChunkResult[] = [];

    // İlk bölüm (Giriş/İçindekiler)
    const { data: startChunks } = await supabase
        .from('document_chunks')
        .select('content, page_number, chunk_index')
        .eq('file_id', fileId)
        .order('chunk_index', { ascending: true })
        .limit(Math.ceil(limit / 3));

    if (startChunks) chunks.push(...startChunks);

    // Orta bölüm
    if (totalChunks > limit) {
        const middleOffset = Math.floor(totalChunks / 2) - Math.ceil(limit / 6);
        const { data: middleChunks } = await supabase
            .from('document_chunks')
            .select('content, page_number, chunk_index')
            .eq('file_id', fileId)
            .order('chunk_index', { ascending: true })
            .range(middleOffset, middleOffset + Math.ceil(limit / 3) - 1);

        if (middleChunks) chunks.push(...middleChunks);
    }

    // Son bölüm
    if (totalChunks > limit / 2) {
        const { data: endChunks } = await supabase
            .from('document_chunks')
            .select('content, page_number, chunk_index')
            .eq('file_id', fileId)
            .order('chunk_index', { ascending: false })
            .limit(Math.ceil(limit / 3));

        if (endChunks) chunks.push(...endChunks.reverse());
    }

    // Tekrarları kaldır ve sırala
    const uniqueChunks = removeDuplicates(chunks);
    const sortedChunks = uniqueChunks.sort((a, b) => a.chunk_index - b.chunk_index);

    return sortedChunks
        .slice(0, limit)
        .map(chunk => {
            const pageInfo = chunk.page_number ? `[Sayfa ${chunk.page_number}] ` : '';
            return `${pageInfo}${chunk.content}`;
        })
        .join('\n\n---\n\n');
}

/**
 * Döküman için temel context getirir (chat açıldığında ilk yükleme için).
 */
export async function getInitialDocumentContext(fileId: string): Promise<string> {
    const supabase = getSupabase();

    // Önce özet var mı kontrol et
    const { data: file } = await supabase
        .from('files')
        .select('summary')
        .eq('id', fileId)
        .single();

    if (file?.summary) {
        return `[Döküman Özeti]\n${file.summary}`;
    }

    // Özet yoksa geniş context getir
    return await getBroadContext(fileId, 10);
}

// MARK: - Hybrid Search (Vector + BM25 + RRF Fusion)
// Mobil uygulamadaki RAGSearchService ile aynı mantık

/**
 * Sunucu taraflı /api/gemini/embed route'u üzerinden embedding oluşturur
 * (API anahtarı istemciye inmez)
 */
async function createEmbedding(text: string): Promise<number[]> {
    const response = await fetch('/api/gemini/embed', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text })
    });

    if (!response.ok) {
        const errorText = await response.text();
        console.error('Embedding API error:', errorText);
        throw new Error(`Embedding failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return data.embedding;
}

/**
 * Vector search using Supabase pgvector
 */
async function vectorSearch(
    fileId: string,
    queryEmbedding: number[],
    limit: number
): Promise<VectorSearchResult[]> {
    const supabase = getSupabase();

    // Single RPC — the same one iOS calls. The old 4-attempt fallback chain
    // (match_document_chunks / _v2 / text-encoded embedding) is gone; those
    // functions are dropped by migration 20260711120100.
    const { data, error } = await supabase.rpc('match_chunks', {
        query_embedding: queryEmbedding,
        match_threshold: RAG_CONFIG.similarityThreshold,
        match_count: limit,
        file_id: fileId,
    });

    if (error) {
        console.error('Vector search error:', error);
        return [];
    }

    const results = (data || []) as VectorSearchResult[];
    return results.filter(r => r.similarity >= RAG_CONFIG.similarityThreshold);
}

/**
 * Sorgu metninin dilini tespit eder (döküman dilinden bağımsız)
 * Sorgu Türkçe ise 'turkish', İngilizce ise 'english', belirsiz ise 'simple' döner
 */
function detectQueryLanguage(query: string): DocumentLanguage {
    const normalized = query.toLowerCase();
    const turkishCharCount = (normalized.match(turkishCharRegex) || []).length;
    const words = normalized
        .split(/[^a-zA-ZçğıöşüÇĞİÖŞÜ]+/)
        .filter(Boolean);

    if (words.length === 0) {
        return 'simple';
    }

    // Türkçe karakter varsa muhtemelen Türkçe
    if (turkishCharCount > 0) {
        return 'turkish';
    }

    // Türkçe stop word sayısını kontrol et
    let turkishStopWordCount = 0;
    let englishStopWordCount = 0;

    for (const word of words) {
        if (turkishStopWords.has(word)) turkishStopWordCount++;
        if (englishStopWords.has(word)) englishStopWordCount++;
    }

    // Türkçe stop word daha fazlaysa Türkçe
    if (turkishStopWordCount > englishStopWordCount) {
        return 'turkish';
    }

    // İngilizce stop word daha fazlaysa İngilizce
    if (englishStopWordCount > turkishStopWordCount) {
        return 'english';
    }

    // Belirsiz ise simple (stemming yapmaz)
    return 'simple';
}

/**
 * Sorguyu BM25 için ön işleme tabi tutar
 * Stop word'leri çıkarır ve anlamlı kelimeleri korur
 */
function preprocessQueryForBM25(query: string, language: DocumentLanguage): string {
    // YENI: Yapısal referansları yakala ve koru (Tablo 2-1, Şekil 3.4, vb.)
    const structuralRefs: string[] = [];
    const refPattern = /\b(tablo|table|şekil|figure|bölüm|chapter|section)\s*[\d.-]+\b/gi;
    let match;
    while ((match = refPattern.exec(query)) !== null) {
        structuralRefs.push(match[0].toLowerCase());
    }

    // Küçük harfe çevir
    let processed = query.toLowerCase();

    // Noktalama işaretlerini çıkar
    processed = processed.replace(/[.,:;!?()[\]{}""''…]/g, ' ');

    // Çoklu boşlukları tek boşluğa çevir
    processed = processed.replace(/\s+/g, ' ').trim();

    // Stop word'leri çıkar
    const stopWords = language === 'turkish' ? turkishStopWords : englishStopWords;
    const words = processed.split(' ').filter(word =>
        word.length > 2 && !stopWords.has(word)
    );

    // En az 1 kelime olmalı
    if (words.length === 0 && structuralRefs.length === 0) {
        // Stop word filtresi çok agresif olduysa, orijinal sorguyu kullan
        return query;
    }

    // Yapısal referansları başa ekle (öncelik)
    let result = words.join(' ');
    if (structuralRefs.length > 0) {
        result = structuralRefs.join(' ') + ' ' + result;
    }

    return result.trim();
}

/**
 * BM25 search (keyword-based)
 */
async function bm25Search(
    fileId: string,
    query: string,
    limit: number
): Promise<BM25SearchResult[]> {
    const supabase = getSupabase();

    // ÖNEMLI: Sorgu dilini tespit et (döküman dilinden bağımsız)
    const queryLanguage = detectQueryLanguage(query);

    // Döküman dilini de al (fallback için)
    const documentLanguage = await getDocumentLanguage(fileId);

    // Sorguyu ön işleme tabi tut
    const processedQuery = preprocessQueryForBM25(query, queryLanguage);

    // Log only language metadata, never the query text itself (PII).
    console.log(`🔤 BM25 search debug:`);
    console.log(`  Query language: "${queryLanguage}" (detected from query)`);
    console.log(`  Document language: "${documentLanguage}" (from doc content)`);

    const attempts: { name: string; params: Record<string, unknown> }[] = [];

    // Önce sorgu diliyle ara
    if (queryLanguage !== 'simple') {
        attempts.push({
            name: 'search_chunks_bm25_lang',
            params: {
                search_query: processedQuery,
                target_file_id: fileId,
                match_count: limit,
                search_language: queryLanguage
            }
        });
    }

    // Sonra döküman diliyle ara (cross-lingual search için)
    if (documentLanguage !== 'simple' && documentLanguage !== queryLanguage) {
        attempts.push({
            name: 'search_chunks_bm25_lang',
            params: {
                search_query: processedQuery,
                target_file_id: fileId,
                match_count: limit,
                search_language: documentLanguage
            }
        });
    }

    // Fallback to simple BM25 search (no language parameter)
    attempts.push({
        name: 'search_chunks_bm25',
        params: {
            search_query: processedQuery,
            target_file_id: fileId,
            match_count: limit
        }
    });

    let lastError: unknown = null;
    for (const attempt of attempts) {
        const lang = (attempt.params as { search_language?: string }).search_language;
        const attemptDesc = lang ? `${attempt.name}(${lang})` : attempt.name;
        console.log(`  🔎 Attempting: ${attemptDesc}`);

        const { data, error } = await supabase.rpc(attempt.name, attempt.params);
        if (!error) {
            const results = (data || []) as BM25SearchResult[];
            console.log(`    → ${results.length} results`);
            if (results.length > 0) {
                console.log(`  ✓ BM25 success with ${attemptDesc}: ${results.length} results`);
                return results;
            }
            continue;
        }
        console.error(`  ✗ ${attemptDesc} error:`, error);
        lastError = error;
    }

    if (lastError) {
        console.error('❌ BM25 search failed with error:', lastError);
    } else {
        console.log('⚠️  BM25 returned 0 results (query terms not in document)');
    }
    return [];
}

/**
 * RRF (Reciprocal Rank Fusion) - İki sonuç listesini birleştirir
 */
export function rrfFusion(
    vectorResults: VectorSearchResult[],
    bm25Results: BM25SearchResult[]
): ScoredChunk[] {
    const chunkMap = new Map<string, ScoredChunk>();
    const k = RAG_CONFIG.rrfK;

    // Vector results scoring
    vectorResults.forEach((result, index) => {
        const score = 1.0 / (k + index + 1);
        chunkMap.set(result.id, {
            id: result.id,
            content: result.content,
            page_number: result.page_number,
            chunk_index: result.chunk_index,
            vectorScore: score * RAG_CONFIG.vectorWeight,
            bm25Score: 0,
            rrfScore: score * RAG_CONFIG.vectorWeight
        });
    });

    // BM25 results scoring
    bm25Results.forEach((result, index) => {
        const score = 1.0 / (k + index + 1);
        const existing = chunkMap.get(result.id);

        if (existing) {
            existing.bm25Score = score * RAG_CONFIG.bm25Weight;
            existing.rrfScore += score * RAG_CONFIG.bm25Weight;
        } else {
            chunkMap.set(result.id, {
                id: result.id,
                content: result.content,
                page_number: result.page_number,
                chunk_index: result.chunk_index,
                vectorScore: 0,
                bm25Score: score * RAG_CONFIG.bm25Weight,
                rrfScore: score * RAG_CONFIG.bm25Weight
            });
        }
    });

    // Sort by RRF score
    return Array.from(chunkMap.values())
        .sort((a, b) => b.rrfScore - a.rrfScore);
}

/**
 * Hybrid search: Vector + BM25 + RRF Fusion
 * Bu fonksiyon mobil uygulamadaki RAGSearchService.hybridSearch ile aynı mantığı kullanır
 */
export async function searchRelevantChunksHybrid(
    fileId: string,
    query: string,
    limit: number = 10
): Promise<string> {
    // Never log query text — user questions are PII.
    console.log(`🔍 Hybrid search: fileId="${fileId}"`);

    try {
        // Parallel search: Vector + BM25
        const [queryEmbedding, bm25Results] = await Promise.all([
            createEmbedding(query),
            bm25Search(fileId, query, limit)
        ]);

        const vectorResults = await vectorSearch(fileId, queryEmbedding, limit);

        console.log(`📊 Vector results: ${vectorResults.length}, BM25 results: ${bm25Results.length}`);

        // Check if we have any results
        if (vectorResults.length === 0 && bm25Results.length === 0) {
            console.log('⚠️ No results from hybrid search, using fallback');
            return await getBroadContext(fileId, limit);
        }

        // BM25'in 0 sonuç vermesi normaldir - sorgu kelimeleri içerikte olmayabilir
        // Bu durumda vector search (semantic search) devreye girer
        if (bm25Results.length === 0 && vectorResults.length > 0) {
            console.log('ℹ️ BM25 returned 0 results (query terms not found), using vector search only (semantic matching)');
        }

        // RRF Fusion
        const fusedResults = rrfFusion(vectorResults, bm25Results);

        // Take top results
        const topResults = fusedResults.slice(0, RAG_CONFIG.rerankTopK);

        console.log(`✓ Hybrid search returned ${topResults.length} fused results`);

        // Debug: Similarity score'ları göster
        console.log('📈 Top chunk scores:');
        topResults.slice(0, 3).forEach((chunk, i) => {
            console.log(`  [${i + 1}] RRF: ${chunk.rrfScore.toFixed(4)}, Vector: ${chunk.vectorScore.toFixed(4)}, BM25: ${chunk.bm25Score.toFixed(4)}, Page: ${chunk.page_number || 'N/A'}`);
        });

        // Format with enhanced citation (matches mobile RAGContextBuilder)
        return topResults
            .map((chunk, index) => {
                const pageInfo = chunk.page_number ? ` (Sayfa ${chunk.page_number})` : '';
                const confidenceIndicator = chunk.rrfScore > 0.02 ? ' [Yüksek Eşleşme]' : '';
                return `---
[${index + 1}]${pageInfo}${confidenceIndicator}
${chunk.content}`;
            })
            .join('\n\n');

    } catch (err) {
        console.error('❌ Hybrid search error:', err);
        // Fallback to BM25 only
        return await searchRelevantChunks(fileId, query, limit);
    }
}

// MARK: - Library-wide Search (Multi-file Hybrid)

/** Caps how many documents a single library query will scan, to bound cost. */
const LIBRARY_MAX_FILES = 25;

interface LibraryFile {
    id: string;
    name: string;
}

interface LibraryScoredChunk extends ScoredChunk {
    fileId: string;
    fileName: string;
}

/**
 * Kütüphane-geneli hibrit arama: birden fazla dokümanda paralel olarak
 * vektör + BM25 araması yapar, her dosya için RRF füzyonu uygular, sonra
 * tüm dosyalardan gelen en iyi parçaları küresel olarak sıralar.
 *
 * Tek dosyalık `searchRelevantChunksHybrid` ile aynı düşük seviyeli (test
 * edilmiş) arama yollarını yeniden kullanır; embedding sorgu başına bir kez
 * hesaplanır.
 *
 * @param files - Aranacak dosyalar (id + görüntülenecek isim)
 * @param query - Kullanıcının sorusu
 * @param perFileLimit - Her dosyadan alınacak aday parça sayısı
 * @param finalLimit - Bağlama dahil edilecek toplam parça sayısı
 * @returns Dosya adı + sayfa atıflı, birleştirilmiş bağlam metni
 */
export async function searchLibraryChunks(
    files: LibraryFile[],
    query: string,
    perFileLimit: number = 6,
    finalLimit: number = 12
): Promise<string> {
    if (files.length === 0) return '';

    // Bound the scan: most-recent files are passed first by the caller.
    const scanned = files.slice(0, LIBRARY_MAX_FILES);
    if (files.length > LIBRARY_MAX_FILES) {
        console.log(`📚 Library search capped: scanning ${LIBRARY_MAX_FILES} of ${files.length} files`);
    }

    try {
        const queryEmbedding = await createEmbedding(query);

        const perFileResults = await Promise.all(
            scanned.map(async (file): Promise<LibraryScoredChunk[]> => {
                try {
                    const [vectorResults, bm25Results] = await Promise.all([
                        vectorSearch(file.id, queryEmbedding, perFileLimit),
                        bm25Search(file.id, query, perFileLimit),
                    ]);

                    if (vectorResults.length === 0 && bm25Results.length === 0) {
                        return [];
                    }

                    return rrfFusion(vectorResults, bm25Results)
                        .slice(0, perFileLimit)
                        .map(chunk => ({ ...chunk, fileId: file.id, fileName: file.name }));
                } catch (fileErr) {
                    console.error(`Library search failed for file ${file.id}:`, fileErr);
                    return [];
                }
            })
        );

        const allChunks = perFileResults
            .flat()
            .sort((a, b) => b.rrfScore - a.rrfScore)
            .slice(0, finalLimit);

        if (allChunks.length === 0) return '';

        return allChunks
            .map((chunk, index) => {
                const pageInfo = chunk.page_number ? `, Sayfa ${chunk.page_number}` : '';
                return `---
[${index + 1}] (${chunk.fileName}${pageInfo})
${chunk.content}`;
            })
            .join('\n\n');
    } catch (err) {
        console.error('❌ Library search error:', err);
        return '';
    }
}
