import { NextRequest } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { createSupabaseWithToken } from '@/lib/supabase';

export async function POST(req: NextRequest) {
    const authHeader = req.headers.get('Authorization');
    const token = authHeader?.replace('Bearer ', '').trim();
    if (!token) {
        return new Response('Unauthorized', { status: 401 });
    }

    const apiKey = process.env.GEMINI_API_KEY || process.env.NEXT_PUBLIC_GEMINI_API_KEY;
    if (!apiKey) {
        return Response.json({ error: 'Gemini API key not configured' }, { status: 500 });
    }

    let body: { fileId?: string; text?: string };
    try {
        body = await req.json();
    } catch {
        return new Response('Invalid JSON', { status: 400 });
    }

    const { fileId, text } = body;
    if (!text || typeof text !== 'string') {
        return new Response('text is required', { status: 400 });
    }

    const supabase = createSupabaseWithToken(token);
    const { error: authError } = await supabase.auth.getUser();
    if (authError) {
        return new Response('Unauthorized', { status: 401 });
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
        model: process.env.GEMINI_MODEL || process.env.NEXT_PUBLIC_GEMINI_MODEL || 'gemini-2.0-flash'
    });

    const prompt = `Aşağıdaki doküman metnini Türkçe olarak özetle. Özet kapsamlı ama kısa olsun.

## Kurallar
- Dokümanın ana konusunu belirt
- En önemli noktaları maddeler halinde listele
- Anahtar terimleri ve kavramları vurgula
- Maksimum 300 kelime
- Markdown formatı kullan

## Doküman Metni
${text.slice(0, 15000)}`;

    const encoder = new TextEncoder();
    const readable = new ReadableStream({
        async start(controller) {
            try {
                const result = await model.generateContentStream(prompt);
                let fullText = '';
                for await (const chunk of result.stream) {
                    const chunkText = chunk.text();
                    fullText += chunkText;
                    controller.enqueue(encoder.encode(chunkText));
                }

                // Save summary to files table if fileId provided
                if (fileId) {
                    await supabase
                        .from('files')
                        .update({ summary: fullText.slice(0, 500) })
                        .eq('id', fileId);
                }
            } catch (err) {
                console.error('Summarize error:', err);
                const errorMsg = err instanceof Error ? err.message : 'Bilinmeyen hata';
                controller.enqueue(encoder.encode(`\n\n⚠️ Özet oluşturulurken hata: ${errorMsg}`));
            } finally {
                controller.close();
            }
        }
    });

    return new Response(readable, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
}
