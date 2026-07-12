// Client-side RAG indexing for PDFs uploaded from the web.
//
// Until now chunking + embedding only happened in the iOS app, so documents
// uploaded here were never indexed and web chat silently fell back to broad
// context. This is a simplified port of the iOS chunker (RAGChunker.swift):
// sentence/paragraph-aware accumulation with page tracking and 2-sentence
// overlap. It writes the same document_chunks rows (including the metadata
// columns from migration 20260711120000), so both platforms search the same
// index and iOS re-indexing (reindex_document) remains compatible.
'use client';

import { getSupabase } from './supabase';

// Mirror of iOS RAGConfig chunking values — keep in sync.
const TARGET_CHUNK_WORDS = 500;
const MAX_CHUNK_WORDS = 750;
const MIN_CHUNK_WORDS = 60;
const OVERLAP_SENTENCES = 2;
const EMBED_CONCURRENCY = 3;

interface PendingChunk {
    content: string;
    pageNumber: number | null;
    containsList: boolean;
}

interface ChunkInsertRow {
    file_id: string;
    chunk_index: number;
    content: string;
    page_number: number | null;
    embedding: number[];
    content_type: string;
    contains_table: boolean;
    contains_list: boolean;
}

/** Extracts per-page text with pdf.js (lazy import — browser-only globals). */
async function extractPdfPages(file: Blob): Promise<string[]> {
    const { pdfjs } = await import('react-pdf');
    await import('@/lib/pdfjs-config');

    const buffer = await file.arrayBuffer();
    const pdf = await pdfjs.getDocument({ data: new Uint8Array(buffer) }).promise;

    const pages: string[] = [];
    for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
        const page = await pdf.getPage(pageNum);
        const textContent = await page.getTextContent();
        const text = textContent.items
            .map(item => ('str' in item ? item.str : ''))
            .join(' ')
            .replace(/\s+/g, ' ')
            .trim();
        pages.push(text);
    }
    await pdf.destroy();
    return pages;
}

function splitSentences(text: string): string[] {
    // Sentence-ish split: period/question/exclamation followed by whitespace +
    // capital or digit. Good enough for chunk boundaries; exactness not needed.
    return text
        .split(/(?<=[.!?])\s+(?=[A-ZÇĞİÖŞÜ0-9])/)
        .map(s => s.trim())
        .filter(Boolean);
}

const listLineRegex = /(^|\s)(?:[-•*]\s|\d+[.)]\s)/;

function wordCount(text: string): number {
    return text.split(/\s+/).filter(Boolean).length;
}

/** Page-aware sentence accumulation with overlap (simplified iOS chunker). */
function chunkPages(pages: string[]): PendingChunk[] {
    const chunks: PendingChunk[] = [];
    let currentSentences: string[] = [];
    let currentWords = 0;
    let currentPage: number | null = null;

    const flush = () => {
        if (currentSentences.length === 0) return;
        const content = currentSentences.join(' ').trim();
        if (wordCount(content) < MIN_CHUNK_WORDS && chunks.length > 0) {
            // Too small to stand alone — merge into the previous chunk.
            const prev = chunks[chunks.length - 1];
            prev.content = `${prev.content} ${content}`;
            prev.containsList = prev.containsList || listLineRegex.test(content);
        } else {
            chunks.push({
                content,
                pageNumber: currentPage,
                containsList: listLineRegex.test(content),
            });
        }
        // 2-sentence overlap carries context across the boundary.
        const overlap = currentSentences.slice(-OVERLAP_SENTENCES);
        currentSentences = [...overlap];
        currentWords = overlap.reduce((sum, s) => sum + wordCount(s), 0);
    };

    pages.forEach((pageText, pageIndex) => {
        if (!pageText) return;
        // Close the running chunk at page boundaries once it has real content,
        // so page_number stays meaningful (chunks rarely need to span pages).
        if (currentWords >= MIN_CHUNK_WORDS) flush();
        currentPage = pageIndex + 1;

        for (const sentence of splitSentences(pageText)) {
            currentSentences.push(sentence);
            currentWords += wordCount(sentence);
            if (currentWords >= MAX_CHUNK_WORDS) {
                flush();
            } else if (currentWords >= TARGET_CHUNK_WORDS && /[.!?]$/.test(sentence)) {
                flush();
            }
        }
    });

    // Final flush without overlap re-seeding.
    if (currentSentences.length > 0) {
        const content = currentSentences.join(' ').trim();
        if (wordCount(content) >= MIN_CHUNK_WORDS || chunks.length === 0) {
            chunks.push({
                content,
                pageNumber: currentPage,
                containsList: listLineRegex.test(content),
            });
        } else if (chunks.length > 0) {
            chunks[chunks.length - 1].content += ` ${content}`;
        }
    }

    return chunks;
}

async function embedText(text: string): Promise<number[]> {
    const response = await fetch('/api/gemini/embed', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text }),
    });
    if (!response.ok) {
        throw new Error(`Embedding failed (${response.status})`);
    }
    const data = await response.json();
    return data.embedding as number[];
}

/** Embeds chunks with limited concurrency (embed route is rate-limited 60/min). */
async function embedChunks(chunks: PendingChunk[]): Promise<(number[] | null)[]> {
    const results: (number[] | null)[] = new Array(chunks.length).fill(null);
    let nextIndex = 0;

    async function worker() {
        while (nextIndex < chunks.length) {
            const index = nextIndex++;
            try {
                results[index] = await embedText(chunks[index].content);
            } catch (error) {
                console.error(`Chunk ${index} embedding failed:`, error);
            }
        }
    }

    await Promise.all(
        Array.from({ length: Math.min(EMBED_CONCURRENCY, chunks.length) }, worker)
    );
    return results;
}

export async function isDocumentIndexed(fileId: string): Promise<boolean> {
    const supabase = getSupabase();
    const { count, error } = await supabase
        .from('document_chunks')
        .select('id', { count: 'exact', head: true })
        .eq('file_id', fileId);
    if (error) return false;
    return (count ?? 0) > 0;
}

/**
 * Chunks, embeds and persists a PDF so web-uploaded documents are chatable
 * on both platforms. Safe to fire-and-forget after upload: failures only mean
 * the document stays unindexed (iOS will index it on first open, as before).
 */
export async function indexDocumentFile(file: Blob, fileId: string): Promise<void> {
    if (await isDocumentIndexed(fileId)) return;

    const pages = await extractPdfPages(file);
    const chunks = chunkPages(pages);
    if (chunks.length === 0) {
        console.warn('Indexing skipped: no extractable text (scanned PDF?)');
        return;
    }

    const embeddings = await embedChunks(chunks);

    const rows: ChunkInsertRow[] = [];
    chunks.forEach((chunk, index) => {
        const embedding = embeddings[index];
        if (!embedding) return;
        rows.push({
            file_id: fileId,
            chunk_index: rows.length,
            content: chunk.content,
            page_number: chunk.pageNumber,
            embedding,
            content_type: chunk.containsList ? 'list' : 'text',
            contains_table: false,
            contains_list: chunk.containsList,
        });
    });

    if (rows.length === 0) {
        console.warn('Indexing skipped: all embeddings failed');
        return;
    }

    const supabase = getSupabase();
    // Clear any partial previous index, then batch-insert (mirrors the iOS
    // reindex_document + insert flow; UNIQUE(file_id, chunk_index) applies).
    await supabase.from('document_chunks').delete().eq('file_id', fileId);

    const BATCH = 50;
    for (let start = 0; start < rows.length; start += BATCH) {
        const { error } = await supabase
            .from('document_chunks')
            .insert(rows.slice(start, start + BATCH));
        if (error) throw error;
    }

    console.log(`Indexed ${rows.length} chunks for file ${fileId}`);
}
