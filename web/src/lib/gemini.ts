// Client-side Gemini facade. All AI calls go through /api/gemini/* route
// handlers so the API key stays on the server. Prompt building lives here.

// MARK: - Chat Message Type for History
export interface ChatHistoryMessage {
    role: 'user' | 'model';
    text: string;
}

// MARK: - API helpers

async function generateViaApi(prompt: string, imageBase64?: string): Promise<string> {
    const response = await fetch('/api/gemini/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt, imageBase64 }),
    });

    if (!response.ok) {
        const data = await response.json().catch(() => null);
        throw new Error(data?.error || `AI request failed (${response.status})`);
    }

    const data = await response.json();
    return data.text;
}

async function* streamViaApi(
    prompt: string,
    history?: ChatHistoryMessage[],
    imageBase64?: string
): AsyncGenerator<string, void, unknown> {
    const response = await fetch('/api/gemini/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt, history, imageBase64 }),
    });

    if (!response.ok || !response.body) {
        const data = await response.json().catch(() => null);
        throw new Error(data?.error || `AI request failed (${response.status})`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const text = decoder.decode(value, { stream: true });
        if (text) yield text;
    }
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

// Translation
export async function translateText(
    text: string,
    targetLang: string = 'tr'
): Promise<string> {
    const prompt = `Translate the following text to ${targetLang}. Only return the translation, nothing else:\n\n${text}`;
    return generateViaApi(prompt);
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
        const expandedQuery = (await generateViaApi(prompt)).trim();
        console.log(`🔄 Query expansion: "${query}" → "${expandedQuery}"`);
        return expandedQuery;
    } catch (error) {
        console.error('Query expansion failed:', error);
        // Fallback: basit çeviri
        return query;
    }
}

// Raw single-shot generation. Used by features that build their own prompt
// (e.g. citation metadata extraction) and parse the model's reply themselves.
export async function generateRaw(prompt: string): Promise<string> {
    return generateViaApi(prompt);
}

// Chat with context
export async function chatWithContext(
    message: string,
    context: string
): Promise<string> {
    const prompt = `You are a helpful assistant analyzing a document. Use the following context to answer the question.

Context from document:
${context}

User question: ${message}

Please provide a helpful, accurate answer based on the context. If the answer cannot be found in the context, say so clearly.`;

    return generateViaApi(prompt);
}

// Document summary
export async function generateSummary(text: string): Promise<string> {
    const prompt = `Summarize the following document text in Turkish. Keep it concise but comprehensive:\n\n${text}`;
    return generateViaApi(prompt);
}

// Smart note from selection
export async function generateSmartNote(text: string): Promise<string> {
    const prompt = `Read this text and generate a smart note in Turkish. Include key points, important concepts, and any notable insights:\n\n${text}`;
    return generateViaApi(prompt);
}

// Stream chat (for real-time responses)
export async function* streamChat(
    message: string,
    context?: string
): AsyncGenerator<string, void, unknown> {
    const prompt = context
        ? `Context from document:\n${context}\n\nUser question: ${message}\n\nProvide a helpful answer based on the context.`
        : message;

    yield* streamViaApi(prompt);
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

    // Build context with header
    const formattedContext = context
        ? buildContextHeader() + context
        : '';

    // Build enhanced prompt
    const prompt = formattedContext
        ? buildEnhancedPrompt(message, formattedContext)
        : message;

    yield* streamViaApi(prompt, history.length > 0 ? history : undefined);
}


// MARK: - Library-wide Chat (Multi-document RAG)

interface LibraryFileRef {
    id: string;
    name: string;
}

function buildLibraryPrompt(message: string, context: string): string {
    return `# Kütüphane Bölümleri
Aşağıda kullanıcının sorusuyla ilgili, kütüphanedeki **birden fazla dokümandan** alınan bölümler yer almaktadır. Her bölümün başında kaynak dosya adı ve sayfası belirtilmiştir.

${context}

---

## Kullanıcı Sorusu
${message}

---

## Yanıt Kuralları
- **SADECE** yukarıdaki doküman bölümlerini kullan; dış bilgi veya varsayım YAPMA
- Her önemli bilgi için kaynağı belirt: dosya adı ve sayfa — örn. "(rapor.pdf, Sayfa 4)"
- Farklı dokümanlardan gelen bilgileri karşılaştırırken hangi dosyadan geldiğini netleştir
- Doküman İngilizce, soru Türkçe olabilir: terimlerin Türkçe karşılığını da ver
- Akademik ama anlaşılır Türkçe kullan; gereksiz tekrardan kaçın
- Eğer konu hiçbir dokümanda yoksa: "Kütüphanenizdeki dokümanlar bu konuda bilgi içermiyor." de — ASLA uydurma

Şimdi yukarıdaki kurallara uyarak soruyu yanıtla:`;
}

/**
 * Kütüphane-geneli sohbet: birden fazla doküman üzerinde RAG araması yapar
 * ve konuşma geçmişiyle birlikte yanıt akışı döndürür.
 */
export async function* streamLibraryChat(
    message: string,
    files: LibraryFileRef[],
    history: ChatHistoryMessage[]
): AsyncGenerator<string, void, unknown> {
    const { searchLibraryChunks } = await import('./rag');

    const context = await searchLibraryChunks(files, message);
    const prompt = context ? buildLibraryPrompt(message, context) : message;

    yield* streamViaApi(prompt, history.length > 0 ? history : undefined);
}

// Chat with image - for image-based questions
export async function chatWithImage(
    message: string,
    imageBase64: string,
    context?: string
): Promise<string> {
    const textPrompt = context
        ? `Döküman bağlamı:\n${context}\n\nKullanıcı sorusu: ${message}\n\nLütfen görseli analiz ederek soruyu yanıtla.`
        : message;

    return generateViaApi(textPrompt, imageBase64);
}

// Stream chat with image - for real-time responses with image
export async function* streamChatWithImage(
    message: string,
    imageBase64: string,
    context?: string
): AsyncGenerator<string, void, unknown> {
    const textPrompt = context
        ? `Döküman bağlamı:\n${context}\n\nKullanıcı sorusu: ${message}\n\nLütfen görseli analiz ederek soruyu yanıtla.`
        : message;

    yield* streamViaApi(textPrompt, undefined, imageBase64);
}
