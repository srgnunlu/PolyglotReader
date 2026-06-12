import { NextRequest, NextResponse } from 'next/server';
import { EMBEDDING_MODEL, getAuthenticatedUserId, getGeminiApiKey } from '@/lib/server/gemini';

// Generates a 768-dim embedding (text-embedding-004) for RAG search.
export async function POST(req: NextRequest) {
    const userId = await getAuthenticatedUserId();
    if (!userId) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    let body: { text?: unknown };
    try {
        body = await req.json();
    } catch {
        return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const { text } = body;
    if (typeof text !== 'string' || !text.trim()) {
        return NextResponse.json({ error: 'text is required' }, { status: 400 });
    }

    try {
        const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${EMBEDDING_MODEL}:embedContent`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'x-goog-api-key': getGeminiApiKey(),
                },
                body: JSON.stringify({
                    model: `models/${EMBEDDING_MODEL}`,
                    content: { parts: [{ text }] },
                }),
            }
        );

        if (!response.ok) {
            console.error('Embedding API error:', response.status, await response.text());
            return NextResponse.json({ error: 'Embedding request failed' }, { status: 502 });
        }

        const data = await response.json();
        return NextResponse.json({ embedding: data.embedding.values });
    } catch (error) {
        console.error('Embedding error:', error);
        return NextResponse.json({ error: 'Embedding request failed' }, { status: 502 });
    }
}
