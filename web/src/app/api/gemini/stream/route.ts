import { NextRequest, NextResponse } from 'next/server';
import {
    ChatHistoryMessage,
    getAuthenticatedUserId,
    getGeminiModel,
    historyToGeminiFormat,
    toImagePart,
    trimHistoryToBudget,
    withGeminiRetry,
} from '@/lib/server/gemini';
import { AI_STREAM_LIMIT, enforceRateLimit } from '@/lib/server/rateLimit';

function isValidHistory(value: unknown): value is ChatHistoryMessage[] {
    if (!Array.isArray(value)) return false;
    return value.every(item => {
        if (!item || typeof item !== 'object') return false;
        const msg = item as Record<string, unknown>;
        return (msg.role === 'user' || msg.role === 'model') && typeof msg.text === 'string';
    });
}

// Streaming Gemini generation (chat). Returns a plain text stream.
export async function POST(req: NextRequest) {
    const userId = await getAuthenticatedUserId();
    if (!userId) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const limited = enforceRateLimit('stream', userId, AI_STREAM_LIMIT);
    if (limited) return limited;

    let body: { prompt?: unknown; history?: unknown; imageBase64?: unknown };
    try {
        body = await req.json();
    } catch {
        return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const { prompt, history, imageBase64 } = body;
    if (typeof prompt !== 'string' || !prompt.trim()) {
        return NextResponse.json({ error: 'prompt is required' }, { status: 400 });
    }
    if (history !== undefined && !isValidHistory(history)) {
        return NextResponse.json({ error: 'history is malformed' }, { status: 400 });
    }
    if (imageBase64 !== undefined && typeof imageBase64 !== 'string') {
        return NextResponse.json({ error: 'imageBase64 must be a string' }, { status: 400 });
    }

    try {
        const model = getGeminiModel();

        let stream: AsyncGenerator<{ text: () => string }>;
        if (history && history.length > 0) {
            const trimmed = trimHistoryToBudget(history);
            const chat = model.startChat({ history: historyToGeminiFormat(trimmed) });
            stream = (await withGeminiRetry(() => chat.sendMessageStream(prompt))).stream;
        } else if (imageBase64) {
            stream = (await withGeminiRetry(() =>
                model.generateContentStream([prompt, toImagePart(imageBase64)])
            )).stream;
        } else {
            stream = (await withGeminiRetry(() => model.generateContentStream(prompt))).stream;
        }

        const encoder = new TextEncoder();
        const readable = new ReadableStream({
            async start(controller) {
                try {
                    for await (const chunk of stream) {
                        // Client went away (panel closed / new message sent):
                        // stop pumping instead of generating into the void.
                        if (req.signal.aborted) break;
                        controller.enqueue(encoder.encode(chunk.text()));
                    }
                    controller.close();
                } catch (error) {
                    controller.error(error);
                }
            },
        });

        return new Response(readable, {
            headers: {
                'Content-Type': 'text/plain; charset=utf-8',
                'Cache-Control': 'no-store',
            },
        });
    } catch (error) {
        console.error('Gemini stream error:', error);
        return NextResponse.json({ error: 'AI request failed' }, { status: 502 });
    }
}
