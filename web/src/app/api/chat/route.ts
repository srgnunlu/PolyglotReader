import { NextRequest } from 'next/server';
import { GoogleGenerativeAI, Content } from '@google/generative-ai';
import { createSupabaseWithToken } from '@/lib/supabase';
import { searchRelevantChunksHybrid } from '@/lib/rag';

// Matches the ChatHistoryMessage type in gemini.ts
interface ChatHistoryMessage {
    role: 'user' | 'model';
    text: string;
}

// Mirrors shouldTranslateQuery logic from gemini.ts
function shouldTranslateQuery(query: string): boolean {
    const structuralPatterns = /\b(tablo|şekil|bölüm|sayfa|chapter|table|figure|section)\s*[\d.-]+/i;
    if (structuralPatterns.test(query)) return false;
    const wordCount = query.trim().split(/\s+/).length;
    if (wordCount <= 3) return false;
    const complexTerms = /\b(kardiyovasküler|pulmoner|nörolojik|travma|resüsitasyon|patofizyoloji|farmakoloji)\b/i;
    if (complexTerms.test(query)) return true;
    return false;
}

function buildContextHeader(): string {
    return `# Doküman Bölümleri\nAşağıda kullanıcının sorusuyla ilgili doküman bölümleri yer almaktadır.\n\n`;
}

function buildEnhancedPrompt(message: string, context: string): string {
    return `${context}

---

## Kullanıcı Sorusu
${message}

---

## Yanıt Kuralları

### 1. Kaynak Kullanımı ve Dil Uyumu
- **SADECE** yukarıdaki doküman bölümlerini kullan
- Dış bilgi veya varsayım YAPMA
- **ÖNEMLİ**: Doküman İngilizce, soru Türkçe olabilir:
  * İngilizce terimlerin Türkçe karşılıklarını kullanarak yanıtla
  * Hem orijinal terimi hem Türkçe karşılığı belirt
- Her önemli bilgi için kaynak göster: [1], [2] veya [Sayfa X]

### 2. Yanıt Formatı
- **Kısa soru** → Öz ve net cevap (1-3 cümle)
- **Açıklama istekleri** → Yapılandırılmış maddeler halinde
- **Karşılaştırma** → Tablo formatı kullan
- **Tanım soruları** → Önce tanım, sonra detay

### 3. Belirsizlik Durumu
Eğer konu dokümanda YOKSA:
- "Bu konuda doküman bilgi içermiyor." de
- ASLA uydurma bilgi verme

### 4. Dil ve Ton
- Akademik ama anlaşılır Türkçe
- Teknik terimleri hem İngilizce hem Türkçe ver

Şimdi yukarıdaki kurallara uyarak soruyu yanıtla:`;
}

export async function POST(req: NextRequest) {
    // --- Auth ---
    const authHeader = req.headers.get('Authorization');
    const token = authHeader?.replace('Bearer ', '').trim();
    if (!token) {
        return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const apiKey = process.env.GEMINI_API_KEY || process.env.NEXT_PUBLIC_GEMINI_API_KEY;
    if (!apiKey) {
        return Response.json({ error: 'Gemini API key not configured' }, { status: 500 });
    }

    let body: {
        message?: string;
        fileId?: string;
        history?: ChatHistoryMessage[];
        image?: string;
        context?: string;
    };
    try {
        body = await req.json();
    } catch {
        return Response.json({ error: 'Invalid JSON' }, { status: 400 });
    }

    const { message, fileId, history = [], image, context: providedContext } = body;

    if (!message || typeof message !== 'string') {
        return Response.json({ error: 'message is required' }, { status: 400 });
    }

    // --- Supabase (authenticated) ---
    const supabase = createSupabaseWithToken(token);

    // Verify the token is valid
    const { error: authError } = await supabase.auth.getUser();
    if (authError) {
        return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const geminiModel = process.env.GEMINI_MODEL || process.env.NEXT_PUBLIC_GEMINI_MODEL || 'gemini-2.0-flash';
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: geminiModel });

    // --- Build context ---
    let context = providedContext ?? '';

    if (fileId) {
        // RAG: always use hybrid search (Vector + BM25 + RRF) for best results
        let searchQuery = message;
        const hasTurkishChars = /[çğıöşüÇĞİÖŞÜ]/.test(message);
        if (hasTurkishChars && shouldTranslateQuery(message)) {
            try {
                // Query expansion: inline Gemini call on server
                const expandModel = genAI.getGenerativeModel({ model: geminiModel });
                const expandPrompt = `Sen bir tıbbi terminoloji uzmanısın. Bu Türkçe sorguyu İngilizce'ye çevir ve tıbbi terimlerle genişlet. SADECE terimleri ver, açıklama yapma, maksimum 10 kelime:\n"${message}"`;
                const expandResult = await expandModel.generateContent(expandPrompt);
                searchQuery = expandResult.response.text().trim();
            } catch {
                searchQuery = message;
            }
        }

        context = await searchRelevantChunksHybrid(fileId, searchQuery, 10, supabase);
    }

    // --- Build prompt ---
    const formattedContext = context ? buildContextHeader() + context : '';
    const prompt = formattedContext ? buildEnhancedPrompt(message, formattedContext) : message;

    // --- Stream Gemini response ---
    const encoder = new TextEncoder();
    const readable = new ReadableStream({
        async start(controller) {
            try {
                if (image) {
                    // Image + context mode
                    const base64Data = image.includes(',') ? image.split(',')[1] : image;
                    let mimeType = 'image/png';
                    if (image.startsWith('data:')) {
                        const match = image.match(/data:([^;]+);/);
                        if (match) mimeType = match[1];
                    }
                    const imagePart = { inlineData: { mimeType, data: base64Data } };
                    const textPrompt = formattedContext
                        ? `Döküman bağlamı:\n${formattedContext}\n\nKullanıcı sorusu: ${message}\n\nLütfen görseli analiz ederek soruyu yanıtla.`
                        : message;
                    const result = await model.generateContentStream([textPrompt, imagePart]);
                    for await (const chunk of result.stream) {
                        controller.enqueue(encoder.encode(chunk.text()));
                    }
                } else if (history.length > 0) {
                    // Chat with history
                    const geminiHistory: Content[] = history.map(m => ({
                        role: m.role,
                        parts: [{ text: m.text }]
                    }));
                    const chat = model.startChat({ history: geminiHistory });
                    const result = await chat.sendMessageStream(prompt);
                    for await (const chunk of result.stream) {
                        controller.enqueue(encoder.encode(chunk.text()));
                    }
                } else {
                    // Simple generate
                    const result = await model.generateContentStream(prompt);
                    for await (const chunk of result.stream) {
                        controller.enqueue(encoder.encode(chunk.text()));
                    }
                }
            } catch (err) {
                console.error('Chat stream error:', err);
                const errorMsg = err instanceof Error ? err.message : 'Bilinmeyen hata';
                controller.enqueue(encoder.encode(`\n\n⚠️ AI yanıtı oluşturulurken hata: ${errorMsg}`));
            } finally {
                controller.close();
            }
        }
    });

    return new Response(readable, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
}
