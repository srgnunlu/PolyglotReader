import { NextRequest, NextResponse } from 'next/server';
import { getAuthenticatedUserId, getGeminiModel, toImagePart } from '@/lib/server/gemini';
import { AI_OCR_LIMIT, enforceRateLimit } from '@/lib/server/rateLimit';

// A page canvas exported as JPEG at 0.85 quality stays well under this; the
// guard exists so nobody can funnel arbitrarily large payloads to Gemini.
const MAX_IMAGE_BASE64_LENGTH = 4 * 1024 * 1024; // ~4MB of base64 (~3MB binary)

const ALLOWED_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

// Reading-order matters for the downstream translate flow, so the prompt is
// explicit about multi-column layout instead of trusting model defaults.
const OCR_PROMPT = `Extract ALL text from this scanned document page image.
Rules:
- Return the text in natural reading order. If the page has multiple columns, read the left column top to bottom first, then the next column.
- Preserve paragraph breaks; do not merge separate paragraphs.
- Include headings, footnotes and figure captions where they occur in reading order.
- Do NOT translate, summarize, comment, or add anything. Return ONLY the extracted text.
- If the page contains no readable text, return nothing.`;

// Server-side OCR for scanned PDF pages (no text layer). Accepts a page
// rendered to an image and returns the recognized text.
export async function POST(req: NextRequest) {
    const userId = await getAuthenticatedUserId();
    if (!userId) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const limited = enforceRateLimit('ocr', userId, AI_OCR_LIMIT);
    if (limited) return limited;

    let body: { image?: unknown; mimeType?: unknown };
    try {
        body = await req.json();
    } catch {
        return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const { image, mimeType } = body;
    if (typeof image !== 'string' || !image.trim()) {
        return NextResponse.json({ error: 'image is required' }, { status: 400 });
    }
    if (image.length > MAX_IMAGE_BASE64_LENGTH) {
        return NextResponse.json({ error: 'image too large (max ~4MB base64)' }, { status: 413 });
    }
    if (mimeType !== undefined) {
        if (typeof mimeType !== 'string' || !ALLOWED_MIME_TYPES.has(mimeType)) {
            return NextResponse.json({ error: 'unsupported mimeType' }, { status: 400 });
        }
    }

    // Data URLs carry their own mime type; raw base64 falls back to the
    // provided mimeType (client sends JPEG canvas exports).
    const imagePart = image.startsWith('data:')
        ? toImagePart(image)
        : { inlineData: { mimeType: (mimeType as string | undefined) ?? 'image/jpeg', data: image } };

    try {
        // system: false — the analyst system instruction would make OCR
        // summarize/comment instead of returning the raw page text.
        const model = getGeminiModel({ system: false });
        const result = await model.generateContent([OCR_PROMPT, imagePart]);
        return NextResponse.json({ text: result.response.text() });
    } catch (error) {
        // Log the error only — never the image payload (may contain PII).
        console.error('Gemini OCR error:', error);
        return NextResponse.json({ error: 'AI request failed' }, { status: 502 });
    }
}
