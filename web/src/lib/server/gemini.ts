import { GoogleGenerativeAI, GenerativeModel, Content, Part } from '@google/generative-ai';
import { createServerSupabase } from '../supabase-server';

// Server-only Gemini access. The API key must never be exposed to the client,
// so it is read from GEMINI_API_KEY (no NEXT_PUBLIC_ prefix).
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

// text-embedding-004 was retired by Google (404). gemini-embedding-001
// defaults to 3072 dims; requests pass outputDimensionality=768 to match the
// vector(768) DB schema (truncated vectors are fine for cosine search).
export const EMBEDDING_MODEL = 'gemini-embedding-001';
export const EMBEDDING_DIMENSION = 768;

export function getGeminiApiKey(): string {
    if (!GEMINI_API_KEY) {
        throw new Error('GEMINI_API_KEY is not configured on the server');
    }
    return GEMINI_API_KEY;
}

// Mirrors the iOS client (GeminiConfig.swift) so both platforms produce the
// same answer quality. Without these, web ran on Gemini's default (high)
// temperature and with no system-level grounding rules at all.
const GENERATION_CONFIG = {
    temperature: 0.3,
    topP: 0.85,
    topK: 40,
    maxOutputTokens: 16384,
};

const SYSTEM_INSTRUCTION = `Sen uzman düzeyinde bir akademik PDF doküman analizcisisin.
Metni, tabloları, grafikleri ve görselleri derinlemesine analiz edebilirsin.

## TEMEL YETENEKLERİN:
1. **Derinlemesine Analiz**: Akademik makaleleri, araştırma bulgularını ve
metodolojileri detaylı analiz et
2. **Görsel Yorumlama**: Grafik, tablo, diyagram ve şekilleri sayısal verilerle birlikte yorumla
3. **Kritik Değerlendirme**: Bulguların güçlü ve zayıf yönlerini belirt
4. **Bağlam Koruma**: Önceki konuşmaları hatırla ve tutarlı yanıtlar ver
5. **Kaynak Gösterme**: Her önemli bilgi için sayfa referansı ver
6. **Karşılaştırmalı Analiz**: Farklı bölümler arasında bağlantı kur

## YANITLAMA KURALLARI:
- Her zaman Türkçe yanıt ver
- Markdown formatını etkin kullan (başlıklar, listeler, kalın/italik)
- Sayısal verileri tablolarla göster
- Belirsiz veya eksik bilgileri açıkça belirt
- Uzun cevapları mantıklı bölümlere ayır
- Önemli kavramları **kalın** olarak vurgula
- Doğrudan alıntılarda "tırnak işareti" kullan

## KALİTE STANDARTLARI:
- Spekülasyon yapma, sadece dokümandaki bilgilere dayan
- İstatistiksel verileri doğru aktar (p-değeri, güven aralığı vb.)
- Metodolojik detayları atlama
- Karmaşık kavramları basitçe açıkla`;

export function getGeminiModel(options?: { system?: boolean }): GenerativeModel {
    const genAI = new GoogleGenerativeAI(getGeminiApiKey());
    return genAI.getGenerativeModel({
        model: process.env.GEMINI_MODEL || 'gemini-3-flash-preview',
        generationConfig: GENERATION_CONFIG,
        // OCR passes system: false — the analyst persona would make it
        // summarize/comment instead of returning raw text.
        ...(options?.system === false
            ? {}
            : { systemInstruction: SYSTEM_INSTRUCTION }),
    });
}

// Retries transient Gemini failures (429 / 5xx) the same way the iOS client
// does. Streaming callers are safe to wrap because the SDK promise rejects
// before any chunk is produced.
export async function withGeminiRetry<T>(operation: () => Promise<T>): Promise<T> {
    const delaysMs = [500, 1500];
    let lastError: unknown;
    for (let attempt = 0; attempt <= delaysMs.length; attempt++) {
        try {
            return await operation();
        } catch (error) {
            lastError = error;
            const message = error instanceof Error ? error.message : String(error);
            const transient = /429|500|502|503|rate limit|resource.*exhausted|overloaded/i.test(message);
            if (!transient || attempt === delaysMs.length) throw error;
            await new Promise(resolve => setTimeout(resolve, delaysMs[attempt]));
        }
    }
    throw lastError;
}

// Returns the authenticated user id, or null if the request has no valid session.
export async function getAuthenticatedUserId(): Promise<string | null> {
    const supabase = await createServerSupabase();
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) return null;
    return data.user.id;
}

export interface ChatHistoryMessage {
    role: 'user' | 'model';
    text: string;
}

export function historyToGeminiFormat(history: ChatHistoryMessage[]): Content[] {
    return history.map(msg => ({
        role: msg.role,
        parts: [{ text: msg.text }],
    }));
}

// Same budget idiom as the iOS client (word count × 1.3, 20k-token cap).
// Clients send the full conversation on every turn; without a cap, long
// sessions grow request size without bound and eventually 400.
const MAX_HISTORY_TOKENS = 20_000;

function estimatedTokens(text: string): number {
    return Math.ceil(text.split(/\s+/).filter(Boolean).length * 1.3);
}

export function trimHistoryToBudget(
    history: ChatHistoryMessage[],
    maxTokens: number = MAX_HISTORY_TOKENS
): ChatHistoryMessage[] {
    // Gemini requires history to start with a 'user' turn.
    const firstUser = history.findIndex(msg => msg.role === 'user');
    let trimmed = firstUser >= 0 ? history.slice(firstUser) : [];

    let total = trimmed.reduce((sum, msg) => sum + estimatedTokens(msg.text), 0);
    // Drop oldest user/model pairs whole so role alternation stays valid,
    // always keeping at least the most recent pair.
    while (total > maxTokens && trimmed.length > 2) {
        total -= estimatedTokens(trimmed[0].text) + estimatedTokens(trimmed[1]?.text ?? '');
        trimmed = trimmed.slice(2);
    }
    return trimmed;
}

// Converts a (data URL or raw) base64 image string into a Gemini inline part.
export function toImagePart(imageBase64: string): Part {
    const base64Data = imageBase64.includes(',')
        ? imageBase64.split(',')[1]
        : imageBase64;

    let mimeType = 'image/png';
    if (imageBase64.startsWith('data:')) {
        const match = imageBase64.match(/data:([^;]+);/);
        if (match) mimeType = match[1];
    }

    return {
        inlineData: {
            mimeType,
            data: base64Data,
        },
    };
}
