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

export function getGeminiModel(): GenerativeModel {
    const genAI = new GoogleGenerativeAI(getGeminiApiKey());
    return genAI.getGenerativeModel({
        model: process.env.GEMINI_MODEL || 'gemini-3-flash-preview',
    });
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
