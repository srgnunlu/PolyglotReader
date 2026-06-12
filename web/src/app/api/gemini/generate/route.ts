import { NextRequest, NextResponse } from 'next/server';
import { getAuthenticatedUserId, getGeminiModel, toImagePart } from '@/lib/server/gemini';

// Non-streaming Gemini generation (translation, summary, smart note, image Q&A).
export async function POST(req: NextRequest) {
    const userId = await getAuthenticatedUserId();
    if (!userId) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    let body: { prompt?: unknown; imageBase64?: unknown };
    try {
        body = await req.json();
    } catch {
        return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const { prompt, imageBase64 } = body;
    if (typeof prompt !== 'string' || !prompt.trim()) {
        return NextResponse.json({ error: 'prompt is required' }, { status: 400 });
    }
    if (imageBase64 !== undefined && typeof imageBase64 !== 'string') {
        return NextResponse.json({ error: 'imageBase64 must be a string' }, { status: 400 });
    }

    try {
        const model = getGeminiModel();
        const result = imageBase64
            ? await model.generateContent([prompt, toImagePart(imageBase64)])
            : await model.generateContent(prompt);

        return NextResponse.json({ text: result.response.text() });
    } catch (error) {
        console.error('Gemini generate error:', error);
        return NextResponse.json({ error: 'AI request failed' }, { status: 502 });
    }
}
