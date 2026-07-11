# PolyglotReader — RAG, Chat ve AI Yanıt Kalitesi Analizi

> Tarih: 2026-07-11 · Kapsam: iOS (`PolyglotReader/`) + Web (`web/`) · Yöntem: 5 paralel kod incelemesi, tüm bulgular file:line referanslı.
> Bu rapor salt analiz içindir; hiçbir kod değiştirilmemiştir.

---

## Yönetici Özeti (TL;DR)

**Genel durum:** iOS tarafındaki RAG + chat sistemi olgun ve profesyonel seviyede (yapı-farkında chunking, hibrit arama, LLM rerank, streaming, token bütçeli history, zengin UI). Web tarafı ise iOS'un "hafif kopyası" gibi davranıyor ama kritik parçaları eksik: **system prompt yok, generationConfig yok, history trimming yok, retry yok, indeksleme yok**. En büyük yapısal sorunlar:

1. **Chunk metadata'sı DB'ye yazılmıyor** — tablo/başlık önceliklendirmesi fiilen çalışmıyor (kod var ama etkisiz).
2. **Web'de Gemini system instruction + generationConfig tamamen yok** → web yanıtları default (yüksek) temperature ile üretiliyor; iOS'tan belirgin kalite farkı.
3. **iOS system prompt'unda ters anlam bug'ı**: "Metodolojik detayları atla" (atlama olmalıydı).
4. **Supabase'den yüklenen chat geçmişi Gemini session'ına enjekte edilmiyor** → uygulama yeniden açıldığında model önceki konuşmayı hatırlamıyor (kullanıcı ekranda görüyor ama model bilmiyor).
5. **ivfflat vektör index'i migration zincirinde DROP edilip yeniden yaratılmamış** olabilir → vektör aramanın sessizce full-scan'e düşme riski.
6. **BM25 Türkçe stemming kullanmıyor** (`'simple'` tsvector) → TR sorgularda keyword recall düşük.
7. Web'den yüklenen dosyalar hiç indekslenmiyor (chunking yalnız iOS'ta) → web chat bu dosyalarda bağlamsız fallback'e düşüyor.

---

# BÖLÜM 1 — DETAYLI RAPOR

## 1. RAG (Retrieval-Augmented Generation) Sistemi

### 1.1 Mevcut durum

**Mimari:** `RAGService` facade → `RAGChunker` + `RAGEmbeddingService` + `RAGSearchService` + `RAGContextBuilder` + `GeminiRAGService` (rerank/expansion). İndeksleme (chunk + embedding + DB yazma) **yalnızca iOS'ta**; web (`web/src/lib/rag.ts`) sadece arama yapıyor.

| Parametre | Değer | Referans |
|---|---|---|
| Embedding modeli | `gemini-embedding-001` (text-embedding-004 emekli, 404 dönüyor) | [RAGConfig.swift:45](PolyglotReader/Services/RAG/RAGConfig.swift:45) |
| Embedding boyutu | 768 (`outputDimensionality=768` ile kesiliyor; model default'u 3072) | [RAGConfig.swift:46](PolyglotReader/Services/RAG/RAGConfig.swift:46), [RAGEmbeddingService.swift:270-281](PolyglotReader/Services/RAG/RAGEmbeddingService.swift:270) |
| Similarity metriği | Cosine (`<=>` operatörü, `vector_cosine_ops`) | migrations/20260109150658 (satır 181), 20260103133658 (satır 25) |
| Index | ivfflat `lists=100` (HNSW yorum satırında, aktif değil) | migrations/20251224212455 (satır 24-27) |
| Vector threshold | iOS **0.45**, web **0.30**, DB default'ları 0.60/0.35/0.25 (migrationlara göre değişken!) | [RAGConfig.swift:19](PolyglotReader/Services/RAG/RAGConfig.swift:19), [rag.ts:5](web/src/lib/rag.ts:5) |
| Top-k | iOS normal 10, derin arama 24, context'e giren 6; web topK 15 / rerankTopK 8 | [RAGConfig.swift:14-18](PolyglotReader/Services/RAG/RAGConfig.swift:14), [rag.ts:9-10](web/src/lib/rag.ts:9) |
| RRF | Client-side, k=60, ağırlıklı (vector 0.65 / BM25 0.35) + sayfa 1.5x, figür 1.3x boost | [RAGSearchService.swift:435-512](PolyglotReader/Services/RAG/RAGSearchService.swift:435), [RAGConfig.swift:21-23](PolyglotReader/Services/RAG/RAGConfig.swift:21) |
| Context bütçesi | Normal 30k, kısa sorgu 12k, karşılaştırma 50k, derin arama min 40k token | [RAGConfig.swift:27-32](PolyglotReader/Services/RAG/RAGConfig.swift:27) |

**Hybrid search:** Vector (`match_chunks` RPC) + BM25 (`search_chunks_bm25` RPC) ayrı çekilip client-side RRF ile birleştiriliyor ([RAGSearchService.swift:98-137](PolyglotReader/Services/RAG/RAGSearchService.swift:98)). SQL tarafındaki `hybrid_search_chunks` RPC'si **hiç çağrılmıyor** (ölü kod).

**Re-ranking:** Var — Gemini tabanlı LLM rerank, chunk'ları 0-10 puanlıyor ([GeminiRAGService.swift:23-61](PolyglotReader/Services/Gemini/GeminiRAGService.swift:23)). Yalnızca **Derin Arama** modunda tetikleniyor ([RAGService.swift:479-515](PolyglotReader/Services/RAGService.swift:479)); normal chat'te rerank yok. Web'de rerank hiç yok.

**Metadata filtering:** Sayfa numarası sorgudan çıkarılıp doğrudan çekiliyor ([RAGSearchService.swift:26-46](PolyglotReader/Services/RAG/RAGSearchService.swift:26)); "Figure 2-1"/"Tablo 2" referansları ILIKE ile aranıyor ([RAGSearchService.swift:48-78](PolyglotReader/Services/RAG/RAGSearchService.swift:48)). Bölüm başlığıyla filtreleme yok (DB'de sütun bile yok).

**İndeksleme tetikleyicileri:** Upload ([LibraryViewModel+Upload.swift:111](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift:111)), Reader açılışı ([PDFReaderViewModel.swift:283-294](PolyglotReader/ViewModels/PDFReaderViewModel.swift:283)), Chat açılışı ([ChatViewModel.swift:291-307](PolyglotReader/ViewModels/ChatViewModel.swift:291)). Tekrar önleme: `getChunkCount > 0` + process-içi task dedup + `reindex_document` RPC (önce siler).

### 1.2 Güçlü yanlar

- Profesyonel hibrit arama: vector + BM25 + RRF + akıllı boost'lar; sayfa/figür farkındalıklı sorgu analizi.
- Derin Arama modu gerçekten derin (24 aday + 40k context + LLM rerank + query expansion) — commit 879f354 ile güçlendirilmiş.
- Cross-lingual retrieval: sorgu aramadan önce İngilizceye çevriliyor ([GeminiRAGService.swift:126-172](PolyglotReader/Services/Gemini/GeminiRAGService.swift:126)) — TR soru → EN makale senaryosu çözülmüş.
- Çift katmanlı embedding cache (LRU memory 500 + disk TTL 4 saat), cache key model adını içeriyor ([RAGEmbeddingService.swift:110-214](PolyglotReader/Services/RAG/RAGEmbeddingService.swift:110)).
- Batch embedding (5'li paralel) + retry + rate-limit mapping ([RAGService.swift:168-206](PolyglotReader/Services/RAGService.swift:168)).
- Görsel-caption RAG: görseller Vision ile bulunup Gemini caption + caption_embedding üretiliyor, chat'te chunk aramasıyla **paralel** sorgulanıyor ([ChatViewModel+Messaging.swift:214-321](PolyglotReader/ViewModels/ChatViewModel+Messaging.swift:214)).

### 1.3 Zayıf yanlar / hatalar

1. **⚠️ Chunk metadata'sı persist edilmiyor (en önemli yapısal sorun).** `sectionTitle`, `contentType`, `containsTable`, `containsList`, `imageReferences` chunker'da hesaplanıyor ama `saveDocumentChunks` yalnızca `content/embedding/page_number` yazıyor ([RAGService.swift:278](PolyglotReader/Services/RAGService.swift:278)). Arama sonuçlarında bu alanlar hep default (false/nil) dönüyor → context builder'daki tablo rozetleri ve RRF'deki tablo boost'u **fiilen hiç tetiklenmiyor**. Kod var, etkisi yok.
2. **⚠️ ivfflat index güvenilmez.** `20251228105009_cleanup_duplicate_indexes.sql` embedding index'ini DROP ediyor ama yeniden yaratmıyor; sonraki migrationlar `IF NOT EXISTS` kullandığından migration sırasına göre vektör index'i **hiç olmayabilir** → sessiz full-scan. Prod DB'de `\di document_chunks*` ile doğrulanmalı.
3. **BM25 Türkçe stemming'siz.** Saklanan `ts_content` `to_tsvector('simple', ...)` ile üretiliyor (migration 20260109115254, satır 22-23). iOS hep 'simple' arıyor; web'in kullandığı `search_chunks_bm25_lang` ise runtime `to_tsvector` hesapladığı için **GIN index'i kullanmıyor** (full-scan, büyük dokümanlarda yavaş).
4. **Threshold/parametre kaosu.** Vector eşiği: DB default'ları 0.60→0.35→0.25 (üç migration), iOS 0.45, web 0.30. topK: iOS 10 / web 15. Tek doğruluk kaynağı yok; iki platform aynı soruya farklı chunk seti getiriyor.
5. **Rerank skor ölçeği normalize değil.** `finalScore = rerankScore(0-10) ?? rrfScore(~0.02)` ([RAGModels.swift:120-122](PolyglotReader/Services/RAG/RAGModels.swift:120)) — kısmi rerank'ta karışık ölçek, tutarsız sıralama olasılığı.
6. **Ölü RPC yığını:** `hybrid_search_chunks`, `search_image_captions` (pdf_images sürümü), `match_document_chunks_v2` (iOS için), eski `reciprocalRankFusion`, `ExpandedQuery.hypotheticalAnswer` (HyDE kalıntısı) — hiçbiri çağrılmıyor.
7. **Web vector RPC "shotgun" deseni:** 4 farklı RPC imzasını sırayla deniyor ([rag.ts:301-347](web/src/lib/rag.ts:301)) — kırılgan; iOS tek RPC kullanıyor.
8. `fetchChunksByContentSearch` çoklu figür referansında yalnız ilk pattern'i arıyor ([SupabaseService+RAG.swift:174-182](PolyglotReader/Services/Supabase/SupabaseService+RAG.swift:174)).
9. `match_chunks`'a embedding JSON float dizisi olarak gönderiliyor, diğer RPC'ler text→vector cast kullanıyor — iki farklı geçiş biçimi ([SupabaseTypes.swift:5-22](PolyglotReader/Services/Supabase/SupabaseTypes.swift:5)).

### 1.4 Performans sorunları

- Gemini `embedContent` tekil endpoint → yüzlerce chunk'lı doküman = yüzlerce API çağrısı (5'li paralel hafifletiyor ama batch API yok).
- Arama başına **iki** embedding çağrısı: chunk search + image caption search ayrı embedding üretiyor; query expansion sonrası metin farklıysa cache yakalamıyor.
- Üç ayrı indeksleme tetikleyicisi (upload/reader/chat) process'ler arası yarışırsa çift embedding maliyeti (sonuç duplike olmaz ama para harcanır).
- `estimateTokens` = kelime × 1.3 — Türkçe agglutinatif yapıda gerçek token'ı düşük tahmin ediyor; 30k "token" bütçesi fiilen daha büyük olabilir.

---

## 2. Chunk Sistemi

### 2.1 Mevcut durum

- **Metin çıkarma:** `PDFTextExtractor` sayfa markerları (`--- Sayfa X/Y ---`) ekliyor ([PDFTextExtractor.swift:164-167](PolyglotReader/Services/PDF/PDFTextExtractor.swift:164)); tablolar `[TABLO_BAŞLANGIÇ]/[TABLO_BİTİŞ]` markerlarıyla işaretlenip tab/çoklu-boşluk `|` ile hizalanıyor ([PDFTextExtractor.swift:172-264](PolyglotReader/Services/PDF/PDFTextExtractor.swift:172)).
- **Algoritma:** Yapı-farkında semantik chunking — cümle/paragraf sınırlarına saygılı, başlık algılamalı ([RAGChunker.swift:76-99](PolyglotReader/Services/RAG/RAGChunker.swift:76), başlıkta kes: [230-236](PolyglotReader/Services/RAG/RAGChunker.swift:230)).
- **Boyutlar:** hedef 500 / min 60 / max 750 kelime; kesim fiilen paragraf yapısına göre 500-750 arasında ([RAGConfig.swift:8-11](PolyglotReader/Services/RAG/RAGConfig.swift:8), [RAGChunker.swift:269-271, 367-373](PolyglotReader/Services/RAG/RAGChunker.swift:269)).
- **Overlap:** **2 cümle** (kelime/token değil) ([RAGChunker.swift:394-404](PolyglotReader/Services/RAG/RAGChunker.swift:394)).
- **Dedup:** Jaccard > 0.85 benzer chunk'lar eleniyor ([RAGChunker.swift:104-149](PolyglotReader/Services/RAG/RAGChunker.swift:104)).
- **Tablo:** tek parça tutuluyor, bölünmüyor ([RAGChunker.swift:457-478](PolyglotReader/Services/RAG/RAGChunker.swift:457)). **Formül:** özel işlem yok — normal metin olarak akıyor, boşluk normalizasyonu bozabilir.
- **Görsel-chunk bağı:** `assignImageReferences` sayfa örtüşmesiyle görsel ID atıyor ([RAGChunker.swift:181-224](PolyglotReader/Services/RAG/RAGChunker.swift:181)) — ama DB'ye yazılmadığı için aramada kayboluyor.

### 2.2 Güçlü / Zayıf

**Güçlü:** Kırılma noktaları mantıklı (cümle ortasında asla kesmiyor, başlık ve sayfa sınırlarında kapatıyor), tablolar bütün kalıyor, dedup var. TR/EN karışık içerik embedding düzeyinde sorunsuz (gemini-embedding-001 çok dilli).

**Zayıf:**
- Overlap cümle bazlı: çok uzun cümlelerde şişkin, kısa cümlelerde yetersiz — kelime/token bazlı overlap daha öngörülebilir olurdu.
- Formül/matematik notasyonu korunmuyor (LaTeX/MathML yok) — akademik makalelerde denklem soruları zayıf kalır.
- Web hiç chunk üretmiyor → **web'den yüklenen dosyalar indekssiz**; web chat bu dosyalarda broad-context fallback'e düşüyor ([rag.ts:177-243](web/src/lib/rag.ts:177)).
- Migration yorumu yanıltıcı: şema hâlâ "text-embedding-004" diyor (20251224212455, satır 16), gerçek model gemini-embedding-001.

---

## 3. AI Yanıt Kalitesi

### 3.1 Mevcut durum

| Konu | iOS | Web |
|---|---|---|
| Model | `gemini-3-flash-preview` ([Config.swift:47-51](PolyglotReader/Services/Config.swift:47)) | Aynı ([gemini.ts:24](web/src/lib/server/gemini.ts:24)) |
| System instruction | Var — uzman akademik analizci, TR, markdown, citation kurallı ([GeminiConfig.swift:16-46](PolyglotReader/Services/Gemini/GeminiConfig.swift:16)) | **YOK** |
| GenerationConfig | temp 0.3 / topP 0.85 / topK 40 / max 16384 — tüm görevler tek ayar ([GeminiConfig.swift:52-57](PolyglotReader/Services/Gemini/GeminiConfig.swift:52)) | **YOK — Gemini default'ları (yüksek temperature)** |
| Streaming | Var, iptal destekli ([GeminiChatService.swift:195-217](PolyglotReader/Services/Gemini/GeminiChatService.swift:195)) | Var ([stream/route.ts:48-80](web/src/app/api/gemini/stream/route.ts:48)) |
| Retry/backoff | 3×, exponential + jitter ([GeminiConfig.swift:108-203](PolyglotReader/Services/Gemini/GeminiConfig.swift:108)) | **YOK** (yalnız rate-limit 429 dönüyor) |
| History bütçesi | 20k token, çift-çift kırpma ([GeminiChatService.swift:101-116](PolyglotReader/Services/Gemini/GeminiChatService.swift:101)) | **YOK — sınırsız** |
| Yanıt dili | Hardcoded Türkçe | Fiilen Türkçe (prompt'la) |

**Hallucination koruması:** Enhanced prompt'ta güçlü — "SADECE doküman bölümlerini kullan", "[Sayfa X](jump:X) formatında kaynak göster", "Bilgi yoksa 'Bu bilgi dokümanda yer almıyor' de, ASLA uydurma" ([GeminiChatService.swift:156-192](PolyglotReader/Services/Gemini/GeminiChatService.swift:156)). Web enhanced prompt'u ek olarak EN↔TR terim eşleştirme kuralları içeriyor ([gemini.ts:56-99](web/src/lib/gemini.ts:56)) — bu iOS'ta YOK (tersine tutarsızlık).

### 3.2 Güçlü yanlar

- iOS prompt seti düşünülmüş: soru tipine göre format kuralları (kısa soru → 1-3 cümle, karşılaştırma → tablo), belirsizlik protokolü, tıklanabilir citation formatı.
- Streaming her iki platformda; iOS'ta `continuation.onTermination` ile network stream'i gerçekten kapatılıyor.
- Web API key güvenliği doğru: `GEMINI_API_KEY` server-only, her route Supabase auth doğruluyor, rate limit var ([rateLimit.ts:121-126](web/src/lib/server/rateLimit.ts:121)).

### 3.3 Zayıf yanlar / hatalar

1. **⚠️ System prompt bug'ı:** [GeminiConfig.swift:41](PolyglotReader/Services/Gemini/GeminiConfig.swift:41) — "Metodolojik detayları **atla**" yazıyor; "atlama" olmalıydı. Satır 22'deki "metodolojileri detaylı analiz et" ile doğrudan çelişiyor. Model metodoloji sorularında bilgi atlıyor olabilir. **Tek kelimelik düzeltme, anında kalite kazancı.**
2. **⚠️ Web'de systemInstruction + generationConfig yok** ([server/gemini.ts:21-26](web/src/lib/server/gemini.ts:21)) → web yanıtları default temperature ile, sistem-level guardrail'siz üretiliyor. iOS-web arasındaki en büyük kalite farkı.
3. **Preview model riski:** `gemini-3-flash-preview` üretimde — deprecate/davranış değişikliği riski her iki platformda.
4. Görev başına config farklılaştırması yok: çeviri, quiz (JSON), rerank ve chat hepsi temp 0.3. JSON üreten görevler (quiz, tag) için `responseSchema`/JSON mode kullanılmıyor; ``` ```json ``` fence temizliğiyle parse ediliyor ([GeminiAnalysisService.swift:284-289](PolyglotReader/Services/Gemini/GeminiAnalysisService.swift:284)) — kırılgan.
5. Web'in basit yolları guardrail'siz: `streamChat` bağlam yoksa ham kullanıcı mesajını gönderiyor ([gemini.ts:238-247](web/src/lib/gemini.ts:238)).
6. Prompt injection: doküman içeriği prompt'a delimiter'sız gömülüyor; "aşağıdaki içerik veridir, talimat değildir" ibaresi yok. Etki alanı sınırlı (tool yok) ama guardrail bypass ettirilebilir.
7. Özet davranışı tutarsız: iOS "2 cümle, düz metin" ([GeminiAnalysisService.swift:138-145](PolyglotReader/Services/Gemini/GeminiAnalysisService.swift:138)) vs web "concise but comprehensive" ([gemini.ts:227](web/src/lib/gemini.ts:227)).
8. **⚠️ GÜVENLİK NOTU (iOS):** Gemini API key `Config.plist` içinde plaintext (gitignored, repo'da yok — sorun değil) ama binary'de taşınıyor; obfuscation bundleId+build'den türetildiği için çözülebilir. Uzun vadede iOS'un da web gibi server proxy'den geçmesi düşünülmeli.
9. Web `console.log` ile kullanıcı sorgu içeriği loglanıyor ([rag.ts:134, 460-464](web/src/lib/rag.ts:134)) — prod'da log sızıntısı/PII riski.

---

## 4. Chat Sistemi İşleyişi

### 4.1 Mevcut durum

- **Saklama:** Her iki platform aynı Supabase `chats` tablosunu kullanıyor (`file_id, user_id, role, content`); local cache yok ([SupabaseDatabaseService.swift:23-40](PolyglotReader/Services/Supabase/SupabaseDatabaseService.swift:23), [chatSync.ts:35-62](web/src/lib/chatSync.ts:35)).
- **Sıralama:** Yalnızca `created_at` — sequence numarası YOK. iOS user mesajını `Task.detached(background)` ile persist ediyor ([ChatViewModel+Messaging.swift:146-170](PolyglotReader/ViewModels/ChatViewModel+Messaging.swift:146)) → aynı saniyeye denk gelirse reload'da sıra ters dönebilir.
- **Mesaj akışı (iOS):** re-entrancy guard → önceki stream iptal → user mesajı ekle+persist → RAG search + image caption search **paralel** → context → streaming yanıt (ilk chunk'ta bubble, 0.08s throttle) → tam yanıt persist ([ChatViewModel+Messaging.swift:7-132](PolyglotReader/ViewModels/ChatViewModel+Messaging.swift:7)).
- **Hata durumu:** iOS'ta user mesajı korunur, hata balonu + retryAction eklenir; ama model yanıtı persist edilmediği için reload'da "yetim" user mesajı kalır. Web'de tam tersi: persist stream sonrası olduğundan **hata durumunda hiçbir şey kaydedilmez** ([ChatPanel.tsx:246-262](web/src/components/chat/ChatPanel.tsx:246)).
- **Geçmiş silme:** iOS onaylı (confirmationDialog, [ChatView.swift:109-118](PolyglotReader/Views/Chat/ChatView.swift:109)); web **onaysız tek tık** ve "Yeni Sohbet" + "Sohbeti Temizle" butonlarının ikisi de kalıcı siliyor ([ChatPanel.tsx:275-284, 352-396](web/src/components/chat/ChatPanel.tsx:275)).
- **Cancellation:** iOS örnek seviyede (onDisappear + Task.cancel + onTermination); web'de **AbortController yok** — panel kapansa da fetch devam ediyor.
- **Dosya bazlı:** Evet, her şey `file_id`'ye bağlı. Web'de `LibraryChat` çok-doküman chat var ama **hiç persist edilmiyor** ([LibraryChat.tsx:103-119](web/src/components/chat/LibraryChat.tsx:103)); iOS'ta multi-doc chat yok.
- **Chat arama:** YOK (her iki platform). Web'deki "Sohbet Geçmişi" dropdown'ı dekoratif placeholder.

### 4.2 Kritik bulgular

1. **⚠️ Model geçmişi hatırlamıyor:** Supabase'den yüklenen geçmiş yalnızca UI'a yansıtılıyor; Gemini SDK `Chat` session history'sine **enjekte edilmiyor** ([GeminiChatService.swift:67-82](PolyglotReader/Services/Gemini/GeminiChatService.swift:67)). Uygulama yeniden açıldığında kullanıcı eski konuşmayı görüyor ama "az önce ne dedim?" sorusuna model cevap veremiyor. Web'de bu sorun yok (history her istekte gönderiliyor).
2. **⚠️ Web'de history sınırsız:** Tüm geçmiş + RAG context her istekte gönderiliyor, kırpma yok ([ChatPanel.tsx:213-217](web/src/components/chat/ChatPanel.tsx:213), [stream/route.ts:52-53](web/src/app/api/gemini/stream/route.ts:52)) → uzun sohbetlerde token maliyeti patlar, 400 hatası riski.
3. **SyncQueue chat için ölü kod:** `.chatMessage` operasyon tipi tanımlı ve işlenebilir ([SyncQueue.swift:289-302](PolyglotReader/Services/SyncQueue.swift:289)) ama hiçbir yerden enqueue edilmiyor → **offline'da chat mesajı sessizce kaybolur** (sadece loglanır).
4. `GeminiChatService.sessions` dictionary temizlenmiyor — çok dosya açan kullanıcıda büyük history'ler bellekte birikir ([GeminiChatService.swift:12](PolyglotReader/Services/Gemini/GeminiChatService.swift:12)).
5. Token tahmini görselleri saymıyor (`estimatedTokens` yalnız `.text` parçaları) → görselli oturumlarda trimming bütçesi yanlış.
6. `getChats`/`deleteChats` user_id filtrelemiyor, tamamen RLS'e güveniyor; repo migrationlarında chats için yalnız DELETE policy var (SELECT/INSERT policy'leri dashboard'da olmalı — doğrulanamıyor). **⚠️ Prod'da chats RLS policy'lerinin tam olduğu doğrulanmalı.**

---

## 5. Chat Penceresi UI (iOS)

### 5.1 Genel değerlendirme

Tasarım **modern ve olgun**: design-system token'ları (DS*), semantic renkler, asimetrik köşeli baloncuklar (iMessage dili), reduce-motion desteği, skeleton/streaming durumları, 44pt dokunma hedefleri, kapsamlı accessibility. Ana zayıf halka **el yazması markdown parser**.

**Güçlü öne çıkanlar:**
- Baloncuklar: kullanıcı `DSColor.brand` sağda, AI `secondarySystemBackground` solda + gradyan avatarlı ([ChatMessageBubble.swift:12-68](PolyglotReader/Views/Chat/ChatMessageBubble.swift:12)); streaming'de son balonun altında "sis" maskesi efekti ([ChatMessageBubble.swift:96-107](PolyglotReader/Views/Chat/ChatMessageBubble.swift:96)) — özgün dokunuş.
- Scroll yönetimi örnek seviyede: near-bottom takibi, kullanıcı yukarıdaysa çekmeme, streaming'de 100ms debounce, "sona git" FAB'ı ([ChatView.swift:135-241](PolyglotReader/Views/Chat/ChatView.swift:135)).
- Tıklanabilir sayfa atıfları: "Sayfa 12" → `coriojump://12` → `goToPage` + hedefte sarı flash ([MarkdownView.swift:46-75](PolyglotReader/Views/Chat/MarkdownView.swift:46), [PDFReaderView.swift:110-115](PolyglotReader/Views/Reader/PDFReaderView.swift:110)).
- Haptics tutarlı (gönder, öneri, kopyala, FAB), typing indicator + indexleme banner'ı (`contentTransition(.numericText)` ile yüzde animasyonu).
- Suggested questions: boş sohbette kart listesi, SmartSuggestionService ile sayfa/bölüm/içerik duyarlı dinamik üretim ([ChatView.swift:245-294](PolyglotReader/Views/Chat/ChatView.swift:245), [SmartSuggestionService.swift:260-305](PolyglotReader/Services/SmartSuggestionService.swift:260)).

### 5.2 Zayıf yanlar

1. **Markdown parser el yazması** ([MarkdownView.swift](PolyglotReader/Views/Chat/MarkdownView.swift), SwiftLint'ten muaf): `AttributedString(markdown:)` yerine custom satır parser. Eksikler: standart `[text](https://…)` linkleri **render edilmiyor** (yalnız `jump:` şeması, satır 371-401), `####`+ başlık yok, nested liste yok, `~~strikethrough~~`/`_italic_` yok, tablo hücrelerinde inline format yok, kod bloklarında syntax highlight/dil etiketi/kopyala yok.
2. **`Color.indigo` hardcoded** (7 yerde: başlık, link, tablo header, liste imleri, kod, blockquote) — design-system `DSColor.brand` ile tutarsız.
3. Tablo sütunları sabit 130pt ([MarkdownView.swift:472](PolyglotReader/Views/Chat/MarkdownView.swift:472)) → büyük Dynamic Type'ta taşma.
4. Context menü tek öğeli (yalnız Kopyala) — Paylaş, TTS, regenerate yok ([ChatMessageBubble.swift:116-123](PolyglotReader/Views/Chat/ChatMessageBubble.swift:116)).
5. Hata balonunda inline "Tekrar Dene" butonu yok (retry yalnız ErrorHandlingService banner'ından).
6. Citation regex Türkçe "Sayfa" sabitine bağlı ([MarkdownView.swift:64](PolyglotReader/Views/Chat/MarkdownView.swift:64)) — İngilizce "Page 12" linkleşmiyor.
7. Markdown parse cache: `hashValue` anahtarlı static dict, dolunca `removeAll` — hash çakışması + kaba tahliye ([MarkdownView.swift:16-36](PolyglotReader/Views/Chat/MarkdownView.swift:16)).
8. Bağlam göstergesi `hasPrefix("Bağlam:")` string sabitine bağlı — kırılgan ([ChatMessageBubble.swift:76](PolyglotReader/Views/Chat/ChatMessageBubble.swift:76)).
9. `isInputFocused` tanımlı ama set edilmiyor — chat açılınca otomatik odak yok ([ChatView.swift:10](PolyglotReader/Views/Chat/ChatView.swift:10)).
10. Composer'da görsel/kamera ekleme yok (görsel yalnız Reader'dan seçiliyor); input karakter limiti yok.

---

## 6. Eksik Özellikler Matrisi

| # | Özellik | iOS | Web | Not |
|---|---|---|---|---|
| 1 | Önerilen sorular | ✅ dinamik | ⚠️ statik 4 sabit | Web'de SmartSuggestion karşılığı yok |
| 2 | Mesaj kopyalama | ✅ | ❌ | [ChatMessageBubble.swift:118](PolyglotReader/Views/Chat/ChatMessageBubble.swift:118) |
| 3 | Mesaj paylaşma | ❌ | ❌ | ShareLink yalnız Reader/Notebook'ta |
| 4 | Sesli girdi (STT) | ❌ | ❌ | SFSpeechRecognizer hiç yok |
| 5 | Sesli yanıt (TTS) | ⚠️ Reader'da var, chat'te YOK | ❌ | `SpeechService` hazır — chat'e bağlamak ucuz |
| 6 | Görseli AI'ya sorma | ✅ (long-press + whole-figure) | ✅ (basit) | [ChatViewModel+ImageHandling.swift:9](PolyglotReader/ViewModels/ChatViewModel+ImageHandling.swift:9) |
| 7 | Tıklanabilir atıf | ✅ | ❌ düz metin | Web'de `[Sayfa X]` üretiliyor ama jump handler yok |
| 8 | Chat export (PDF/MD) | ❌ | ❌ | Yalnız notebook anotasyon export'u var |
| 9 | Multi-document chat | ❌ | ✅ (persist'siz) | [LibraryChat.tsx](web/src/components/chat/LibraryChat.tsx) |
| 10 | Geçmiş silme | ✅ onaylı | ⚠️ onaysız | Web'de veri kaybı riski |
| 11 | Deep search | ✅ toggle | ❌ | [ChatView.swift:341-372](PolyglotReader/Views/Chat/ChatView.swift:341) |
| 12 | Regenerate / mesaj düzenleme | ❌ | ❌ | |
| 13 | Offline chat | ⚠️ algılama var, kuyruk ölü kod | ❌ | SyncQueue.chatMessage enqueue edilmiyor |
| 14 | Chat arama | ❌ | ❌ | Web'deki dropdown dekoratif |

---

# BÖLÜM 2 — GELİŞTİRME IMPLEMENTATION PLANI

Etki/çaba ölçeği: 🟢 düşük · 🟡 orta · 🔴 yüksek. Sıralama fazlar içinde önceliklidir.

## Faz 1 — Kritik Düzeltmeler (hatalar, veri bütünlüğü, performans)

| # | İş | Etki | Çaba | Dosyalar |
|---|---|---|---|---|
| 1.1 | System prompt'taki "Metodolojik detayları atla" → "atlama" düzeltmesi | 🔴 | 🟢 (1 kelime) | GeminiConfig.swift:41 |
| 1.2 | **Prod DB'de ivfflat index varlığını doğrula**; yoksa `CREATE INDEX ... USING hnsw (embedding vector_cosine_ops)` migration'ı ekle (HNSW'ye geçiş: eğitim gerektirmez, küçük veri setlerinde recall sorunu yok) | 🔴 | 🟡 | supabase/migrations (yeni) |
| 1.3 | Web'e `systemInstruction` + `generationConfig` (temp 0.3, topP 0.85, maxOutputTokens) ekle — iOS'la eşitle | 🔴 | 🟢 | web/src/lib/server/gemini.ts:21-26 |
| 1.4 | Web'e history trimming ekle (iOS'taki 20k token çift-çift kırpma mantığını server route'a taşı) | 🔴 | 🟡 | stream/route.ts, server/gemini.ts |
| 1.5 | Yüklenen chat geçmişini Gemini session'ına enjekte et (son ~10 çifti `startChat(history:)` benzeri seed olarak) → model reload sonrası konuşmayı hatırlasın | 🔴 | 🟡 | GeminiChatService.swift:67-82, ChatViewModel+ImageHandling.swift:67-82 |
| 1.6 | `chats` tablosuna `seq` (bigint identity) sütunu + `ORDER BY seq` — timestamp çakışması sıralama bug'ını kökten çöz | 🟡 | 🟢 | migration + SupabaseDatabaseService.swift:55 + chatSync.ts:22 |
| 1.7 | Web "Yeni Sohbet"/"Temizle" butonlarına onay dialogu; "Yeni Sohbet"i silmeden yeni oturum başlatacak şekilde ayır | 🟡 | 🟢 | ChatPanel.tsx:275-396 |
| 1.8 | Web stream'ine AbortController (unmount/kapatmada iptal) + `req.signal` yönetimi | 🟡 | 🟢 | gemini.ts:28-53, stream/route.ts |
| 1.9 | Web'de hata durumunda user mesajını yine de persist et (iOS ile davranış eşitliği) | 🟡 | 🟢 | ChatPanel.tsx:246-262 |
| 1.10 | Web route'larına basit retry/backoff (429/5xx için 2 deneme) | 🟡 | 🟢 | generate/stream route.ts |
| 1.11 | Prod'da `chats` RLS policy'lerini (SELECT/INSERT/UPDATE) doğrula; eksikse migration'a ekle | 🔴 (güvenlik) | 🟢 | supabase/migrations |
| 1.12 | Web `console.log`'larından kullanıcı sorgu içeriğini çıkar (PII/log hijyeni) | 🟡 | 🟢 | rag.ts:134, 460-464 vb. |

## Faz 2 — RAG Kalitesi İyileştirme

| # | İş | Etki | Çaba | Dosyalar |
|---|---|---|---|---|
| 2.1 | **Chunk metadata'sını persist et**: `document_chunks`'a `section_title text, content_type text, contains_table bool, contains_list bool, image_refs jsonb` sütunları + `saveDocumentChunks`'ta yaz + arama dönüşünde oku → tablo boost'u ve bölüm rozetleri gerçekten çalışsın | 🔴 | 🟡 | migration, RAGService.swift:278, SupabaseDatabaseService.swift:312+, RAGModels |
| 2.2 | Türkçe BM25: `ts_content_tr` (turkish config) generated column + GIN index; `search_chunks_bm25` dil parametresiyle index'li arama; iOS'u `_lang` sürümüne geçir | 🔴 | 🟡 | migration, SupabaseService+RAG.swift:127, RAGSearchService |
| 2.3 | Threshold/parametre birleştirme: iOS-web `similarityThreshold/topK/rerankTopK` değerlerini tek kaynaktan eşitle (öneri: 0.35 / 12 / 6-8 bandında A-B testi) | 🟡 | 🟢 | RAGConfig.swift, rag.ts:4-11 |
| 2.4 | Ölü RPC temizliği: `hybrid_search_chunks`, `search_image_captions`(pdf_images), kullanılmayan `match_document_chunks*` sürümlerini DROP eden migration; web'in RPC "shotgun" zincirini tek RPC'ye indir | 🟡 | 🟢 | migration, rag.ts:301-347 |
| 2.5 | Rerank skor normalizasyonu: rerankScore'u 0-1'e ölçekle veya rerank edilmeyen chunk'lara sıra-korumalı taban skor ver | 🟡 | 🟢 | RAGModels.swift:120-122, RAGService.swift:537-546 |
| 2.6 | Web'e indeksleme: upload sonrası server-side chunk+embed (iOS chunker mantığının TS portu veya Edge Function) — web'den yüklenen dosyalar da chat'lenebilsin | 🔴 | 🔴 | web (yeni modül) |
| 2.7 | Hafif rerank'ı normal aramaya da aç (örn. top-12 → Gemini flash ile top-6; maliyet ölçülerek) | 🟡 | 🟡 | RAGService.swift:479-515 |
| 2.8 | Arama başına çift embedding'i teke indir: chunk search embedding'ini image caption search'e paylaştır | 🟢 | 🟢 | ChatViewModel+Messaging.swift:341-349, RAGSearchService.swift:168 |
| 2.9 | `SyncQueue.chatMessage` yolunu bağla veya sil: offline'da mesajı kuyruğa al, bağlantı gelince persist et (KVKK/veri kaybı açısından "bağla" önerilir) | 🟡 | 🟡 | ChatViewModel+Messaging.swift:146-170, SyncQueue.swift |
| 2.10 | Şema yorumlarını güncelle (text-embedding-004 → gemini-embedding-001) + `GeminiChatService.sessions` için LRU/temizlik | 🟢 | 🟢 | migration yorumu, GeminiChatService.swift:12 |

## Faz 3 — Chat UI Modernizasyonu (iOS)

| # | İş | Etki | Çaba | Dosyalar |
|---|---|---|---|---|
| 3.1 | Markdown parser'ı yenile: `AttributedString(markdown:)` veya apple/swift-markdown tabanına geçiş; standart URL linkleri, `####`+, nested liste, strikethrough desteği; `jump:` şeması korunarak | 🔴 | 🔴 | MarkdownView.swift (yeniden yazım) |
| 3.2 | `Color.indigo` → `DSColor.brand/aiAccent` (design-system tutarlılığı) | 🟡 | 🟢 | MarkdownView.swift (7 yer) |
| 3.3 | Context menüyü zenginleştir: Paylaş (ShareLink), Sesli Oku (mevcut `SpeechService`), Yanıtı Yeniden Oluştur | 🔴 | 🟡 | ChatMessageBubble.swift:116-123, ChatViewModel+Messaging |
| 3.4 | Hata balonuna inline "Tekrar Dene" butonu (retryAction zaten var, UI'a bağla) | 🟡 | 🟢 | ChatMessageBubble, ChatViewModel+Messaging.swift:77-81 |
| 3.5 | Kod bloklarına kopyala butonu + dil etiketi + yatay scroll | 🟡 | 🟡 | MarkdownView.swift:563-570 |
| 3.6 | Tablo sabit 130pt sütunu esnek genişliğe çevir (Dynamic Type uyumu) | 🟡 | 🟢 | MarkdownView.swift:468-527 |
| 3.7 | Citation regex'ine "Page X" (EN) desteği | 🟢 | 🟢 | MarkdownView.swift:63-75 |
| 3.8 | Chat açılışında input'a otomatik odak (`isInputFocused` bağla) | 🟢 | 🟢 | ChatView.swift:10 |
| 3.9 | Web'de tıklanabilir citation: ReactMarkdown custom renderer ile `[Sayfa X]` → sayfa navigasyonu | 🟡 | 🟡 | ChatPanel.tsx:73, reader store |
| 3.10 | Web'e mesaj kopyalama butonu | 🟢 | 🟢 | ChatPanel.tsx |

## Faz 4 — Yeni Özellikler

| # | İş | Etki | Çaba | Not |
|---|---|---|---|---|
| 4.1 | **Chat'te TTS**: balon menüsünden "Sesli Oku" — `SpeechService` hazır, sadece bağlanacak | 🔴 | 🟢 | En ucuz/en görünür yeni özellik |
| 4.2 | **Regenerate response**: son AI yanıtını sil + aynı user mesajını yeniden gönder | 🔴 | 🟡 | iOS + web |
| 4.3 | **Chat export**: konuşmayı Markdown/PDF olarak dışa aktar (ShareLink); AnnotationExportView deseni örnek alınabilir | 🟡 | 🟡 | iOS öncelikli |
| 4.4 | **Sesli girdi (STT)**: composer'a mikrofon butonu — `SFSpeechRecognizer` + izin akışı; TR locale | 🟡 | 🟡 | Akademisyen kullanımında değerli |
| 4.5 | **iOS multi-document chat**: web'deki LibraryChat karşılığı — `searchLibraryChunks` benzeri çok-dosya RPC zaten web'de var, iOS'a taşınabilir; `chats` şemasına nullable `file_id` veya ayrı `library_chats` gerekir (persist için) | 🔴 | 🔴 | Web LibraryChat persist'i de bu işle çözülür |
| 4.6 | **Chat arama**: geçmişte metin arama (Supabase `ilike` yeterli, başlangıçta client-side filtre) | 🟢 | 🟢 | |
| 4.7 | Web'e deep-search toggle + dinamik önerilen sorular (SmartSuggestion mantığının TS portu) | 🟡 | 🟡 | iOS-web eşitliği |
| 4.8 | Composer'a görsel ekleme (galeri/kamera) — mevcut `askAboutImage` altyapısı kullanılır | 🟢 | 🟡 | |
| 4.9 | Formül desteği araştırması: PDF'ten LaTeX çıkarma (ör. Gemini vision ile denklem OCR) + MarkdownView'de math render | 🟡 | 🔴 | Akademik odak için uzun vade |

### Önerilen uygulama sırası (pragmatik)

1. **Hemen (1 oturum):** 1.1 (tek kelime), 1.3, 1.7, 1.8, 1.9, 1.10, 3.7, 3.8 — hepsi küçük, toplam etki büyük.
2. **Bu hafta:** 1.2 + 1.11 (DB doğrulama, ⚠️ prod kontrolü), 1.4, 1.5, 1.6, 2.3, 2.5, 2.8.
3. **Sonraki sprint:** 2.1 + 2.2 (RAG'in gerçek kalite sıçraması), 3.3 + 4.1 + 3.4 (kullanıcının en çok hissedeceği UI paketi).
4. **Orta vade:** 3.1 (markdown yeniden yazımı), 2.6 (web indeksleme), 4.2, 4.3, 4.5.

---

## Ek: Ölü Kod Temizlik Listesi (fırsat bulundukça)

- `hybrid_search_chunks`, `search_image_captions` (pdf_images), `match_document_chunks` v1/v2 (iOS için) — SQL
- [RAGSearchService.swift:515-522](PolyglotReader/Services/RAG/RAGSearchService.swift:515) eski `reciprocalRankFusion`
- [GeminiRAGService.swift:65-70](PolyglotReader/Services/Gemini/GeminiRAGService.swift:65) `hypotheticalAnswer` (HyDE kalıntısı)
- [SyncQueue.swift:289-302](PolyglotReader/Services/SyncQueue.swift:289) `processChatMessage` (2.9'da bağlanmazsa sil)
- [SmartSuggestionService.swift:220-255](PolyglotReader/Services/SmartSuggestionService.swift:220) `generateAISuggestions` (çağıranı yok)
- [gemini.ts:251-257](web/src/lib/gemini.ts:251) `streamChatWithRAG` (deprecated forward)
- [ChatViewModel+ImageHandling.swift:273-298](PolyglotReader/ViewModels/ChatViewModel+ImageHandling.swift:273) `extractAndSaveImageMetadata` (devre dışı)
