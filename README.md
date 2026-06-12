# PolyglotReader (Corio Docs)

Yapay zeka destekli PDF okuyucu ve belge analiz uygulaması. Akademik literatür okuyan, Türkçe konuşan kullanıcılar için tasarlandı: belgeyle sohbet (RAG), anında çeviri, anotasyon ve quiz üretimi.

| Platform | Konum | Teknoloji |
|---|---|---|
| iOS / macOS | `PolyglotReader/` | SwiftUI, PDFKit, supabase-swift |
| Web ("Corio Docs") | `web/` | Next.js 16, React 19, Tailwind v4, Zustand |

Ortak backend: **Supabase** (Postgres + pgvector, Auth, Storage) + **Google Gemini**.

## Özellikler

- **PDF okuma** — sayfa önbelleği, okuma ilerlemesi, zoom, tam ekran
- **AI sohbet (RAG)** — hibrit arama (vektör + BM25, RRF birleştirme), kaynak gösteren cevaplar
- **Hızlı çeviri** — metin seç → anında Türkçe çeviri popup'ı
- **Anotasyon** — vurgu/altçizgi, yüzde-tabanlı koordinatlarla cihazlar arası senkron
- **Not defteri** — tüm anotasyonların filtrelenebilir görünümü
- **Kütüphane** — klasör + etiket organizasyonu, arama, AI kategorilendirme

## Web — Geliştirme

```bash
cd web
pnpm install
cp .env.example .env.local   # değerleri doldur
pnpm dev                      # http://localhost:3000
```

Ortam değişkenleri (`web/.env.example` içinde açıklamalı):

| Değişken | Açıklama |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase proje URL'i |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon anahtarı (RLS ile korunur) |
| `GEMINI_API_KEY` | **Sadece sunucu** — `/api/gemini/*` route'ları okur |
| `GEMINI_MODEL` | Örn. `gemini-3-flash-preview` |

Kalite komutları:

```bash
pnpm typecheck   # TypeScript
pnpm lint        # ESLint
pnpm test        # Vitest birim testleri
pnpm build       # Üretim derlemesi
```

> PDF.js worker/cmaps/font dosyaları CDN'den değil, `scripts/copy-pdf-assets.mjs` ile
> `public/pdfjs/` altından servis edilir; `predev`/`prebuild` otomatik kopyalar.

## Web — Vercel Deploy

1. Vercel'de yeni proje → bu repo'yu bağla
2. **Root Directory:** `web` olarak ayarla (framework otomatik algılanır)
3. Environment Variables bölümüne yukarıdaki 4 değişkeni gir
4. Deploy — `prebuild` PDF.js varlıklarını otomatik kopyalar

Güvenlik mimarisi: Gemini anahtarı yalnızca sunucuda kalır; `src/proxy.ts`
oturum yenileme + sayfa düzeyinde auth koruması sağlar; tüm Supabase
tablolarında RLS aktiftir.

## iOS / macOS — Geliştirme

```bash
xcodebuild -scheme PolyglotReader -configuration Debug build
xcodebuild -scheme PolyglotReader -destination 'platform=iOS Simulator,name=iPhone 16' test
./Scripts/swiftlint.sh
```

API anahtarları gitignore'lanmış `Config.plist` dosyasından okunur — şablon ve
detaylar için [CLAUDE.md](CLAUDE.md) dosyasına bakın.

## Veritabanı

Şema ve RPC fonksiyonları [CLAUDE.md](CLAUDE.md) içinde belgelidir. SQL
migration dosyaları repo kökünde ve `PolyglotReader/Services/rag_migration.sql`
konumundadır. Tüm tablolarda `auth.uid() = user_id` RLS politikaları zorunludur.
