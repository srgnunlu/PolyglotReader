# PolyglotReader (Corio Docs) — Kapsamlı Proje İnceleme Raporu

**Tarih:** 12 Haziran 2026
**İncelenen branch:** `feature/web-ui-redesign`
**Kapsam:** Tüm kaynak kod (Swift + TypeScript), config dosyaları, SQL migration'lar, dokümantasyon, git geçmişi, canlı Supabase kontrolü

---

## 1. Proje Nedir, Ne Yapar (Özet)

PolyglotReader — web tarafında **"Corio Docs"** olarak markalanmış — yapay zeka destekli bir **PDF okuyucu ve belge analiz uygulaması**. Akademik makale / belge okuyan kullanıcılar (özellikle Türkçe konuşan, İngilizce literatür okuyan kitle) için tasarlanmış. Temel özellikler:

- **PDF okuma:** Sayfa sayfa görüntüleme, küçük resimler (thumbnail), okuma ilerlemesi takibi
- **AI sohbet (RAG):** Belge içeriği parçalara (chunk) bölünüp embedding'lenir; kullanıcı sorularına belgeden alıntılı, kaynak gösteren cevaplar üretilir (Google Gemini)
- **Hızlı çeviri:** Metin seç → anında Türkçe çeviri popup'ı ("killer feature")
- **Anotasyon:** Renkli vurgular (highlight), notlar; cihazdan bağımsız yüzde-tabanlı koordinatlar
- **Not defteri (Notebook):** Tüm anotasyonların toplandığı, filtrelenebilir görünüm
- **Quiz:** Belge içeriğinden AI ile soru üretimi (sadece iOS)
- **Kütüphane:** Klasör + etiket organizasyonu, arama, grid/liste görünümü

**İki platform var:**

| Platform | Konum | Durum |
|---|---|---|
| **iOS/macOS (SwiftUI)** | `PolyglotReader/` | Olgun — PROJECT-SCHEMA.MD'ye göre Faz 8 (erişilebilirlik + lokalizasyon) tamamlanmış, Faz 9 (App Store hazırlığı) bekliyor |
| **Web (Next.js)** | `web/` | Aktif geliştirme — "Corio Docs" UI redesign'ı ~%60-70 tamamlanmış, son commit'ler reader'daki render döngüsü buglarını düzeltiyor |

Backend her ikisinde de ortak: **Supabase** (Postgres + pgvector, Auth, Storage) + **Google Gemini API**.

---

## 2. Tech Stack

### Web (`web/` — "corio-docs-web")
| Katman | Teknoloji | Sürüm |
|---|---|---|
| Framework | Next.js (App Router) | 16.1.6 (güncel) |
| UI | React | 19.2.3 (güncel) |
| Dil | TypeScript (strict: true) | 5.x |
| Stil | Tailwind CSS v4 + shadcn/ui (23 bileşen) + "Corio Design Language" token'ları | 4.2.1 |
| State | Zustand (4 store) + Context API (anotasyonlar) | 5.0.9 |
| PDF | react-pdf + pdfjs-dist | 10.3.0 / 5.4.296 |
| AI | @google/generative-ai (model: gemini-3-flash-preview) | 0.24.1 |
| Backend SDK | @supabase/supabase-js + @supabase/ssr | 2.89.0 / 0.8.0 |
| Diğer | framer-motion, next-themes (light/dark/sepia), cmdk (⌘K), sonner, vaul, lucide-react | — |

### iOS/macOS (`PolyglotReader/` — 121 Swift dosyası, ~27.300 satır)
| Katman | Teknoloji | Sürüm |
|---|---|---|
| Framework | SwiftUI, iOS 17+ / macOS 14+ | Swift 5.9+ |
| Mimari | MVVM + Servis katmanı (facade pattern), tüm ViewModel'ler @MainActor | — |
| PDF | PDFKit | — |
| Backend SDK | supabase-swift | 2.38.1 |
| AI | google/generative-ai-swift | 0.5.6 |
| Güvenlik | Keychain, sertifika pinleme (Release), API key obfuscation (XOR+SHA256), jailbreak tespiti | — |
| Lint | SwiftLint (force unwrap = ERROR, print yasak, hardcoded key yasak) | — |

### Veritabanı (Supabase — proje: `tftmypxwgccdgvldhaya`)
- 9 tablo: `files`, `chats`, `annotations`, `document_chunks`, `pdf_images`, `reading_progress`, `folders`, `tags`, `file_tags`
- pgvector (768 boyut, Gemini text-embedding-004), IVFFlat index
- Hibrit arama: vektör (0.65-0.7) + BM25 tam metin (0.3-0.35), RRF birleştirme
- ~15 RPC fonksiyonu (çoğu SECURITY DEFINER)
- Storage bucket: `user_files` (private)

---

## 3. Mevcut Durum (Ne Çalışıyor, Ne Çalışmıyor)

### ✅ Çalışıyor
- **iOS uygulaması bütün olarak:** Auth (Apple + Google OAuth), kütüphane (klasör/etiket), PDF okuma, anotasyonlar, RAG sohbet, quiz, notebook, offline destek (SyncQueue), Türkçe lokalizasyon (100+ anahtar), debug araçları
- **Web — temel akış:** Google ile giriş, kütüphane (grid/liste, arama), PDF okuma (cache-first yükleme, zoom, sanal sayfa render), AI sohbet (RAG + streaming), hızlı çeviri, anotasyon katmanı, notebook, ayarlar, ⌘K komut paleti, 3 tema (light/dark/sepia)
- **RAG sistemi:** Diller arası (TR↔EN) arama, sorgu genişletme, yeniden sıralama (rerank), kaynak gösterimi — hem iOS hem web'de

### ⚠️ Kısmen çalışıyor / yeni düzeltilmiş
- **Web PDF reader stabilitesi:** Son 4 commit tamamen donma/sonsuz render döngüsü düzeltmesi (`f3e469a`, `03b0c8a`, `5683644`, `c02facb`). Düzeltmeler taze, regresyon riski var — kapsamlı manuel test yapılmamış görünüyor.
- **Sepia tema:** 3 ayrı düzeltme commit'i + hâlâ kökte debug ekran görüntüsü var (`library-sepia-debug.png`) — tam oturmamış olabilir.

### ❌ Çalışmıyor / eksik (Web)
1. **PDF yükleme (upload):** UI var ama backend bağlantısı yok — [library/page.tsx:181](web/src/app/(app)/library/page.tsx) `TODO: wire to Supabase upload logic`. **Web'den dosya yüklemek şu an mümkün değil.**
2. **Apple ile giriş:** Stub — alert gösterip Google'a yönlendiriyor ([page.tsx:50-54](web/src/app/page.tsx))
3. **Önbellek temizleme:** Ayarlar'da buton var, hiçbir şey yapmıyor ([settings/page.tsx:63](web/src/app/(app)/settings/page.tsx))
4. **Middleware yok:** Sunucu taraflı route koruması yok (detay: Güvenlik bölümü)
5. **Test yok:** Web'de sıfır test dosyası
6. **Deployment yok:** Vercel config, CI/CD, `.env.example` — hiçbiri yok

### Redesign planı ilerlemesi (37 görev, 5 chunk — `docs/superpowers/plans/`)
| Faz | Durum |
|---|---|
| 0-1: Temizlik + Foundation (Tailwind, shadcn, tema, layout, landing, login) | ✅ Tamamlandı |
| 2: Kütüphane | ✅ Tamamlandı |
| 3: PDF Reader çekirdek | ⏳ ~%90 (bug düzeltmeleri devam ediyor) |
| 4: AI özellikleri (çeviri popup, anotasyon, chat refactor) | ⏳ ~%50 |
| 5: Notebook/Ayarlar/Polish + Zustand geçişi | ⏳ ~%60 (CSS temizliği, responsive test kaldı) |

---

## 4. Kod Kalitesi Değerlendirmesi

### iOS (Swift): **8.5 / 10**
**Güçlü yanlar:**
- Örnek niteliğinde servis mimarisi: facade pattern, sorumluluk ayrımı (SupabaseService 16 dosyaya, ErrorHandlingService 8 extension'a bölünmüş)
- Tüm ViewModel'ler @MainActor, hiç `try!` yok, sadece **1 adet** force unwrap ([RAGContextBuilder.swift:137](PolyglotReader/Services/RAG/RAGContextBuilder.swift) — guard ile korunuyor, düşük risk)
- Merkezi hata yönetimi (AppError + retry/exponential backoff), hassas veri maskeleyen loglama
- SwiftLint sıkı kurallarla entegre, TODO/FIXME yok

**Zayıf yanlar:**
- 10 dosya 500+ satır; [PDFReaderView.swift](PolyglotReader/Views/Reader/PDFReaderView.swift) **1.128 satır** (bilinçli olarak "Phase 2 tech debt" işaretlenmiş)
- Test kapsamı ~%15: servis mock'ları ve temel unit testler var ama chat/reader/quiz akışları test edilmemiş
- Hardcoded admin e-postası (Models.swift:36)

### Web (TypeScript): **6.5 / 10**
**Güçlü yanlar:**
- TS strict mode açık, güncel framework sürümleri, temiz bileşen organizasyonu (53 bileşen, anlamlı isimlendirme)
- Zustand store'lar küçük ve odaklı, custom hook'lara iyi ayrıştırma yeni başlamış

**Zayıf yanlar:**
- [PDFViewer.tsx](web/src/components/reader/PDFViewer.tsx) **985 satır** — zoom, metin seçimi, görsel seçimi, anotasyon hepsi tek dosyada; son donma buglarının kaynağı büyük ihtimal bu karmaşıklık
- [ChatPanel.tsx](web/src/components/chat/ChatPanel.tsx) 498 satır, [rag.ts](web/src/lib/rag.ts) 654 satır
- **Sıfır test**, 115 adet `console.log/error` (bir kısmı debug logu, prod'a gidecek)
- Çakışan state yönetimi: Zustand geçişi yarım — bazı state hem store'da hem yerel/Context'te

### Genel kod kalitesi: **7.5 / 10**

---

## 5. UI/UX Değerlendirmesi

**Puan: 7.5 / 10** (vizyon 9, uygulama henüz 7)

- **Tasarım sistemi güçlü:** "Corio Design Language" — sıcak krem/terracotta palet (`#FDFAF6` zemin, `#D4713C` vurgu), Inter (UI) + Literata (okuma) + JetBrains Mono tipografisi. Claude + Apple estetiğinden ilham alan, tutarlı ve profesyonel bir kimlik. 33 KB'lık detaylı redesign spec'i ([polyglotreader-ui-redesign-prompt.md](polyglotreader-ui-redesign-prompt.md)) çok iyi hazırlanmış.
- **Responsive yapı doğru kurgulanmış:** Desktop'ta sidebar (260px) + 3 panelli reader (thumbnail | PDF | chat), mobilde alt tab bar + drawer'lar.
- **Tema desteği:** light/dark/sepia — ama sepia hâlâ tam oturmamış (3 düzeltme commit'i + debug ekran görüntüleri).
- **Eksik UX parçaları:** Upload akışı kopuk (kütüphaneye web'den dosya eklenemiyor — temel akışta delik), çeviri popup'ının "Frosted Light" final tasarımı yapılmamış, responsive son test turu atılmamış.
- **Dil:** Arayüz %100 Türkçe, i18n altyapısı yok — "Polyglot" isimli ürün için ileride sınırlayıcı.

---

## 6. Güvenlik Durumu

### 🔴 KRİTİK — hemen aksiyon gerekli

**⚠️ GÜVENLİK UYARISI 1 — Git'e commit edilmiş Gemini API anahtarı:**
[test_gemini.py](test_gemini.py) dosyası git'e **commit edilmiş** ve içinde hardcoded bir Gemini anahtarı var (`AIzaSyA3KA...`). Bu anahtar git geçmişinde kalıcı olarak duruyor; repo GitHub'da (private bile olsa) risk.
→ **Yapılacak:** Bu anahtarı Google AI Studio'dan derhal iptal et (rotate), dosyayı sil, gerekirse git geçmişinden temizle (BFG/git-filter-repo).

**⚠️ GÜVENLİK UYARISI 2 — Gemini anahtarı tarayıcıya gömülüyor (web mimarisi):**
Web uygulaması Gemini'yi **doğrudan client'tan** çağırıyor: `NEXT_PUBLIC_GEMINI_API_KEY` ([gemini.ts](web/src/lib/gemini.ts)). `.env.local` git'e commit edilmemiş (bunu doğruladım — `web/.gitignore` `.env*` içeriyor, agent raporundaki "commit edilmiş" iddiası yanlıştı), **ama** `NEXT_PUBLIC_` öneki anahtarı derlenen JavaScript'e gömer — siteyi açan herkes anahtarı görebilir ve kotanı tüketebilir / fatura çıkarabilir.
→ **Yapılacak:** Gemini çağrılarını Next.js API route'una (veya Supabase Edge Function'a) taşı; anahtar sadece sunucuda kalsın. Bu, deploy etmeden önce şart.

**⚠️ GÜVENLİK UYARISI 3 — RLS durumu belirsiz (doğrulanmalı):**
SQL dosyalarında `reading_progress`, `folders`, `tags`, `file_tags`, `document_chunks`, `pdf_images` için RLS politikaları var; ancak **`files`, `chats`, `annotations` tablolarının RLS'ini oluşturan hiçbir SQL repo'da yok** (sadece CLAUDE.md'de tablo tanımları var, RLS'siz). Canlı veritabanını kontrol etmeye çalıştım: SQL bağlantısı zaman aşımına uğradı (proje uykuda), Supabase güvenlik danışmanı boş döndü (iyi sinyal ama uyuyan projede güncel olmayabilir).
→ **Yapılacak:** Supabase Dashboard → Database → Tables'tan `files`, `chats`, `annotations` RLS'ini elle doğrula. Yoksa bir kullanıcı başka kullanıcının dosya/sohbet/anotasyonlarını okuyabilir demektir.

### 🟠 Orta öncelik
- **Web'de sunucu taraflı auth koruması yok:** `middleware.ts` yok; koruma sadece client-side `ProtectedRoute` bileşeniyle. Veri RLS'le korunuyorsa risk sınırlı, ama savunma katmanı eksik.
- **RLS tip uyumsuzluğu:** `document_chunks.file_id` TEXT, `files.id` UUID — politikalarda `auth.uid()::text` cast'leri var; sessiz politika hatası riski.
- **Git'te gereksiz hassas-ımsı dosyalar:** `1` (build hata çıktısı), 2 adet Claude oturum transkripti (.txt), `build_output.log`, `loglar.md` (gerçek kullanıcı ID'leri içeren uygulama logları) — secret yok ama temizlenmeli.

### ✅ İyi durumda
- **iOS güvenliği örnek seviyede:** Config.plist gitignore'da, Release'te anahtar obfuscation (XOR+SHA256), Keychain'de oturum saklama, sertifika pinleme, jailbreak tespiti, loglarda token/e-posta maskeleme. Kodda hardcoded secret taraması temiz.
- `service_role` anahtarı hiçbir yerde client'ta kullanılmamış.
- Web `.env.local` doğru şekilde gitignore'da.

**Güvenlik puanı: iOS 9/10 · Web 4/10 · Veritabanı 6/10 (RLS doğrulanana kadar)**

---

## 7. Performans

- **iOS — iyi:** Sayfa cache'i (PDFPageCacheService), bellek limitleri (80MB PDF, 50M piksel render sınırı), 2000 cümle / 30 sn indeksleme limitleri, embedding cache'i, arka plan indeksleme. Geçmişteki `findString()` çökmesi try-catch + rect validasyonuyla çözülmüş (AI_HIGHLIGHT_CRASH_FIXES.md).
- **Web — riskli noktalar:**
  - PDFViewer'da `overscanPages = 10` ile sanal render var ama 985 satırlık bileşende state değişimleri pahalı; son donma bugları bunun kanıtı.
  - PDF.js worker/cMaps **CDN'den** (jsdelivr) yükleniyor — CDN kesintisinde reader açılmaz; self-host edilmeli.
  - Supabase egress azaltmak için web cache + keep-alive servisi eklenmiş (ücretsiz tier bilinçli yönetiliyor — iyi).
  - `next.config.ts` boş: görsel optimizasyonu, bundle analizi vb. yapılandırılmamış.
- **Veritabanı — iyi:** IVFFlat vektör index'leri, GIN tam metin index'i, RRF hibrit arama. Ücretsiz tier'da proje uykuya dalıyor (bugün SQL bağlantısı bu yüzden zaman aşımına uğradı) — ilk istek yavaşlığı kullanıcıya yansır.

---

## 8. Tespit Edilen Hatalar / Eksikler (Öncelik Sırasıyla)

### P0 — Kritik (deploy/yayın öncesi şart)
1. **Commit edilmiş Gemini API anahtarı** (`test_gemini.py`) → anahtarı iptal et + dosyayı sil
2. **Gemini anahtarının client'a gömülmesi** (web mimarisi) → server-side'a taşı
3. **`files`, `chats`, `annotations` RLS doğrulaması** → Dashboard'dan kontrol, yoksa ekle
4. **Web'de PDF upload çalışmıyor** → temel akış kopuk (library/page.tsx:181)

### P1 — Yüksek
5. **Middleware auth koruması yok** (web) → `middleware.ts` + @supabase/ssr
6. **Migration kaosu:** 8 adet gevşek `fix_*.sql` dosyası repo kökünde, sıra belgesi yok, `rag_migration.sql` iki ayrı yerde duplike → `supabase/migrations/` klasörüne numaralı konsolidasyon
7. **Web'de sıfır test** → en azından RAG/auth/store'lara Vitest
8. **PDFViewer.tsx 985 satır** → donma buglarının kök sebebi; hook'lara bölünmeli
9. **Reader donma düzeltmeleri doğrulanmamış** → büyük PDF'lerle (100+ sayfa) manuel regresyon testi

### P2 — Orta
10. `document_chunks.file_id` TEXT/UUID tip uyumsuzluğu
11. Apple Sign-In (web) stub
12. Önbellek temizleme (web settings) sahte
13. Sepia tema tutarsızlıkları
14. PDF.js worker CDN bağımlılığı → self-host
15. Repo kökündeki çöp dosyalar: 5 ekran görüntüsü PNG, AJEM yazar kılavuzu PDF'i, `SKILL.md`, `claude-scientific-skills/`, `1`, 2 transkript .txt, `build_output.log`, `loglar.md` → sil + .gitignore güncelle
16. 115 console.log (web) → prod öncesi temizlik / env flag

### P3 — Düşük
17. Kök dizinde README.md yok
18. Deployment yapılandırması yok (vercel.json, CI/CD, .env.example)
19. iOS: RAGContextBuilder:137 force unwrap, hardcoded admin e-postası
20. i18n altyapısı yok (UI %100 Türkçe hardcoded)
21. iOS erişilebilirlik denetimi (WCAG AA) yapılmamış

---

## 9. İyileştirme Önerileri

1. **Gemini proxy mimarisi:** Tek bir Next.js API route (`/api/chat`, `/api/translate`, `/api/embed`) → Gemini. Anahtar sunucuda, istek başına Supabase auth token doğrulaması. iOS da ileride aynı proxy'yi kullanabilir (anahtar dağıtımı tek yerden, kota kontrolü mümkün olur).
2. **Migration disiplini:** `supabase/migrations/0001_init.sql ... 000N_...sql` yapısına geç; mevcut canlı şemayı `supabase db pull` ile çek, fix dosyalarını arşivle. Böylece şema = git'teki gerçek.
3. **PDFViewer refactor planı:** `usePDFZoom`, `useTextSelection` (zaten var, tam bağlanmalı), `useImageSelection`, `PDFPageList` olarak 4 parçaya böl. Donma buglarının tekrarını en kalıcı bu önler.
4. **Test stratejisi (minimum uygulanabilir):** Web'e Vitest + birkaç kritik test (RAG skorlama, auth hook, store'lar); Playwright zaten MCP olarak kurulu — login→library→reader smoke testi.
5. **Zustand geçişini bitir:** AnnotationContext → store; tek state kaynağı kalsın. Yarım geçiş, render döngüsü buglarını besliyor.
6. **Repo hijyeni:** Çöp dosyaları sil, .gitignore'a `*.png` (kök), `*.log`, transkript pattern'leri ekle, kök README yaz.
7. **Keep-alive + uyku yönetimi:** Ücretsiz tier'da kalınacaksa KeepAliveService'in web'de de çalıştığını doğrula; ya da küçük bir Supabase Pro planı maliyetiyle ($25/ay) karşılaştır.

---

## 10. Geliştirme Planı Önerisi

### Aşama 1 — Güvenlik yangını (yarım gün) 🔴
1. `test_gemini.py` içindeki anahtarı Google AI Studio'dan iptal et, dosyayı sil
2. Supabase Dashboard'dan `files`/`chats`/`annotations` RLS'ini doğrula, eksikse politikaları ekle
3. Çöp dosyaları sil + .gitignore güncelle (tek `chore:` commit'i)

### Aşama 2 — Web mimari düzeltmesi (2-3 gün) 🟠
4. Gemini çağrılarını `/api/*` route'larına taşı (anahtar sunucuda)
5. `middleware.ts` ile sunucu taraflı auth koruması
6. PDF upload'ı Supabase Storage'a bağla (kopuk temel akış)
7. PDF.js worker'ı self-host et

### Aşama 3 — Redesign'ı bitir (3-5 gün) 🟡
8. Faz 4: Çeviri popup final tasarımı, anotasyon senkron testi, ChatPanel bölme
9. Faz 5: Zustand geçişini tamamla, sepia temayı sabitle, responsive test turu
10. Büyük PDF'lerle (100+ sayfa) reader regresyon testi — donma düzeltmelerini doğrula

### Aşama 4 — Sağlamlaştırma (2-3 gün) 🟢
11. Migration konsolidasyonu (`supabase/migrations/`)
12. Web'e minimum test seti (Vitest + Playwright smoke)
13. console.log temizliği, kök README

### Aşama 5 — Yayın 🚀
14. Vercel deploy (env değişkenleri Vercel dashboard'dan) + `.env.example`
15. iOS Faz 9: App Store hazırlığı (ekran görüntüleri, gizlilik etiketi, TestFlight)

**Tahmini toplam:** ~2 hafta odaklı çalışmayla web yayına, iOS TestFlight'a hazır hale gelir.

---

## Genel Karne

| Alan | Puan | Not |
|---|---|---|
| Mimari | 8/10 | iOS örnek seviyede; web doğru yolda ama yarım geçişler var |
| Kod kalitesi | 7.5/10 | iOS 8.5, web 6.5 |
| UI/UX | 7.5/10 | Tasarım sistemi güçlü, uygulama %60-70 |
| Güvenlik | 6/10 | iOS 9, web 4 — commit edilmiş anahtar ve client-side Gemini puanı düşürüyor |
| Test | 4/10 | iOS kısmi, web sıfır |
| Dokümantasyon | 7/10 | Spec/plan mükemmel, README yok, migration belgesiz |
| Deploy hazırlığı | 3/10 | Hiçbir deployment yapılandırması yok |
| **GENEL** | **6.5/10** | Sağlam temel, net vizyon; yayın öncesi güvenlik + tamamlanma işi var |
