# GELİŞTİRME PLANI — Corio Docs / PolyglotReader

**Tarih:** 13 Haziran 2026
**Bakış açısı:** "Bu uygulamayı büyük bir şirketin ürünü gibi en iyi seviyeye nasıl çıkarırız?"
**Kapsam:** Web (Next.js) UI/UX, özellik analizi, kod mimarisi, performans + iOS karşılaştırması
**Yöntem:** 4 paralel derinlemesine kod denetimi (UI/UX, özellik/rakip, mimari, performans) — tümü dosya:satır referanslı
**Not:** Bu rapor önceki güvenlik/RLS/middleware/upload/Zustand düzeltmelerinin **tamamlandığını doğrulayarak** yazıldı. `PROJE_RAPORU.md`'deki P0 güvenlik bulguları artık geçmişte kaldı; bu plan bir sonraki seviyeye — "ürün kalitesi"ne — odaklanır.

---

## 0. Klinik Handoff (TLDR)

**Ne durumdayız:** Sağlam mühendislik temeli olan, vizyonu net ama "yarım kalmış cila" yüzünden henüz büyük şirket ürünü *hissi* vermeyen bir uygulama. Çekirdek (RAG sohbet, çeviri popup, anotasyon, PDF render) çalışıyor ve kalitesi ChatPDF/Humata seviyesinin üstünde. Ama üç yapısal sorun ürünü aşağı çekiyor ve akademik niş için kritik özellikler eksik.

**En kritik üç bulgu (hepsi düşük efor, yüksek etki):**
1. **3 paralel renk paleti çakışıyor** → shadcn `--primary` gri-siyah olduğu için sade `<Button>`'lar terracotta değil **siyah** render ediliyor. (1 satırlık düzeltme)
2. **Kütüphane sayfası dark/sepia modda kırılı** → hex renkler hardcode edilmiş, tema değişince krem zemin + beyaz kartlar kalıyor. En çok kullanılan ekran bu.
3. **Cilalı kod ölü bekliyor, kötü versiyon yayında** → Lucide ikonlu + terracotta `ReaderToolbar.tsx` hiç import edilmemiş; bunun yerine emoji ikonlu (🌐✨⛶🖍️) + indigo `PDFToolbar.tsx` shipliyor.

**Akademik niş için en büyük eksik:** Atıf/kaynakça çıkarma (BibTeX/RIS), kütüphane-geneli sohbet, doküman içi arama (web). Bunlar olmadan ürün "PDF chat oyuncağı" kategorisinde; SciSpace/Zotero/Readwise ligine çıkmıyor.

**Genel hazırlık puanı: 6.0/10** — büyük şirket ürünü olmaya ~3-4 haftalık odaklı çalışma uzaklıkta.

---

## 1. Kategori Karnesi (10 üzerinden)

| Kategori | Puan | Tek cümlede |
|---|---|---|
| **Tasarım vizyonu** | 9/10 | "Corio Design Language" spec'i (krem + terracotta, Inter/Literata/JetBrains Mono) gerçekten birinci sınıf |
| **UI/UX uygulaması** | 6.5/10 | Landing/login/notebook/settings mükemmel; kütüphane + reader chrome'u yarım cila |
| **Özellik tamlığı (akademik niş)** | 5/10 | Tek-doküman okuyucu olarak iyi; akademik katman (atıf, kütüphane sohbeti) tamamen yok |
| **Kod mimarisi** | 7/10 | Temiz katmanlama, Zustand tamamlanmış, güvenli API sınırı; operasyonel boşluklar var |
| **Performans** | 5.5/10 | Sağlam temel ama 2 ciddi ölçeklenme uçurumu (sanal render yok, thumbnail tam-PDF indiriyor) |
| **Erişilebilirlik (a11y)** | 4/10 | aria-label neredeyse yok, focus ring'ler eksik, emoji butonlar ekran okuyucuya literal okunuyor |
| **Test** | 4/10 | 3 trivial test dosyası; RAG/auth/reader kritik yolları test edilmemiş |
| **iOS↔Web paritesi** | 6/10 | Web'de quiz yok, PDF içi arama yok; iki platform tek hikaye anlatmıyor |
| **GENEL** | **6.0/10** | Sağlam temel + net vizyon; ürünleşme işi var |

> Karşılaştırma: `PROJE_RAPORU.md` (12 Haz) genel 6.5/10 vermişti ama o güvenlik açıklarını da sayıyordu. Güvenlik çözülünce ürün-kalitesi merceği biraz daha sert: cila ve özellik eksikleri öne çıkıyor.

---

## 2. UI/UX — Sayfa Sayfa Değerlendirme

### Sayfa puanları

| Sayfa / Alan | Puan | Loading | Empty | Error | Animasyon | Responsive |
|---|---|---|---|---|---|---|
| Landing | 9/10 | — | — | inline | hover/scroll/fadeUp | mükemmel |
| Login | 8/10 | spinner | — | inline kırmızı kutu | Framer giriş | iyi |
| Auth callback | 6/10 | spinner | — | **ham İngilizce hata** | yok | orta |
| **Kütüphane** | 5/10 | skeleton ✓ | tasarlı ✓ | tasarlı ✓ | sadece kart hover | **dark modda kırık** |
| Reader | 6.5/10 | spinner+skeleton | — | tasarlı ✓ | sayfa geçişi | mobilde zayıf |
| Çeviri popup | 8/10 | zıplayan nokta ✓ | — | inline ✓ | — | sürükle + viewport-aware |
| Seçim popup | 5/10 | spinner | — | inline | sürükle | emoji, light-only |
| Chat paneli | 7/10 | yazıyor noktaları ✓ | tasarlı ✓ | inline | yok | mobile değil |
| Notebook | 8.5/10 | skeleton ✓ | tasarlı ✓ | tasarlı ✓ | kart hover | iyi |
| Ayarlar | 8/10 | mount guard | — | toast ✓ | hover | iyi |
| Sidebar/MobileNav | 7/10 | — | — | — | layoutId ✓ | iyi |
| Komut paleti (⌘K) | 7/10 | — | "Sonuç yok" | — | dialog | — |

### En çok kullanılanlar genuinely iyi (dokunma)
- **Landing** — uyumlu terracotta, dekoratif orblar, scroll-aware header → büyük şirket kalitesi.
- **QuickTranslationPopup** ("killer feature") — frosted glass, seçime rAF ile yapışma, sürükle, debounce + race-guard. İyi yürütülmüş.
- **Notebook & Ayarlar** — temiz iOS-tarzı gruplu kartlar, doğru token kullanımı, tam loading/empty/error.

### UI/UX bulgu tablosu (önceliklendirilmiş)

| # | Sorun | Dosya:satır | Öncelik | Çözüm | Efor |
|---|---|---|---|---|---|
| U1 | shadcn default `<Button>` siyah render ediliyor (`--primary` grayscale, sadece sepia'da terracotta) | `globals.css:93`; `ui/button.tsx:13` | **P1** | `:root` + `.dark`'ta `--primary`'yi terracotta yap | **S** |
| U2 | Kütüphane hex renkleri hardcode → dark/sepia tamamen kırık | `library/page.tsx:91,97,105`; `PDFCard.tsx:60-101`; `EmptyLibrary.tsx`; `UploadArea.tsx:57-78` | **P1** | Inline hex → `corio-*` token/Tailwind sınıfı | M |
| U3 | Cilalı `ReaderToolbar.tsx`/`PageNavigation.tsx` ölü kod; yerine emoji+indigo `PDFToolbar.tsx` shipliyor | `reader/PDFToolbar.tsx:111-230`; `ReaderToolbar.tsx` (0 import) | **P1** | `ReaderToolbar`'ı bağla, `PDFToolbar`'ı sil | M |
| U4 | Eski `--bg-*`/`--text-*`/`--border-color` token'larının dark/sepia karşılığı yok → 4 bileşen dark modda light kalıyor | `globals.css:75-81` (no `.dark`/`.sepia`); PDFToolbar, SelectionPopup, ImageSelectionPopup, ChatPanel.module.css | **P1** | Eski token'lara dark/sepia override ekle veya bileşenleri `corio-*`'a taşı | M |
| U5 | JetBrains Mono yükleniyor ama hiçbir yerde uygulanmıyor (chat kod blokları default mono) | `globals.css:419`; `ChatPanel.module.css:500-510` | P2 | Chat markdown `code/pre`'ye `font-mono` uygula | S |
| U6 | ChatPanel çekirdek renkleri eski indigo (logo gradient, gönder butonu, öneri chip'leri) | `ChatPanel.module.css:103,314-327,378` | P2 | `corio-accent`'e re-token | M |
| U7 | Seçim & görsel-seçim popup'ları emoji+indigo+light-only | `SelectionPopup.tsx:208-240`; `ImageSelectionPopup.tsx:139-151` | P2 | Lucide ikon + corio token (QuickTranslationPopup kalitesine getir) | M |
| U8 | Kalıcı seçim highlight'ı indigo, palet dışı | `PDFViewer.tsx:175` (`rgba(99,102,241,0.3)`) | P2 | corio-accent + alpha | S |
| U9 | Reader PDF kanvas zemini sabit koyu gri, tema/sepia'yı yok sayıyor | `PDFViewer.tsx:304` (`--color-gray-800`) | P2 | `--corio-reader-bg` kullan | S |
| U10 | `useKeyboardShortcuts` hook'u hiç kullanılmıyor; reader'da ←/→, ⌘\, ⌘T, ⌘F kısayolları yok | `hooks/useKeyboardShortcuts.ts` (0 import); `reader/[id]/page.tsx:318-329` | P2 | Ok tuşu navigasyonu + spec kısayollarını bağla | M |
| U11 | CommandPalette ⌘1/⌘2/⌘3 ipucu gösteriyor ama o kısayollar yok (yanıltıcı) | `layout/CommandPalette.tsx:71,76,81` | P2 | Kısayolları uygula veya etiketi kaldır | S |
| U12 | Icon-only butonlarda aria-label yok (ekran okuyucu emojiyi literal okuyor); hand-rolled input'larda `outline-none` + focus ring yok | `PDFToolbar.tsx:55-135`; `library/page.tsx:121`; landing CTA'lar | P2 | aria-label + focus-visible ring ekle | S |
| U13 | Ayarlar'daki "Kullanım Koşulları"/"Gizlilik Politikası" butonları ölü (onClick/href yok) | `settings/page.tsx:238-250` | P2 | `/legal/*` sayfalarına bağla (mevcutlar) | S |
| U14 | Auth callback kullanıcıya ham İngilizce hata gösteriyor (kural ihlali: Türkçe, ham yok) | `auth/callback/page.tsx:35` | P2 | Genel Türkçe mesaj | S |
| U15 | Apple Sign-In `alert()` ile (markasız, sert) | `page.tsx:53` | P3 | Toast/disabled state | S |
| U16 | Türkçe metinlerde eksik diakritik ("Notlarim", "Henuz", "secip", "Sari/Yesil") | `notes/page.tsx:131,174-177`; `NotebookFilters.tsx:15-17` | P3 | "Notlarım/Henüz/seçip/Sarı/Yeşil" düzelt | S |
| U17 | Landing istatistikleri uydurma görünüyor ("10K+ Aktif Kullanıcı", "4.8★ App Store") — beta için | `HeroSection.tsx:139-142` | P3 | Kaldır veya doğru yap | S |
| U18 | Mobil üst bar yok (spec: ☰ + başlık + avatar); sadece alt nav var; chat mobilde bottom-sheet değil | `AppShell.tsx`; `ChatPanel.tsx` | P3 | Mobil header + vaul bottom-sheet | M-L |

### Spec'e göre eksik UI parçaları
- Thumbnail kenar çubuğu (spec 4e) yok
- FloatingActionBar yok
- Klasör/etiket filtresi + sıralama (isim/tarih/boyut/son okunan) yok — `useLibraryStore` sortBy/folders/tags içermiyor

### Tipografi & tema durumu
- **Fontlar doğru wire'lı** (`layout.tsx:8-24`). Ama **Literata** sadece çeviri popup'ında (`QuickTranslationPopup.tsx:255`), **JetBrains Mono hiç** uygulanmıyor → 3 fonttan 2'si yüklü-ama-kullanılmıyor.
- Dark mode Corio token'larıyla tam; ama eski token'lar + hardcode hex'ler yüzünden kütüphane + reader chrome'u dark modda kırık (U2, U4).

---

## 3. Özellik Analizi — Rakip Karşılaştırması

**Strateji özeti:** Bugün ürün **ChatPDF/Humata** ile yarışıyor (tek-doküman sohbet) ve Türkçe UX + çeviri ile kazanıyor. Ama **SciSpace/Elicit/Zotero/Readwise** ile yarışmıyor — akademik iş akışını sahiplenen uygulamalar. O lige çıkmanın en ucuz yolu aşağıda.

### Mevcut özellik envanteri (öne çıkanlar)

| Özellik | iOS | Web | Kalite |
|---|---|---|---|
| Google OAuth | ✓ | ✓ | iyi |
| Apple Sign-In | ✓ | **stub (yok)** | web zayıf |
| PDF kütüphane (grid/list/arama/sıralama) | ✓ | ✓ | iyi |
| Klasör / Etiket | ✓ | kısmi | web'de UI yok |
| PDF upload | ✓ | ✓ (düzeltildi) | iyi |
| RAG sohbet + sayfa atıfı | ✓ | ✓ | iyi |
| Hibrit arama (vektör+BM25+RRF) | ✓ | ✓ | iyi |
| Diller-arası RAG (TR↔EN) | ✓ | ✓ | iyi |
| Çeviri popup | ✓ | ✓ | iyi (killer) |
| Görsel→AI vision | ✓ | ✓ | iyi |
| Anotasyon + Notebook | ✓ | ✓ | iyi |
| **Quiz** | ✓ | **YOK** | iOS ship, web tip-only |
| **PDF içi tam-metin arama** | ✓ | **YOK** | iOS ship, web yok |
| Tema (light/dark/sepia) | — | ✓ | dark/light iyi, sepia kaba |

### Eksik akademik özellikler (öncelik sırasıyla)

| # | Eksik özellik | Kim sahibi | Öncelik | Efor | Çözüm |
|---|---|---|---|---|---|
| M1 | **Atıf çıkarma & export (BibTeX/RIS)** | Zotero, SciSpace | **P0** | M | İlk sayfa DOI regex → Crossref API → BibTeX/RIS indirme. Eksik en büyük akademik farklılaştırıcı |
| M2 | **Kaynakça parse** ("atıf verilen makaleleri göster") | SciSpace, Scholarcy | **P0** | L | References bölümüne Gemini structured-output → DOI'li linkli liste. M1 ile eşleşir |
| M3 | **Kütüphane-geneli sohbet & arama** | Elicit, Humata, NotebookLM | **P0** | L | `document_chunks` zaten per-file embedding'li; `hybrid_search_chunks`'ta `file_id` filtresini `IN (...)`'e gevşet. Backend ~%80 hazır |
| M4 | **Doküman anahattı / TOC navigasyonu** | Acrobat, Preview, Readwise | **P1** | S(iOS)/M(web) | iOS: PDFKit `outlineRoot` bedava (şu an 0 kullanım); web: pdfjs `getOutline()`. Düşük efor, yüksek günlük değer |
| M5 | **Highlight/anotasyon export (Markdown/CSV/PDF)** | Readwise, Zotero | **P1** | S | Notebook verisi hazır; export butonu ekle. Ucuz, her ciddi okuyucunun beklediği |
| M6 | **Yan-yana / çift-panel çeviri görünümü** | DeepL, Google | **P1** | M | Bugün sadece seçim-popup çeviri var. "Polyglot" vaadi için senkron bilingual panel manşet özelliği |
| M7 | **Tam-sayfa / tam-doküman çeviri** | DeepL, Google | **P1** | M | Görünen sayfayı yerinde çevir (toggle), sadece seçili snippet değil |
| M8 | **Sesli okuma (TTS)** | Speechify, Apple Books | **P1** | M | iOS: `AVSpeechSynthesizer`; web: Web Speech API. Erişilebilirlik + yolda dinleme |
| M9 | **Flashcard / kelime export (Anki)** | LingQ | P2 | M | Çeviri-yoğun ürün için doğal: terim+çeviri kaydet → Anki export. Niş tanımlayıcı |
| M10 | **Okuma istatistikleri / streak** | Readwise Reader | P2 | M | `reading_progress` ham veriyi veriyor; agregasyon + dashboard. Retention sürücüsü |
| M11 | **Taranmış PDF için OCR** | Acrobat, SciSpace | P2 | L | Eski akademik PDF'ler tarama → RAG/çeviri sessizce başarısız. iOS Vision; web Tesseract |
| M12 | **Sayfa düzeyi yer imi** | her okuyucu | P2 | S | Bugün gerçek bookmark yok. Hızlı kazanım |
| M13 | **Bölüm-düzeyi özet** | Scholarcy, SciSpace | P2 | M | Mevcut chunk+sayfa yapısıyla başlık başına özet |
| M19 | **Sözlük araması (kelimeye dokun → tanım)** | Apple Books, Kindle | P2 | S | Tam çeviriden hafif; tek kelime akademik İngilizce için iyi |
| M20 | **Highlight'lara etiket** | Readwise, Zotero | P2 | S | Anotasyonların etiketi yok; sadece dosyaların var |
| M14-18 | Audio overview (NotebookLM), EPUB, işbirliği/paylaşım, web clipper, formül/tablo çıkarma | çeşitli | P3 | L-XL | Gelecek; ağır lift |

### Yarım kalmış özellikler (UI var backend yok / tersi)

| Özellik | Durum | Kanıt |
|---|---|---|
| Web'de Quiz | Tip var, servis/UI yok | `types/models.ts:88 QuizQuestion`; sıfır route/component |
| Web Apple Sign-In | Buton stub'a bağlı | `page.tsx:50-53` alert + Google'a yönlendir |
| Web'de Klasör/Etiket | Şema+iOS tam; web'de yönetim UI'ı yok | `app/(app)/`'de route yok |
| Görsel "Ask AI" base64 | Çalışıyor ama kod belirsiz | `ImageSelectionPopup.tsx:71-77` yorumları formatın kafa karışıklığını itiraf ediyor |

### Var ama kötü implement edilmiş

| Özellik | Sorun | Kanıt |
|---|---|---|
| "Atıf" (RAG) | Atıf deniyor ama sadece **kullanıcının kendi sayfa numarasını** gösteriyor (`[Sayfa X]`), bibliyografik kaynak değil. Akademisyen için "atıf" = kaynak demek | `RAGContextBuilder.swift:66`, `rag.ts:149` |
| Web PDF viewer | 985→382 satıra bölündü (iyi) ama hâlâ zoom+seçim+görsel+anotasyon+sanallaştırma tek yerde | `PDFViewer.tsx` |
| Görsel bölge tespiti (iOS) | Gerçek gömülü-görsel çıkarma değil, heuristik nokta/yarıçap (radius:80) | `PDFImageService.swift:159` |

---

## 4. Kod Mimarisi — 7/10

**Güçlü:** Zustand migrasyonu **tamamlanmış** (Context duplikasyonu yok), 985 satırlık PDFViewer gerçekten 5 hook'a bölünmüş (artık 382), API route'ları auth-gated + input validasyonlu, auth sınırı `proxy.ts`'te (Next.js 16'nın middleware halefi — "middleware.ts yok" tasarım gereği), **`src`'de sıfır `any`**.

**Zayıf (operasyonel, yapısal değil):**

| # | Sorun | Dosya:satır | Öncelik | Çözüm | Efor |
|---|---|---|---|---|---|
| A1 | AI route'larında **rate limiting yok** — login'li kullanıcı endpoint'leri dövüp Gemini kotasını/maliyetini yakabilir | `app/api/gemini/{generate,stream,embed}/route.ts` | **P1** | userId bazlı rate limit (Upstash veya in-memory token bucket) | M |
| A2 | **113 `console.*` prod'a gidiyor** (84'ü `lib`'de, 26'sı `rag.ts`'te emoji debug); bazıları sorgu metni/chunk içeriği logluyor (PHI riski) | `lib/rag.ts:134,460-464`; `pdfCache.ts`; `gemini.ts` | **P1** | `logger` util veya NODE_ENV guard; içerik logları sil. (Not: `next.config.ts:19` prod'da console'u strip ediyor ama içerik-string'leri yine de hesaplanıyor) | M |
| A3 | **Supabase client tipsiz** — `Database` generic yok, her `.from().select()` `any` dönüyor, inline cast'lerle elle tipleniyor | `lib/supabase.ts:4`; `supabase-server.ts:9`; `proxy.ts:13` | P2 | `supabase gen types typescript` → `database.types.ts` | M |
| A4 | Reader sayfası 432 satır "god component", ~25 `useState` + 8 `useEffect`; seçim state'i (11 setter) çıkarılmalı | `reader/[id]/page.tsx:64-93` | P2 | `useReaderSelection` hook'una çıkar | M |
| A5 | Hiçbir yerde **network retry yok** (kural: max 3 retry) | `lib/rag.ts:273`; `gemini.ts:13,33` | P2 | API fetch helper'larını 3x exponential backoff ile sar | M |
| A6 | Tutarsız hata yüzeyi: `annotationSync`/`chatSync` hatayı yutup `[]`/`null` dönüyor (sessiz), `gemini.ts` throw ediyor → kullanıcı not kaydı başarısızlığını hiç görmüyor | `annotationSync.ts:35,87,131`; `useAnnotationStore.ts:42,61` | P2 | Tek kontrat; başarısızlığı toast'a propagate et | M |
| A7 | ChatPanel `handleSendMessage` `messages`'ı closure'dan okuyor ama effect deps'i eksik → stale-closure riski | `ChatPanel.tsx:114,169` | P2 | Functional setState / ref / doğru useCallback | S |
| A8 | Zustand store'ları **whole-store destructuring** ile tüketiliyor (selector yok) → her store değişiminde re-render | `reader/[id]/page.tsx:46-53`; `library/page.tsx:37` | P3 | Atomik selector `useReaderStore(s=>s.x)` / `useShallow` | S |
| A9 | `vectorSearch` 4 farklı RPC imzasını döngüde brute-force ediyor (şema belirsizliği koda gömülü) | `lib/rag.ts:301-353` | P3 | Gerçek RPC'yi doğrula, ölüleri sil | S |
| A10 | Ölü kod: `streamChatWithRAG` DEPRECATED ama export'lu; muhtemel kullanılmayan gemini export'ları | `lib/gemini.ts:202,227` | P3 | Sil (git geçmişi var) | S |

**Test (P2 boşluk):** Sadece 3 test dosyası (2 store + `gemini.translateText`). **Kritik yollar test edilmemiş:** RAG hibrit arama / RRF fusion (`rag.ts`, 646 satır, sıfır test), auth, reader sayfası, API route'lar, sync lib'leri.

---

## 5. Performans — 5.5/10

Sağlam temel (pdf.js self-hosted ✓, PDFViewer/thumbnail `next/dynamic` ✓, Supabase singleton ✓, IndexedDB blob cache ✓, donma bug'ı gerçekten çözülmüş ✓) ama **iki ciddi ölçeklenme uçurumu**:

| # | Sorun | Dosya:satır | Öncelik | Etki | Çözüm | Efor |
|---|---|---|---|---|---|---|
| P1 | **Gerçek sanallaştırma yok**: `Array.from({length: totalPages})` her sayfa için DOM div'i yaratıyor; sadece render içeriği pencereleniyor | `PDFViewer.tsx:238-295` | **P0** | 100+ sayfalık PDF → 100+ DOM node + 100 ref callback + 100 shimmer animasyonu hep canlı; layout/paint maliyeti sayfa sayısıyla lineer | Sadece pencere dilimini render et, pencere-dışını tek spacer div ile temsil et (veya react-window) | L |
| P2 | **Thumbnail yolu kart başına TÜM PDF'i indiriyor** (cache'li base64 yoksa); web upload'lar `thumbnail_base64` set etmiyor | `PDFThumbnail.tsx:79-100`; `useFileUpload.ts:51-57` | **P0** | 20-doküman kütüphane = 20 tam-PDF indirme (egress + RAM) + 20 pdf.js render, sırf sayfa-1 önizleme için | Upload anında küçük thumbnail (PNG/WebP) üret + sakla; fallback statik ikon | M |
| P3 | `overscanPages=10` → 21 tam sayfa (kanvas+text+annotation) aynı anda render | `PDFViewer.tsx:14,239-241` | P1 | 21 canlı sayfa = yüksek RAM; explicit canvas teardown yok | overscan'i 2-3'e indir; P1 ile eşle | S |
| P4 | **Her mesajda** RAG hibrit arama (embed API + 2 RPC) + bazen ekstra Gemini query-expansion | `gemini.ts:237-275,155-182`; `rag.ts:586-646` | P1 | Her kullanıcı turu = 1 embed + vectorSearch + bm25 (+ dil tespiti) stream başlamadan → ekstra gecikme & maliyet | (fileId,query) embedding cache; trivial follow-up'larda RAG atla | M |
| P5 | `AnnotationLayer` tüm `annotations` array'ini alıp sayfa başına filter ediyor; herhangi değişimde tüm pencereli kanvasları redraw | `PDFViewer.tsx:280-286`; `AnnotationLayer.tsx:43,107` | P1 | Tek highlight ekleme → ~21 mount'lu layer'da draw effect | Sayfa başına `useMemo` ile grupla, `React.memo` ile sar | S |
| P6 | `react-markdown` streaming'de her chunk'ta tüm mesajı yeniden parse ediyor | `ChatPanel.tsx:193-200,410` | P1 | Uzun cevaplarda görünür jank | Mesaj id başına memoize; ~50ms chunk batch | S |
| P7 | Kütüphane sorgusu fetch-all `select('*')` (base64 blob dahil), pagination yok | `useDocuments.ts:73-90` | P1 | Tüm kütüphane + büyük base64 sütunları tek seferde; dosya sayısıyla sınırsız büyür | `.range()` pagination; explicit sütun, `thumbnail_base64` hariç | M |
| P8 | Reader veri çekme waterfall: doc → signedUrl → chunks → progress → `getUser()` seri | `reader/[id]/page.tsx:167-208` | P1 | PDF render öncesi 4-5 seri round-trip | Bağımsız okumaları `Promise.all` | S |
| P9 | Hiç `next/image` yok (ham `<img>`) | `PDFThumbnail.tsx:124`; `ChatPanel.tsx:401,452` | P2 | Otomatik resize/format/lazy decode yok | URL-backed görseller için `next/image`; base64 için `loading=lazy` | M |
| P10 | Bundle analyzer yok; framer-motion sadece 2 dosyada kullanılıyor ama shipliyor | `next.config.ts` | P2 | Regresyon takibi yok | `@next/bundle-analyzer`; framer-motion'u lazy/değiştir | S |

---

## 6. Yol Haritası — "Büyük Şirket Ürünü" Seviyesine

Sıra: önce ucuz-yüksek-etki cila → sonra akademik farklılaştırıcılar → sonra sertleştirme. Her faz bağımsız olarak ship edilebilir.

### Faz A — Görsel Tutarlılık & Cila (2-3 gün) 🎨
*"Dark modda siyah butonlu, yarım bitmiş" hissini "tutarlı ürün"e çeviren en hızlı kazanımlar.*
- **U1** `--primary` → terracotta (1 satır) — bütün sade butonları düzeltir
- **U4** Eski token'lara dark/sepia override — 4 bileşeni dark modda düzeltir
- **U2** Kütüphane hex'lerini token'a çevir — en çok kullanılan ekranı dark modda düzeltir
- **U3** `PDFToolbar` → `ReaderToolbar` (cilalı versiyonu bağla, emoji'yi sil)
- **U5-U9** Font/renk re-token, kanvas zemini
- **U13-U17** Ölü butonlar, ham hata, diakritik, uydurma istatistik (toplu `fix:` commit)
- **Çıktı:** Tüm ekranlar 3 temada tutarlı, palet tek, emoji→Lucide

### Faz B — Performans Uçurumları (3-4 gün) ⚡
*Büyük PDF + kalabalık kütüphane senaryolarında ürünü kullanılamaz olmaktan kurtarır.*
- **P1+P3** Reader gerçek sanallaştırma + overscan düşür → 100+ sayfa için tek büyük kazanım
- **P2+P7** Upload'ta thumbnail üret + kütüphane pagination → egress/scroll kazanımı
- **P4** RAG embedding cache → mesaj başına gecikme & Gemini maliyeti
- **P5,P6,P8** Memoization + paralel fetch (hızlı kazanımlar)
- **Çıktı:** 200 sayfalık PDF ve 50 dokümanlık kütüphane akıcı

### Faz C — Akademik Farklılaştırıcılar (1-2 hafta) 🎓
*Ürünü "PDF chat oyuncağı"ndan "araştırma aracı"na taşıyan katman. Sırayla en yüksek ROI.*
- **M3** Kütüphane-geneli sohbet (backend ~%80 hazır — en yüksek ROI)
- **M1+M2** Atıf/kaynakça çıkarma + BibTeX/RIS export (Zotero entegrasyonu = moat)
- **M4** Anahat/TOC navigasyonu (neredeyse bedava — PDFKit/pdfjs verir)
- **M5** Highlight export (veri hazır)
- **M6+M7** Yan-yana + tam-sayfa çeviri ("Polyglot" vaadi)
- **M8** TTS sesli okuma
- **Çıktı:** SciSpace/Readwise ile aynı masada konuşulabilir ürün

### Faz D — Platform Paritesi & Sertleştirme (3-5 gün) 🔧
- Web'e **quiz** + **PDF içi arama** (iOS'tan port — iki platform tek hikaye)
- **A1** AI route rate limiting (maliyet/abuse koruması — deploy öncesi şart)
- **A2** console.* temizliği + logger util (PHI riski)
- **A3** Supabase tip üretimi
- **Test:** `rag.ts` RRF fusion + auth + reader smoke (Vitest + Playwright zaten kurulu)
- **A4-A10** Reader refactor, retry, tutarlı hata, ölü kod
- **Çıktı:** Operasyonel olgunluk, test güvencesi

### Hızlı kazanım listesi (her biri ≤ yarım gün, yüksek algı)
`U1` terracotta butonlar · `M4` TOC navigasyonu · `M5` highlight export · `M12` sayfa yer imi · `M19` sözlük araması · `M20` highlight etiketi · `P5/P6/P8` memoization · `U13` legal linkler · `U16` diakritik

---

## 7. Kapanış Değerlendirmesi

Bu uygulamanın **vizyonu zaten büyük şirket seviyesinde** (9/10) — tasarım dili, RAG kalitesi, Türkçe-öncelikli UX gerçek farklılaştırıcılar. Eksik olan iki şey:

1. **Yürütme tutarlılığı** — cilalı kod yazılmış ama bağlanmamış (ReaderToolbar ölü), tema sistemi 3 palete bölünmüş, en çok kullanılan ekran (kütüphane) dark modda kırık. Bunlar **az eforla** kapanır ve algıyı dramatik değiştirir.

2. **Akademik katman** — atıf, kütüphane-sohbeti, anahat, export. Bunlar olmadan ürün rakiplerinin gerisinde; **backend'in çoğu zaten hazır** (özellikle M3 kütüphane sohbeti).

**Önerilen ilk hamle:** Faz A (2-3 gün cila) → ürün anında "bitmiş" hisseder; sonra Faz C'de M3'ten başla (en yüksek ROI). Performans (Faz B) gerçek kullanıcı büyük PDF açmadan önce, deploy ölçeklenmeden tamamlanmalı.

**~3-4 haftalık odaklı çalışmayla** bu ürün büyük şirket vitrinine konulabilir.
