import { GoogleGenerativeAI, GenerativeModel, Content } from '@google/generative-ai';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);

function getModel(): GenerativeModel {
    return genAI.getGenerativeModel({
        model: process.env.GEMINI_MODEL ?? 'gemini-2.0-flash'
    });
}

// MARK: - Chat Message Type for History
export interface ChatHistoryMessage {
    role: 'user' | 'model';
    text: string;
}

// MARK: - Enhanced Prompt Builder (NotebookLM-Style)
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
  * Örnek: "long spine board" → "uzun sırt tahtası" veya "travma tahtası"
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
- Varsa ilgili/yakın konuları öner: "Ancak Sayfa X'te ilgili konu ele alınıyor: ..."
- **NOT**: İngilizce terimler için Türkçe karşılıkları düşün!
  * "spinal board", "backboard" → "sırt tahtası", "travma tahtası", "omurga tahtası"
  * "cardiac arrest" → "kalp durması", "kardiyak arrest"
- ASLA uydurma bilgi verme

### 4. Dil ve Ton
- Akademik ama anlaşılır Türkçe
- Teknik terimleri hem İngilizce hem Türkçe ver
- Örnek: "Long spine board (uzun sırt tahtası)..."
- Gereksiz tekrardan kaçın

Şimdi yukarıdaki kurallara uyarak, özellikle çapraz dil eşleştirmesine dikkat ederek soruyu yanıtla:`;
}

// MARK: - Build Context Header (matches mobile)
function buildContextHeader(): string {
    return `# Doküman Bölümleri
Aşağıda kullanıcının sorusuyla ilgili doküman bölümleri yer almaktadır.

`;
}

// MARK: - Convert history to Gemini format
function historyToGeminiFormat(history: ChatHistoryMessage[]): Content[] {
    return history.map(msg => ({
        role: msg.role,
        parts: [{ text: msg.text }]
    }));
}

// Translation
export async function translateText(
    text: string,
    targetLang: string = 'tr'
): Promise<string> {
    const model = getModel();
    const prompt = `Translate the following text to ${targetLang}. Only return the translation, nothing else:\n\n${text}`;

    const result = await model.generateContent(prompt);
    return result.response.text();
}

/**
 * Sorgunun İngilizce'ye çevrilmesi gerekip gerekmediğini akıllıca belirler.
 * Yapısal referansları (Tablo, Şekil, Bölüm + rakamlar) korur.
 */
function shouldTranslateQuery(query: string): boolean {
    // Tablo/Şekil/Bölüm referansları asla çevrilmemeli
    // Örnekler: "Tablo 2-1", "Şekil 3.4", "Bölüm 5", "Table 2-1"
    const structuralPatterns = /\b(tablo|şekil|bölüm|sayfa|chapter|table|figure|section)\s*[\d.-]+/i;
    if (structuralPatterns.test(query)) {
        console.log(`🔒 Query contains structural reference, skipping translation: "${query}"`);
        return false;
    }

    // Çok kısa sorguları çevirme (3 kelime veya daha az)
    const wordCount = query.trim().split(/\s+/).length;
    if (wordCount <= 3) {
        console.log(`🔒 Query too short (${wordCount} words), skipping translation: "${query}"`);
        return false;
    }

    // Karmaşık tıbbi/teknik terimler varsa çevir
    const complexTerms = /\b(kardiyovasküler|pulmoner|nörolojik|travma|resüsitasyon|patofizyoloji|farmakoloji)\b/i;
    if (complexTerms.test(query)) {
        console.log(`🔄 Query contains complex medical terms, will translate: "${query}"`);
        return true;
    }

    // Varsayılan: Türkçe karakter varsa ama yapısal referans yoksa çevirme
    // Basit sorular için direkt Türkçe arama daha iyi sonuç verir
    console.log(`🔒 Using original query without translation: "${query}"`);
    return false;
}

/**
 * Sorguyu İngilizce'ye çevirir ve tıbbi/teknik terimlerle genişletir
 * RAG için daha iyi sonuçlar alınmasını sağlar
 */
export async function translateAndExpandQuery(query: string): Promise<string> {
    const model = getModel();

    const prompt = `Sen bir tıbbi terminoloji uzmanısın. Aşağıdaki Türkçe sorguyu İngilizce'ye çevir ve tıbbi terimlerle genişlet.

Türkçe sorgu: "${query}"

Kurallar:
1. Önce direkt İngilizce çeviri yap
2. Tıbbi terimlerin alternatif isimlerini ekle
3. Kısa ve öz tut (maksimum 10 kelime)
4. SADECE terimleri ver, açıklama yapma

Örnekler:
- "sırt tahtası nedir" → "backboard spinal board spine board immobilization"
- "kalp durması tedavisi" → "cardiac arrest resuscitation CPR treatment"
- "vazopressör dozları" → "vasopressor doses epinephrine norepinephrine"

Şimdi yukarıdaki sorguyu çevir ve genişlet (SADECE terimleri ver):`;

    try {
        const result = await model.generateContent(prompt);
        const expandedQuery = result.response.text().trim();
        console.log(`🔄 Query expansion: "${query}" → "${expandedQuery}"`);
        return expandedQuery;
    } catch (error) {
        console.error('Query expansion failed:', error);
        // Fallback: basit çeviri
        return query;
    }
}

// Chat with context
export async function chatWithContext(
    message: string,
    context: string
): Promise<string> {
    const model = getModel();
    const prompt = `You are a helpful assistant analyzing a document. Use the following context to answer the question.

Context from document:
${context}

User question: ${message}

Please provide a helpful, accurate answer based on the context. If the answer cannot be found in the context, say so clearly.`;

    const result = await model.generateContent(prompt);
    return result.response.text();
}

// Document summary
export async function generateSummary(text: string): Promise<string> {
    const model = getModel();
    const prompt = `Summarize the following document text in Turkish. Keep it concise but comprehensive:\n\n${text}`;

    const result = await model.generateContent(prompt);
    return result.response.text();
}

// Smart note from selection
export async function generateSmartNote(text: string): Promise<string> {
    const model = getModel();
    const prompt = `Read this text and generate a smart note in Turkish. Include key points, important concepts, and any notable insights:\n\n${text}`;

    const result = await model.generateContent(prompt);
    return result.response.text();
}

// Stream chat (for real-time responses)
export async function* streamChat(
    message: string,
    context?: string
): AsyncGenerator<string, void, unknown> {
    const model = getModel();

    const prompt = context
        ? `Context from document:\n${context}\n\nUser question: ${message}\n\nProvide a helpful answer based on the context.`
        : message;

    const result = await model.generateContentStream(prompt);

    for await (const chunk of result.stream) {
        yield chunk.text();
    }
}

// Stream chat with dynamic RAG search (for document-aware responses)
// DEPRECATED: Use streamChatWithRAGAndHistory instead for memory support
export async function* streamChatWithRAG(
    message: string,
    fileId: string
): AsyncGenerator<string, void, unknown> {
    // Forward to new function with empty history for backward compatibility
    yield* streamChatWithRAGAndHistory(message, fileId, []);
}

// MARK: - Stream Chat with RAG + Conversation History (Memory Support)
// Bu fonksiyon hem RAG hem de önceki mesajları hatırlama özelliği sağlar
export async function* streamChatWithRAGAndHistory(
    message: string,
    fileId: string,
    history: ChatHistoryMessage[]
): AsyncGenerator<string, void, unknown> {
    // Dynamic import to avoid circular dependency
    const { searchRelevantChunksHybrid } = await import('./rag');

    // GÜNCELLEME: Sadece karmaşık sorguları çevir/genişlet, yapısal referansları koru
    let searchQuery = message;
    const hasTurkishChars = /[çğıöşüÇĞİÖŞÜ]/.test(message);

    // Akıllı çeviri: "Tablo 2-1" gibi referansları korur
    if (hasTurkishChars && shouldTranslateQuery(message)) {
        try {
            searchQuery = await translateAndExpandQuery(message);
            console.log(`📝 Using expanded query for RAG: "${searchQuery}"`);
        } catch (error) {
            console.warn('Query expansion failed, using original:', error);
            searchQuery = message;
        }
    } else {
        console.log(`📝 Using original query for RAG: "${searchQuery}"`);
    }

    // Search for relevant chunks using hybrid search
    const context = await searchRelevantChunksHybrid(fileId, searchQuery, 10);

    const model = getModel();

    // Build context with header
    const formattedContext = context
        ? buildContextHeader() + context
        : '';

    // Build enhanced prompt
    const prompt = formattedContext
        ? buildEnhancedPrompt(message, formattedContext)
        : message;

    // If we have conversation history, use chat session for memory
    if (history.length > 0) {
        // Convert history to Gemini format
        const geminiHistory = historyToGeminiFormat(history);

        // Start chat with history
        const chat = model.startChat({
            history: geminiHistory
        });

        // Send new message with streaming
        const result = await chat.sendMessageStream(prompt);

        for await (const chunk of result.stream) {
            yield chunk.text();
        }
    } else {
        // No history - use simple generate
        const result = await model.generateContentStream(prompt);

        for await (const chunk of result.stream) {
            yield chunk.text();
        }
    }
}


// Chat with image - for image-based questions
export async function chatWithImage(
    message: string,
    imageBase64: string,
    context?: string
): Promise<string> {
    const model = getModel();

    // Extract base64 data (remove data URL prefix if present)
    const base64Data = imageBase64.includes(',')
        ? imageBase64.split(',')[1]
        : imageBase64;

    // Detect mime type from data URL or default to PNG
    let mimeType = 'image/png';
    if (imageBase64.startsWith('data:')) {
        const match = imageBase64.match(/data:([^;]+);/);
        if (match) mimeType = match[1];
    }

    const imagePart = {
        inlineData: {
            mimeType,
            data: base64Data,
        },
    };

    const textPrompt = context
        ? `Döküman bağlamı:\n${context}\n\nKullanıcı sorusu: ${message}\n\nLütfen görseli analiz ederek soruyu yanıtla.`
        : message;

    const result = await model.generateContent([textPrompt, imagePart]);
    return result.response.text();
}

// Stream chat with image - for real-time responses with image
export async function* streamChatWithImage(
    message: string,
    imageBase64: string,
    context?: string
): AsyncGenerator<string, void, unknown> {
    const model = getModel();

    // Extract base64 data
    const base64Data = imageBase64.includes(',')
        ? imageBase64.split(',')[1]
        : imageBase64;

    // Detect mime type
    let mimeType = 'image/png';
    if (imageBase64.startsWith('data:')) {
        const match = imageBase64.match(/data:([^;]+);/);
        if (match) mimeType = match[1];
    }

    const imagePart = {
        inlineData: {
            mimeType,
            data: base64Data,
        },
    };

    const textPrompt = context
        ? `Döküman bağlamı:\n${context}\n\nKullanıcı sorusu: ${message}\n\nLütfen görseli analiz ederek soruyu yanıtla.`
        : message;

    const result = await model.generateContentStream([textPrompt, imagePart]);

    for await (const chunk of result.stream) {
        yield chunk.text();
    }
}
