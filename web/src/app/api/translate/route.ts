import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { createSupabaseWithToken } from '@/lib/supabase';

export async function POST(req: NextRequest) {
    const authHeader = req.headers.get('Authorization');
    const token = authHeader?.replace('Bearer ', '').trim();
    if (!token) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await req.json().catch(() => null);
    const text = body?.text;
    const targetLang: string = body?.targetLang ?? 'tr';

    if (!text || typeof text !== 'string') {
        return NextResponse.json({ error: 'text is required' }, { status: 400 });
    }

    const supabase = createSupabaseWithToken(token);
    const { error: authError } = await supabase.auth.getUser();
    if (authError) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        return NextResponse.json({ error: 'Server misconfigured' }, { status: 500 });
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
        model: process.env.GEMINI_MODEL || 'gemini-2.0-flash'
    });

    const prompt = `Translate the following text to ${targetLang}. Only return the translation, nothing else:\n\n${text}`;

    try {
        const result = await model.generateContent(prompt);
        return NextResponse.json({ translation: result.response.text() });
    } catch (error) {
        console.error('Translation error:', error);
        return NextResponse.json({ error: 'Translation failed' }, { status: 502 });
    }
}
