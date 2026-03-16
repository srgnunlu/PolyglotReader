# PolyglotReader Web UI — Komple Yeniden Tasarım Promptu (Claude Code İçin)

> **Bu prompt Claude Code'a verilecektir. Aşağıdaki talimatları adım adım uygula.**

---

## 🎯 Görev Tanımı

Sen bir **Senior UI/UX Architect** olarak görev yapıyorsun. PolyglotReader'ın web uygulamasını (`web/` dizini) sıfırdan yeniden tasarlayacaksın. Mevcut işlevselliği koruyarak, **hem mobil hem masaüstü** için profesyonel, sıcak ve güvenilir bir kullanıcı deneyimi inşa edeceksin.

### Vizyon
- **Claude + Apple estetiği**: Warm, samimi ama son derece profesyonel
- **PDF Reader merkez**: Uygulamanın kalbi PDF okuma ve AI etkileşim deneyimi
- **Hızlı çeviri**: Metin seç → anında çeviri popup'ı (killer feature)
- **Responsive-first**: Mobilde de masaüstü kadar kullanışlı

---

## 🛠️ Teknik Stack

### Mevcut (Koru)
- Next.js 16 (App Router)
- React 19
- TypeScript
- Supabase (Auth, DB, Storage)
- Zustand (state management)
- `@google/generative-ai` (server-side)
- `pdfjs-dist` + `react-pdf`

### Eklenecek
- **shadcn/ui** + **Radix UI** (component library)
- **Tailwind CSS** (mevcut, genişletilecek)
- **Framer Motion** (micro-animations, page transitions)
- **Lucide Icons** (consistent icon set)
- **next-themes** (dark/sepia/light mode)
- **cmdk** (command palette — ⌘K)
- **react-hot-toast** / **sonner** (notifications)

### Kurulum (İlk Adım)
```bash
cd web

# shadcn/ui kurulumu
npx shadcn@latest init
# Seçenekler: style=new-york, color=neutral, css-variables=yes

# Gerekli shadcn componentleri
npx shadcn@latest add button card dialog dropdown-menu input label popover scroll-area separator sheet sidebar skeleton tabs tooltip avatar badge command context-menu resizable toggle toggle-group

# Ek paketler
npm install framer-motion lucide-react next-themes sonner cmdk vaul
```

---

## 🎨 Design System — "Corio Design Language"

### Renk Paleti (Claude-Inspired Warm)

```css
/* tailwind.config.ts içinde extend edilecek */
:root {
  /* Primary — Warm Cream/Beige */
  --background: 40 33% 98%;        /* #FDFAF6 — ana arka plan */
  --foreground: 30 10% 15%;        /* #2A2520 — ana metin */
  
  /* Surface katmanları */
  --surface-1: 36 30% 96%;         /* #F7F3EE — card backgrounds */
  --surface-2: 34 25% 93%;         /* #F0EBE4 — hover states */
  --surface-3: 32 20% 88%;         /* #E4DDD5 — active states */
  
  /* Accent — Warm Terracotta/Amber */
  --accent: 24 80% 55%;            /* #D4713C — primary CTA */
  --accent-hover: 24 80% 48%;      /* darker on hover */
  --accent-subtle: 24 60% 94%;     /* #FAF0E8 — soft accent bg */
  
  /* Semantic */
  --success: 152 60% 42%;          /* Yeşil — başarı */
  --warning: 38 92% 55%;           /* Amber — uyarı */
  --destructive: 0 72% 55%;        /* Kırmızı — hata/sil */
  --info: 210 60% 52%;             /* Mavi — bilgi */
  
  /* PDF Reader Specific */
  --reader-bg: 40 30% 97%;         /* Okuma arka planı */
  --reader-toolbar: 40 20% 99%;    /* Toolbar */
  --highlight-yellow: 48 100% 85%;
  --highlight-green: 120 60% 85%;
  --highlight-blue: 210 80% 85%;
  --highlight-pink: 340 80% 88%;
  
  /* Sidebar */
  --sidebar-bg: 36 25% 95%;
  --sidebar-hover: 34 20% 90%;
  --sidebar-active: 24 60% 94%;
  
  /* Border */
  --border: 30 15% 88%;
  --border-subtle: 30 10% 92%;
  
  /* Shadows — warm tinted */
  --shadow-sm: 0 1px 2px rgba(42, 37, 32, 0.06);
  --shadow-md: 0 4px 12px rgba(42, 37, 32, 0.08);
  --shadow-lg: 0 12px 32px rgba(42, 37, 32, 0.12);
}

/* Dark Mode */
.dark {
  --background: 30 10% 10%;        /* #1C1917 */
  --foreground: 36 20% 90%;        /* #EBE5DD */
  --surface-1: 30 10% 13%;
  --surface-2: 30 10% 16%;
  --surface-3: 30 10% 20%;
  --accent: 24 80% 60%;
  --border: 30 10% 22%;
  --reader-bg: 30 8% 12%;
}

/* Sepia Mode (Okuma modu) */
.sepia {
  --background: 38 45% 92%;        /* #EDE4D3 */
  --foreground: 30 15% 18%;
  --reader-bg: 38 50% 90%;
  --surface-1: 38 40% 88%;
}
```

### Typography

```css
/* Font stack — Inter (UI) + Literata (reading) */
--font-sans: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
--font-reading: 'Literata', 'Georgia', serif;  /* PDF reader text overlay */
--font-mono: 'JetBrains Mono', 'Fira Code', monospace;

/* Scale */
--text-xs: 0.75rem;    /* 12px — meta, caption */
--text-sm: 0.875rem;   /* 14px — secondary */
--text-base: 1rem;     /* 16px — body */
--text-lg: 1.125rem;   /* 18px — subtitle */
--text-xl: 1.25rem;    /* 20px — heading */
--text-2xl: 1.5rem;    /* 24px — page title */
--text-3xl: 1.875rem;  /* 30px — hero */

/* Weight */
--font-normal: 400;
--font-medium: 500;
--font-semibold: 600;
```

### Spacing & Radius

```css
/* Consistent spacing scale (4px base) */
--space-1: 0.25rem;   /* 4px */
--space-2: 0.5rem;    /* 8px */
--space-3: 0.75rem;   /* 12px */
--space-4: 1rem;      /* 16px */
--space-6: 1.5rem;    /* 24px */
--space-8: 2rem;      /* 32px */

/* Radius — rounded but professional */
--radius-sm: 6px;
--radius-md: 10px;
--radius-lg: 14px;
--radius-xl: 20px;
--radius-full: 9999px;
```

### Motion

```css
/* Framer Motion defaults */
--ease-out: cubic-bezier(0.22, 1, 0.36, 1);
--duration-fast: 150ms;
--duration-normal: 250ms;
--duration-slow: 400ms;
```

---

## 📐 Sayfa Mimarileri

### 1. Layout System

```
┌─────────────────────────────────────────────────────┐
│ DESKTOP (≥1024px)                                   │
│ ┌──────┬────────────────────────────────────────┐   │
│ │      │                                        │   │
│ │ Side │         Main Content                   │   │
│ │ bar  │                                        │   │
│ │ 260px│                                        │   │
│ │      │                                        │   │
│ └──────┴────────────────────────────────────────┘   │
│                                                     │
│ MOBILE (<1024px)                                    │
│ ┌───────────────────────────────────────────────┐   │
│ │ ☰  App Title                          👤      │   │
│ ├───────────────────────────────────────────────┤   │
│ │                                               │   │
│ │           Main Content                        │   │
│ │                                               │   │
│ ├───────────────────────────────────────────────┤   │
│ │  📚 Library  │  📖 Reader  │  ⚙️ Settings    │   │
│ └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Sidebar (Desktop):**
- shadcn `<Sidebar>` component kullan
- Collapsible (icon-only mode: 64px)
- Sections: Kütüphane, Klasörler, Etiketler, Ayarlar
- User avatar + dropdown (bottom)
- Keyboard shortcut: `⌘ + \` to toggle

**Bottom Navigation (Mobile):**
- 3-4 tab: Kütüphane, Okuyucu, Defterim, Ayarlar
- Active tab: accent color fill
- Haptic-feel micro animation on tap

### 2. Login / Auth Page (`/login`)

```
Design:
- Centered card (max-width: 420px)
- Warm gradient background (cream → soft amber)
- App logo + tagline: "Belgeleriniz için AI destekli okuma asistanı"
- Google Sign-In button (full width, branded)
- Apple Sign-In button (full width, branded)
- Subtle floating PDF page illustrations (decorative, CSS only)
- Footer: "Giriş yaparak Kullanım Şartlarını kabul ediyorsunuz"

Mobile:
- Full-screen, card takes ~90% width
- No decorative illustrations (performance)
```

### 3. Library Page (`/library`)

```
Desktop Layout:
┌──────────────────────────────────────────────────────┐
│ Sidebar │  ┌──────────────────────────────────────┐  │
│         │  │ 📚 Kütüphane            🔍  ⬆️  ≡/▤ │  │
│ 📂 Tümü │  ├──────────────────────────────────────┤  │
│ 📁 Tıp  │  │                                      │  │
│ 📁 AI   │  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐        │  │
│ ───────  │  │  │ PDF│ │ PDF│ │ PDF│ │ PDF│        │  │
│ 🏷️ Tags  │  │  │card│ │card│ │card│ │card│        │  │
│         │  │  └────┘ └────┘ └────┘ └────┘        │  │
│         │  │  ┌────┐ ┌────┐ ┌────┐               │  │
│ ───────  │  │  │ PDF│ │ PDF│ │ + ⬆│               │  │
│ 👤 Hesap │  │  │card│ │card│ │Yükle│              │  │
│         │  │  └────┘ └────┘ └────┘               │  │
│         │  └──────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘

PDF Card Design:
┌─────────────────────────┐
│ ┌─────────────────────┐ │
│ │                     │ │  ← Thumbnail (aspect-ratio: 3/4)
│ │    PDF Thumbnail    │ │     Skeleton loading
│ │                     │ │     Hover: slight scale + shadow
│ └─────────────────────┘ │
│ Harrison's Principles... │  ← Title (2 lines max, ellipsis)
│ 📅 12 Mar 2026 · 2.4MB  │  ← Meta info
│ 🏷️ Tıp  📖 145 sayfa    │  ← Tags + page count
│ ────────────────── 65%   │  ← Reading progress bar
└─────────────────────────┘

Interactions:
- Hover: translateY(-2px) + shadow elevation
- Right-click / long-press: Context menu (Aç, Yeniden adlandır, Klasöre taşı, Sil)
- Drag & drop: Klasöre sürükle
- Upload: Drag files onto library area or click "+" button
- Search: Instant filter with debounce (300ms)
- View toggle: Grid (default) / List view
- Sort: İsim, Tarih, Boyut, Son okunan
```

### 4. ⭐ PDF Reader Page (`/reader/[id]`) — ANA ODAK

Bu sayfa uygulamanın kalbidir. Aşırı özenli tasarla.

```
DESKTOP LAYOUT (≥1280px):
┌──────────────────────────────────────────────────────────────────┐
│ ◀ Kütüphane   Harrison's Principles Ch.12        ☀️🌙  ⚙️  ⋮  │ ← Top bar
├────────┬─────────────────────────────────────┬───────────────────┤
│        │                                     │                   │
│ Thumb  │                                     │  💬 AI Asistan   │
│ nail   │                                     │  ───────────────  │
│ side   │         PDF CONTENT                 │  Bu bölümde ne   │
│ bar    │         (ana okuma alanı)            │  anlatılıyor?    │
│        │                                     │  ───────────────  │
│ [p1]   │                                     │  📝 Şu konuyu    │
│ [p2] ● │                                     │  açıkla...       │
│ [p3]   │                                     │  ───────────────  │
│ [p4]   │                                     │                   │
│ [p5]   │                                     │  💬 Chat input   │
│        │                                     │  [____________]  │
│ 80px   │          flex-1                     │     360px        │
├────────┴──────────────────┬──────────────────┴───────────────────┤
│ ◀ Sayfa 44/320 ▶  │  🔍 zoom  │ ✏️ Annotation Toolbar           │
└───────────────────────────┴──────────────────────────────────────┘

TABLET LAYOUT (768px-1279px):
- Thumbnail sidebar: hidden (toggle ile açılır)
- Chat panel: sheet olarak sağdan slide-in (Vaul drawer)
- Annotation toolbar: bottom floating bar

MOBILE LAYOUT (<768px):
- Full-screen PDF
- Bottom toolbar: sayfa nav + annotation + chat toggle
- Chat: Full-screen bottom sheet (drag up)
- Thumbnail: horizontal strip at bottom (swipeable)
```

#### 4a. PDF Viewer Core

```
Teknik gereksinimler:
- pdfjs-dist ile render (mevcut)
- Pinch-to-zoom (mobile), scroll zoom (desktop)
- Smooth page transitions (no jarring jumps)
- Page preloading: current ± 2 pages
- Virtual scrolling for 500+ page PDFs
- Keyboard navigation: ← → sayfa, Space scroll, ⌘+F search
- Double-tap to zoom (mobile)
- Reading progress bar (thin, top of viewer)
```

#### 4b. ⭐⭐ Quick Translation Popup — KİLLER FEATURE

```
Bu özellik uygulamanın en önemli farklılaştırıcısı. Çok özenli tasarla.

AKIŞ:
1. Kullanıcı PDF'te metin seçer (mouse drag / touch selection)
2. Seçim tamamlanınca: Floating action bar belirir (seçimin hemen üstünde)

   ┌────────────────────────────────────────┐
   │  🌐 Çevir  │  ✏️ Vurgula  │  📝 Not  │  ← Floating bar
   └────────────────────────────────────────┘

3. "Çevir" tıklanınca: Translation popup açılır

   ┌──────────────────────────────────────────────┐
   │  🌐 Hızlı Çeviri                        ✕   │
   │  ─────────────────────────────────────────── │
   │  Orijinal (EN):                              │
   │  "The anterior cruciate ligament provides    │
   │   primary restraint to anterior tibial       │
   │   translation..."                            │
   │  ─────────────────────────────────────────── │
   │  Çeviri (TR):                                │
   │  "Ön çapraz bağ, anterior tibial             │
   │   translasyona karşı birincil kısıtlamayı    │
   │   sağlar..."                                 │
   │  ─────────────────────────────────────────── │
   │  [📋 Kopyala]  [📝 Not Olarak Kaydet]       │
   │  [🔊 Sesli Oku] [📖 Detaylı Açıklama]      │
   └──────────────────────────────────────────────┘

TASARIM DETAYLARI:
- Popup: Popover/floating panel (Radix Popover veya custom)
- Position: Seçili metnin yanında (viewport overflow handling!)
- Animation: scale(0.95) → scale(1) + fade, 200ms ease-out
- Loading state: Skeleton shimmer while Gemini translates
- Mobile: Bottom sheet olarak (Vaul drawer)
- Keyboard shortcut: Metin seçili iken T tuşuna bas → çevir
- "Detaylı Açıklama" butonu: Gemini'ye "Bu terimi tıp öğrencisine açıkla" promptu gönderir

EK ÖZELLIKLER:
- Dil algılama (otomatik kaynak dil tespiti)
- Son çeviriler geçmişi (session-based)
- Çeviri dilini değiştirme (TR ↔ EN toggle)
- Tıbbi terim ise özel badge: "🏥 Tıbbi Terim"
```

#### 4c. Annotation Toolbar

```
Desktop: PDF viewer altında horizontal toolbar
Mobile: Floating bottom bar (rounded, pill-shaped)

┌──────────────────────────────────────────────────────────┐
│ [🖌️ Highlight ▼] [___ Underline] [≡≡ Strikethrough]    │
│ [🎨 Sarı ● Yeşil ● Mavi ● Pembe ●]  [📝 Not Ekle]     │
│ [↩️ Geri Al]  [↪️ Yinele]                                │
└──────────────────────────────────────────────────────────┘

- Highlight renk seçimi: küçük color picker (4 preset + custom)
- Not ekleme: Inline annotation popup (sayfa kenarında pin icon)
- Hover on highlight: Tooltip ile not göster
```

#### 4d. AI Chat Panel

```
Design: Claude chat interface'inden ilham al

┌──────────────────────────────────┐
│ 💬 AI Asistan              [⊞]  │  ← Expand/collapse
│ ─────────────────────────────── │
│                                  │
│ ┌─ AI ──────────────────────┐   │
│ │ Bu bölüm ön çapraz bağın │   │
│ │ anatomisini anlatıyor...  │   │
│ │ 📄 Sayfa 45'ten           │   │  ← Sayfa referansı (tıklanabilir)
│ └───────────────────────────┘   │
│                                  │
│ ┌─ Sen ─────────────────────┐   │
│ │ Tedavi protokolünü özetle │   │
│ └───────────────────────────┘   │
│                                  │
│ ┌─ AI ──────────────────────┐   │
│ │ ⏳ Yazıyor...              │   │  ← Typing indicator (animated dots)
│ └───────────────────────────┘   │
│                                  │
│ ─────────────────────────────── │
│ Öneriler:                        │
│ [Bu bölümü özetle] [Quiz oluştur]│
│ [Anahtar terimleri listele]      │
│ ─────────────────────────────── │
│ 📎 ┌─────────────────────┐ ▶️  │
│    │ Mesajınızı yazın...  │     │
│    └─────────────────────┘     │
└──────────────────────────────────┘

- Markdown rendering (react-markdown + remark-gfm)
- Code blocks with syntax highlighting
- Sayfa referansları tıklanabilir → PDF o sayfaya scroll
- Suggested prompts: Contextual, sayfaya göre değişir
- Resizable panel (shadcn Resizable)
- ⌘+J: Toggle chat panel
```

#### 4e. Thumbnail Sidebar

```
Design:
- Sol tarafta 80px genişliğinde
- Her sayfa miniature thumbnail
- Aktif sayfa: accent border + slight scale
- Tıkla → o sayfaya git
- Scroll sync: PDF scroll ile thumbnail highlight güncellenir
- Collapse: ⌘+T veya toggle button

┌────────┐
│ ┌────┐ │
│ │ P1 │ │  ← Küçük thumbnail
│ └────┘ │
│ ┌════┐ │
│ ║ P2 ║ │  ← Aktif sayfa (accent border)
│ └════┘ │
│ ┌────┐ │
│ │ P3 │ │
│ └────┘ │
│  ...   │
└────────┘
```

### 5. Notebook Page (`/notes`)

```
Design:
- Masonry veya list layout
- Annotation kartları: highlight rengi + metin + kaynak PDF + sayfa
- Filter: Renk, PDF, Tarih, Arama
- Tıkla → PDF'in o sayfasına git
- Export: Markdown veya PDF olarak dışa aktar

Kart:
┌──────────────────────────────────┐
│ 🟡 Highlight                     │  ← Annotation tipi + renk
│ "Ön çapraz bağ, anterior tibial │
│  translasyona karşı birincil..." │  ← Seçili metin
│ ─────────────────────────────── │
│ 📄 Harrison's Ch.12 · Sayfa 45  │  ← Kaynak
│ 📝 "Sınav için önemli!"         │  ← Kullanıcı notu
│ 📅 14 Mar 2026                   │
└──────────────────────────────────┘
```

### 6. Settings Page (`/settings`)

```
Design:
- Clean, grouped sections (like iOS Settings)
- shadcn Card + Separator
- Sections:
  1. Hesap (avatar, isim, email, çıkış)
  2. Görünüm (tema: Light/Dark/Sepia, font size, font family)
  3. Okuma (varsayılan zoom, sayfa geçiş modu, çeviri dili)
  4. AI Asistan (model tercihi, context uzunluğu)
  5. Depolama (cache temizle, kullanım istatistikleri)
  6. Hakkında (versiyon, geri bildirim, kullanım şartları)
```

---

## 🧩 Shared Components

Aşağıdaki bileşenleri `components/ui/` veya `components/shared/` altında oluştur:

| Bileşen | Kullanım | Notlar |
|---------|----------|--------|
| `AppSidebar` | Ana sidebar (desktop) | shadcn Sidebar extend |
| `MobileNav` | Bottom tab bar (mobile) | Fixed bottom, 3-4 tab |
| `PDFViewer` | PDF render bileşeni | pdfjs-dist wrapper |
| `TranslationPopup` | Hızlı çeviri popup | Radix Popover + Vaul (mobile) |
| `FloatingActionBar` | Text selection toolbar | Metin seçince beliren bar |
| `ChatPanel` | AI sohbet paneli | Resizable, markdown support |
| `AnnotationToolbar` | Vurgulama araçları | Renk seçici, tip seçici |
| `ThumbnailSidebar` | PDF sayfa thumbnails | Lazy loading, scroll sync |
| `PDFCard` | Library'deki PDF kartı | Thumbnail, meta, progress |
| `CommandPalette` | ⌘+K arama | cmdk ile global arama |
| `ThemeSwitcher` | Tema değiştirici | Light/Dark/Sepia toggle |
| `EmptyState` | Boş durum görselleri | Library boş, arama sonuç yok |
| `LoadingSpinner` | Yükleniyor göstergesi | Skeleton + spinner variants |
| `AnnotationCard` | Notebook'taki not kartı | Renk, metin, kaynak, not |

---

## ⌨️ Keyboard Shortcuts (Global)

```
⌘ + K          → Command palette (global arama)
⌘ + \          → Sidebar toggle
⌘ + J          → Chat panel toggle
⌘ + T          → Thumbnail sidebar toggle
⌘ + F          → PDF içi arama
← / →          → Önceki/sonraki sayfa (reader)
Space           → Scroll down (reader)
Shift + Space   → Scroll up (reader)
T               → Seçili metni çevir (selection varken)
H               → Seçili metni highlight (selection varken)
N               → Seçili metne not ekle (selection varken)
Esc             → Popup/panel kapat
⌘ + 1/2/3      → Tema değiştir (light/dark/sepia)
```

---

## 📱 Responsive Breakpoints

```
sm:  640px   — Telefon (portrait)
md:  768px   — Tablet (portrait) / Büyük telefon (landscape)
lg:  1024px  — Tablet (landscape) / Küçük laptop
xl:  1280px  — Laptop / Desktop
2xl: 1536px  — Büyük ekran
```

**Kritik kararlar:**
- `< lg`: Bottom nav, no sidebar, chat = bottom sheet
- `≥ lg`: Sidebar, resizable panels
- `< md`: Translation popup = bottom sheet (Vaul)
- `≥ md`: Translation popup = floating popover

---

## 🔄 State Management (Zustand Stores)

```typescript
// stores/useThemeStore.ts
interface ThemeStore {
  theme: 'light' | 'dark' | 'sepia';
  fontSize: number;       // 14-24
  fontFamily: 'sans' | 'serif' | 'mono';
  setTheme: (theme) => void;
}

// stores/useReaderStore.ts
interface ReaderStore {
  currentPage: number;
  totalPages: number;
  zoom: number;
  selectedText: string | null;
  isTranslating: boolean;
  isChatOpen: boolean;
  isThumbnailOpen: boolean;
  annotations: Annotation[];
  setPage: (page: number) => void;
  setSelectedText: (text: string | null) => void;
  toggleChat: () => void;
  toggleThumbnail: () => void;
  addAnnotation: (annotation: Annotation) => void;
}

// stores/useLibraryStore.ts
interface LibraryStore {
  files: PDFFile[];
  folders: Folder[];
  tags: Tag[];
  viewMode: 'grid' | 'list';
  sortBy: 'name' | 'date' | 'size' | 'lastRead';
  searchQuery: string;
  selectedFolder: string | null;
  isUploading: boolean;
  uploadProgress: number;
}

// stores/useChatStore.ts
interface ChatStore {
  messages: ChatMessage[];
  isLoading: boolean;
  suggestions: string[];
  sendMessage: (text: string) => Promise<void>;
  clearHistory: () => void;
}
```

---

## 🎬 Micro-Animations (Framer Motion)

Uygulamaya hayat veren küçük animasyonlar:

```typescript
// Sayfa geçişleri
const pageTransition = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -8 },
  transition: { duration: 0.25, ease: [0.22, 1, 0.36, 1] }
};

// PDF Card hover
const cardHover = {
  whileHover: { y: -2, boxShadow: "var(--shadow-lg)" },
  transition: { duration: 0.2 }
};

// Translation popup
const popupAnimation = {
  initial: { opacity: 0, scale: 0.95, y: 4 },
  animate: { opacity: 1, scale: 1, y: 0 },
  exit: { opacity: 0, scale: 0.95, y: 4 },
  transition: { duration: 0.2, ease: "easeOut" }
};

// Chat message
const messageAnimation = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.3 }
};

// Skeleton shimmer
const shimmer = {
  backgroundImage: "linear-gradient(90deg, transparent, rgba(255,255,255,0.4), transparent)",
  backgroundSize: "200% 100%",
  animation: "shimmer 1.5s infinite"
};
```

---

## 📂 Dosya Yapısı (Hedef)

```
web/
├── app/
│   ├── layout.tsx              # Root layout (theme provider, sidebar)
│   ├── page.tsx                # Redirect to /library
│   ├── globals.css             # Design tokens, custom CSS
│   ├── (auth)/
│   │   └── login/
│   │       └── page.tsx        # Login page
│   ├── auth/
│   │   └── callback/
│   │       └── route.ts        # OAuth callback (mevcut)
│   ├── library/
│   │   └── page.tsx            # Library page
│   ├── reader/
│   │   └── [id]/
│   │       └── page.tsx        # PDF Reader page
│   ├── notes/
│   │   └── page.tsx            # Notebook page
│   ├── settings/
│   │   └── page.tsx            # Settings page
│   └── api/                    # API routes (mevcut, dokunma)
│       ├── chat/
│       ├── translate/
│       └── embed/
├── components/
│   ├── ui/                     # shadcn/ui components (auto-generated)
│   ├── layout/
│   │   ├── AppSidebar.tsx      # Desktop sidebar
│   │   ├── MobileNav.tsx       # Mobile bottom nav
│   │   ├── TopBar.tsx          # Page top bar
│   │   └── CommandPalette.tsx  # ⌘+K
│   ├── library/
│   │   ├── PDFCard.tsx         # PDF kart bileşeni
│   │   ├── PDFGrid.tsx         # Grid layout
│   │   ├── PDFList.tsx         # List layout
│   │   ├── UploadArea.tsx      # Drag & drop upload
│   │   ├── FolderTree.tsx      # Klasör ağacı
│   │   └── EmptyLibrary.tsx    # Boş durum
│   ├── reader/
│   │   ├── PDFViewer.tsx       # Ana PDF render bileşeni
│   │   ├── PDFPage.tsx         # Tekil sayfa render
│   │   ├── TranslationPopup.tsx # ⭐ Hızlı çeviri popup
│   │   ├── FloatingActionBar.tsx # Text selection toolbar
│   │   ├── AnnotationToolbar.tsx # Vurgulama araçları
│   │   ├── AnnotationLayer.tsx  # Overlay katmanı
│   │   ├── ThumbnailSidebar.tsx # Sayfa thumbnails
│   │   ├── ChatPanel.tsx        # AI sohbet paneli
│   │   ├── PageNavigation.tsx   # Sayfa navigasyonu
│   │   ├── ReadingProgress.tsx  # Okuma ilerleme çubuğu
│   │   └── ReaderToolbar.tsx    # Alt toolbar
│   ├── chat/
│   │   ├── ChatMessage.tsx      # Mesaj baloncuğu
│   │   ├── ChatInput.tsx        # Mesaj input
│   │   ├── SuggestedPrompts.tsx # Öneri butonları
│   │   └── TypingIndicator.tsx  # Yazıyor... animasyonu
│   ├── notebook/
│   │   ├── AnnotationCard.tsx   # Not kartı
│   │   └── NotebookFilters.tsx  # Filtre bar
│   └── shared/
│       ├── ThemeSwitcher.tsx    # Tema değiştirici
│       ├── LoadingSpinner.tsx   # Yükleniyor
│       ├── EmptyState.tsx       # Boş durum
│       └── ConfirmDialog.tsx    # Onay dialogu
├── hooks/
│   ├── useAuth.ts              # Auth hook (mevcut, güncelle)
│   ├── useDocuments.ts         # Documents hook (mevcut, güncelle)
│   ├── useTextSelection.ts     # PDF text selection hook (yeni)
│   ├── useKeyboardShortcuts.ts # Global shortcuts (yeni)
│   ├── useMediaQuery.ts        # Responsive hook (yeni)
│   └── useTranslation.ts       # Translation API hook (yeni)
├── stores/
│   ├── useThemeStore.ts
│   ├── useReaderStore.ts
│   ├── useLibraryStore.ts
│   └── useChatStore.ts
├── lib/
│   ├── supabase/               # Supabase client (mevcut)
│   ├── utils.ts                # Utility functions
│   └── constants.ts            # App constants
├── styles/
│   └── reader.css              # PDF reader specific styles
└── public/
    ├── fonts/                  # Inter, Literata, JetBrains Mono
    └── images/                 # Decorative assets
```

---

## 🚀 Uygulama Sırası

**Bu sırayla ilerle, her adımda çalışır durumda tut:**

### Faz 1: Foundation (Design System + Layout)
1. shadcn/ui kurulumu + Tailwind config (renk paleti, typography)
2. Root layout + theme provider (next-themes)
3. AppSidebar + MobileNav
4. ThemeSwitcher (light/dark/sepia)
5. Login page redesign

### Faz 2: Library
6. PDFCard component
7. Library page (grid + list view)
8. Upload area (drag & drop)
9. Folder/tag filtering
10. Search + sort

### Faz 3: PDF Reader — Core
11. PDFViewer component (pdfjs-dist refactor)
12. Page navigation + zoom controls
13. ThumbnailSidebar
14. Reading progress bar
15. Keyboard shortcuts

### Faz 4: PDF Reader — AI Features ⭐
16. Text selection detection (useTextSelection hook)
17. FloatingActionBar (seçim sonrası toolbar)
18. TranslationPopup (killer feature!)
19. AnnotationToolbar + AnnotationLayer
20. ChatPanel (resizable, markdown)
21. SuggestedPrompts (contextual)

### Faz 5: Notebook + Settings + Polish
22. Notebook page
23. Settings page
24. Command palette (⌘+K)
25. Final responsive testing
26. Performance optimization (lazy loading, code splitting)
27. Animations & micro-interactions

---

## ⚠️ Önemli Kurallar

1. **API route'lara DOKUNMA** — `app/api/` altındaki dosyalar çalışıyor, sadece frontend
2. **Supabase client'ı koru** — `lib/supabase/` mevcut config'i kullan
3. **Server components tercih et** — Data fetching server'da, interaktivite client'ta
4. **Türkçe UI** — Tüm kullanıcı-facing text Türkçe olmalı
5. **Accessibility** — ARIA labels, keyboard navigation, focus management
6. **Mobile-first** — Her bileşeni önce mobilde tasarla, sonra desktop'a genişlet
7. **Incremental** — Her faz sonunda çalışır durumda olmalı
8. **Error states** — Her bileşende loading, empty, error durumları olmalı

---

## 💬 İletişim Protokolü

Her faz başında bana şunu sor:
1. "Bu faz için hangi detayları netleştirmemi istersin?"
2. Tasarım kararları için seçenek sun (max 2-3 opsiyon, kısa açıklamalarla)
3. Her fazın sonunda kısa demo/özet ver

Sorularını Türkçe sor. Teknik terimlerde İngilizce kullanabilirsin.

---

*Bu prompt ile PolyglotReader web uygulamasını Claude/Apple kalitesinde bir deneyime dönüştüreceğiz.*
