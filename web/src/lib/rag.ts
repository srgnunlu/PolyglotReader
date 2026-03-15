import type { SupabaseClient } from '@supabase/supabase-js';
import { getSupabase } from './supabase';

// MARK: - RAG Configuration (matches mobile RAGConfig.swift v3.0)
const RAG_CONFIG = {
    similarityThreshold: 0.30,      // 0.30: Cross-lingual search için düşürüldü (Türkçe↔İngilizce)
    bm25Weight: 0.35,               // Keyword matching ağırlığı
    vectorWeight: 0.65,             // Semantic search ağırlığı
    rrfK: 60,                       // RRF k parametresi
    topK: 15,                       // Aday sayısı (10→15: daha fazla chunk ara)
    rerankTopK: 8,                  // Context'e dahil edilecek chunk (6→8: AI'a daha fazla context)
};

type DocumentLanguage = 'turkish' | 'english' | 'simple';

type DocumentChunkPreview = {
    content: string;
};

type BM25AttemptParams = {
    search_query: string;
    target_file_id: string;
    match_count: number;
    search_language?: DocumentLanguage;
};

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

function embeddingToText(embedding: number[]): string {
    return `[${embedding.join(',')}]`;
}

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

async function getDocumentLanguage(fileId: string, db?: SupabaseClient): Promise<DocumentLanguage> {
    const cached = documentLanguageCache.get(fileId);
    if (cached) return cached;

    const supabase = db ?? getSupabase();
    const { data, error } = await supabase
        .from('document_chunks')
        .select('content')
        .eq('file_id', fileId)
        .order('chunk_index', { ascending: true })
        .limit(4);

    if (error) {
        return 'simple';
    }

    const sampleText = ((data || []) as DocumentChunkPreview[])
        .map((chunk) => chunk.content)
        .join(' ');

    const detected = estimateLanguage(sampleText);
    documentLanguageCache.set(fileId, detected);
    return detected;
}

interface BM25SearchResult {
    id: string;
    file_id: string;
    chunk_index: number;
    content: string;
    page_number: number | null;
    rank: number;
}

interface VectorSearchResult {
    id: string;
    file_id: string;
    chunk_index: number;
    content: string;
    page_number: number | null;
    similarity: number;
}

interface ScoredChunk {
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
    limit: number = 20,
    db?: SupabaseClient
): Promise<string> {
    try {
        console.log(`BM25 search: query="${query}", fileId="${fileId}"`);

        const results = await bm25Search(fileId, query, limit, db);
        console.log(`BM25 search returned ${results?.length || 0} results`);

        if (!results || results.length === 0) {
            console.log('No BM25 results, fetching broad context');
            return await getBroadContext(fileId, limit, db);
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
        return await getBroadContext(fileId, limit, db);
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
async function getBroadContext(fileId: string, limit: number, db?: SupabaseClient): Promise<string> {
    const supabase = db ?? getSupabase();

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
export async function getInitialDocumentContext(fileId: string, db?: SupabaseClient): Promise<string> {
    const supabase = db ?? getSupabase();

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
    return await getBroadContext(fileId, 10, db);
}

// MARK: - Hybrid Search (Vector + BM25 + RRF Fusion)
// Mobil uygulamadaki RAGSearchService ile aynı mantık

/**
 * Gemini API ile embedding oluşturur
 */
async function createEmbedding(text: string): Promise<number[]> {
    const apiKey = process.env.GEMINI_API_KEY || process.env.NEXT_PUBLIC_GEMINI_API_KEY;
    if (!apiKey) throw new Error('Gemini API key not found');

    const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${apiKey}`,
        {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: 'models/text-embedding-004',
                content: { parts: [{ text }] }
            })
        }
    );

    if (!response.ok) {
        const errorText = await response.text();
        console.error('Embedding API error:', errorText);
        throw new Error(`Embedding failed: ${response.status} ${response.statusText} - ${errorText}`);
    }

    const data = await response.json();
    return data.embedding.values;
}

/**
 * Vector search using Supabase pgvector
 */
async function vectorSearch(
    fileId: string,
    queryEmbedding: number[],
    limit: number,
    db?: SupabaseClient
): Promise<VectorSearchResult[]> {
    const supabase = db ?? getSupabase();
    const embeddingText = embeddingToText(queryEmbedding);

    const attempts = [
        {
            name: 'match_document_chunks',
            params: {
                query_embedding: queryEmbedding,
                match_file_id: fileId,
                match_count: limit
            }
        },
        {
            name: 'match_document_chunks_v2',
            params: {
                query_embedding: queryEmbedding,
                match_file_id: fileId,
                match_count: limit,
                similarity_threshold: RAG_CONFIG.similarityThreshold
            }
        },
        {
            name: 'match_document_chunks_v2',
            params: {
                query_embedding: embeddingText,
                match_file_id: fileId,
                match_count: limit,
                similarity_threshold: RAG_CONFIG.similarityThreshold
            }
        },
        {
            name: 'match_chunks',
            params: {
                query_embedding: queryEmbedding,
                match_threshold: RAG_CONFIG.similarityThreshold,
                match_count: limit,
                file_id: fileId
            }
        }
    ];

    let lastError: unknown = null;
    for (const attempt of attempts) {
        const { data, error } = await supabase.rpc(attempt.name, attempt.params);
        if (!error) {
            const results = (data || []) as VectorSearchResult[];
            return results.filter(r => r.similarity >= RAG_CONFIG.similarityThreshold);
        }
        lastError = error;
    }

    if (lastError) {
        console.error('Vector search error:', lastError);
    }
    return [];
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
    limit: number,
    db?: SupabaseClient
): Promise<BM25SearchResult[]> {
    const supabase = db ?? getSupabase();

    // ÖNEMLI: Sorgu dilini tespit et (döküman dilinden bağımsız)
    const queryLanguage = detectQueryLanguage(query);

    // Döküman dilini de al (fallback için)
    const documentLanguage = await getDocumentLanguage(fileId, db);

    // Sorguyu ön işleme tabi tut
    const processedQuery = preprocessQueryForBM25(query, queryLanguage);

    console.log(`🔤 BM25 search debug:`);
    console.log(`  Query language: "${queryLanguage}" (detected from query)`);
    console.log(`  Document language: "${documentLanguage}" (from doc content)`);
    console.log(`  Original query: "${query}"`);
    console.log(`  Processed query: "${processedQuery}"`);

    const attempts: { name: string; params: BM25AttemptParams }[] = [];

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
        const lang = attempt.params.search_language;
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
function rrfFusion(
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
    limit: number = 10,
    db?: SupabaseClient
): Promise<string> {
    console.log(`🔍 Hybrid search: query="${query.substring(0, 50)}...", fileId="${fileId}"`);

    try {
        // Parallel search: Vector + BM25
        const [queryEmbedding, bm25Results] = await Promise.all([
            createEmbedding(query),
            bm25Search(fileId, query, limit, db)
        ]);

        const vectorResults = await vectorSearch(fileId, queryEmbedding, limit, db);

        console.log(`📊 Vector results: ${vectorResults.length}, BM25 results: ${bm25Results.length}`);

        // Check if we have any results
        if (vectorResults.length === 0 && bm25Results.length === 0) {
            console.log('⚠️ No results from hybrid search, using fallback');
            return await getBroadContext(fileId, limit, db);
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
        return await searchRelevantChunks(fileId, query, limit, db);
    }
}
