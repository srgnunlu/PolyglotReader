# PDF Reader Profesyonel Yeniden Tasarım Planı

## Mevcut Durum Analizi

### Sorunlar
1. **PDFViewer.tsx 1192 satır** - Monolitik bileşen, toolbar + viewer + styles hepsi bir arada
2. **Karışık stil yaklaşımı** - CSS Modules + styled-jsx (~330 satır inline CSS) + inline styles karışık
3. **QuickTranslationPopup** sadece çeviri modu aktifken çalışıyor, SelectionPopup'tan bağımsız
4. **SelectionPopup** temel düzeyde - çeviri sonucu popup içinde kalıyor, emoji ikonlar
5. **Toolbar** kalabalık, gruplar net ayrılmamış, mobil deneyim yetersiz
6. **State yönetimi** karmaşık - page.tsx'te useReducer + useState karışımı
7. **Header** basit, "Özetle" butonu inline style ile yazılmış

---

## Yeniden Tasarım Planı

### Faz 1: Bileşen Yapısını Yeniden Düzenleme

**1.1 PDFViewer'ı parçalara ayır:**
```
components/reader/
├── PDFViewer.tsx            → Sadece PDF rendering (Document + Page + scroll)
├── PDFToolbar.tsx           → NEW: Ayrı toolbar bileşeni
├── PDFToolbar.module.css    → NEW: Toolbar stilleri
├── QuickTranslationPopup.tsx → Yeniden tasarla (unified popup)
├── SelectionPopup.tsx       → Yeniden tasarla (compact, modern)
├── AnnotationLayer.tsx      → Olduğu gibi kalabilir
├── AnnotationDetailPopup.tsx → Modernize et
├── SummaryPanel.tsx         → Modernize et
├── ImageSelectionPopup.tsx  → Modernize et
└── hooks/
    ├── usePDFLoader.ts      → NEW: PDF yükleme + cache logic
    ├── useDraggable.ts      → NEW: Ortak drag logic (tüm popup'lar için)
    └── useTextSelection.ts  → NEW: Metin seçim logic
```

**1.2 Styled-jsx → CSS Modules geçişi:**
- PDFViewer içindeki ~330 satır `<style jsx>` bloğunu `PDFViewer.module.css`'e taşı
- Tüm inline styles'ı CSS Modules'a taşı

### Faz 2: Modern Toolbar Tasarımı (PDFToolbar)

**İlham: Notion reader + Adobe Acrobat Web + Arc Browser**

```
┌──────────────────────────────────────────────────────────────────┐
│  ◀  3 / 24  ▶  │  −  100%  +  ⤢  │  🎨▼  │  🌐 Çeviri  💬 AI │
│  [Navigation]   │  [Zoom Controls]  │ [Color]│  [AI Tools]       │
└──────────────────────────────────────────────────────────────────┘
```

Tasarım prensipleri:
- **Floating toolbar** - PDF'in üstünde, hafif gölge ve blur ile
- Gruplar arası ince ayırıcı çizgiler (divider)
- SVG ikonlar (emoji yerine) - Lucide Icons veya custom SVG
- Tooltip'ler her butonda
- Aktif durumlar için pill-shape highlight
- Mobilde: bottom bar olarak konumlan (thumb-friendly)

### Faz 3: Birleşik Akıllı Selection Popup (En Kritik Kısım)

**Mevcut sorun:** SelectionPopup ve QuickTranslationPopup ayrı bileşenler, farklı davranışlar.

**Yeni tasarım - Unified SmartSelectionPopup:**

```
Metin seçildiğinde (her zaman gösterilir):
┌─────────────────────────────────────────────┐
│  ─── (drag handle) ───                      │
│                                             │
│  [🌐 Çevir] [✨ AI'a Sor] [🖍 İşaretle] [📋]│
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ "Seçili metin burada..."            │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─ Çeviri ────────────────────────────┐    │
│  │ Çeviri sonucu burada görünür        │    │  ← Çevir'e basınca açılır
│  │ (inline, ayrı popup değil)          │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

**Hızlı Çeviri Modu aktifken:**
```
┌────────────────────────────────────┐
│  ─── (drag handle) ───            │
│  🌐 Çeviri                    ✕   │
│  ─────────────────────────────    │
│  Çeviri sonucu burada...          │
│                                   │
│  [AI'a Sor] [İşaretle] [Kopyala] │  ← Alt bar: ek aksiyonlar
└────────────────────────────────────┘
```

**Temel özellikler:**
- **Sürüklenebilir** - Drag handle ile serbestçe hareket ettir
- **Sticky positioning** - Seçili metne yapışık, scroll ile takip eder
- **Sınır kontrolü** - Viewport dışına çıkmaz
- **Resize** - İçerik uzunluğuna göre otomatik boyut
- **Glassmorphism** - backdrop-filter: blur(20px), yarı saydam arka plan
- **Animasyonlu geçişler** - Çeviri sonucu slide-down ile gelir
- **Keyboard shortcut** - T: çevir, A: AI'a sor, C: kopyala
- **Pin mode** - Popup'ı sabitleyebilme (metin seçimi kalkarsa da kalır)

### Faz 4: Ortak useDraggable Hook

Tüm popup'larda tekrarlanan drag logic'i tek hook'a çek:

```typescript
function useDraggable(options: {
  initialPosition: { x: number; y: number };
  boundaryRef?: RefObject<HTMLElement>;
  stickyToRange?: Range | null;
  onDragEnd?: (position: { x: number; y: number }) => void;
}) {
  // Returns: position, dragHandleProps, isDragging
}
```

### Faz 5: Reader Page Layout Yenileme

**Mevcut header → Modern minimal header:**
```
┌──────────────────────────────────────────────────────┐
│  ← │ document-name.pdf                  │ 📝 Özetle │
└──────────────────────────────────────────────────────┘
```
- Daha ince (36px yükseklik)
- Dosya adı ortada, truncate
- Özetle butonu inline style yerine proper CSS class

**Sayfa yapısı:**
```
┌─ Header (36px) ──────────────────────────────────────────┐
│  ← │ filename.pdf                            │ Özetle   │
├──────────────────────────────────────────────────────────┤
│                                              │           │
│              PDF Viewer                      │  Chat     │
│         (with floating toolbar)              │  Panel    │
│                                              │ (resize)  │
│    ┌─ Smart Popup ──────────┐               │           │
│    │ Çevir | AI | İşaretle  │               │           │
│    │ Çeviri sonucu...       │               │           │
│    └────────────────────────┘               │           │
│                                              │           │
└──────────────────────────────────────────────────────────┘
```

### Faz 6: Stil Sistemi Tutarlılığı

- **Tüm bileşenler CSS Modules kullanacak** (styled-jsx kaldır)
- **Ortak değişkenler** globals.css'te tutulacak
- **Glassmorphism sistemi:**
  ```css
  .glass {
    background: rgba(255, 255, 255, 0.78);
    backdrop-filter: blur(20px) saturate(1.2);
    border: 1px solid rgba(255, 255, 255, 0.3);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.08);
  }
  /* Dark mode */
  @media (prefers-color-scheme: dark) {
    .glass {
      background: rgba(28, 25, 23, 0.82);
      border: 1px solid rgba(255, 255, 255, 0.08);
    }
  }
  ```
- **Tutarlı animasyonlar:** fade-in (0.15s), slide-up (0.2s), scale (0.1s)
- **Tutarlı border-radius:** popup=16px, button=8px, input=6px

### Faz 7: Mobil Deneyim

- **Toolbar**: Sayfanın altına taşı (bottom bar), thumb-zone
- **Selection Popup**: Bottom sheet (mevcut gibi ama daha iyi animasyon)
- **Chat Panel**: Full-screen overlay (mevcut gibi)
- **Çeviri**: Inline bottom sheet içinde göster

---

## Uygulama Sırası

1. **`useDraggable` hook** oluştur (ortak altyapı)
2. **`usePDFLoader` hook** oluştur (PDFViewer'dan ayır)
3. **`useTextSelection` hook** oluştur
4. **`PDFToolbar`** bileşenini oluştur (styled-jsx → CSS Modules)
5. **PDFViewer'ı refactor et** (hooks + ayrı toolbar)
6. **`SmartSelectionPopup`** oluştur (SelectionPopup + QuickTranslation birleşimi)
7. **Reader page layout** yenile (header, viewer wrapper)
8. **Mobil optimizasyonlar**

---

## Teknik Notlar

- SVG ikonlar için ayrı `ReaderIcons.tsx` dosyası oluştur (Lucide benzeri, minimal)
- Tüm popup z-index'leri düzenle: Toolbar=50, Popup=100, Modal=200
- `position: fixed` yerine `position: absolute` + containment kullan (performans)
- requestAnimationFrame ile sticky positioning (mevcut pattern'ı koru)
- Debounce: çeviri 300ms, progress save 500ms, scale 150ms
- Keyboard shortcuts: mevcut 1-4 renk + T (translate), Escape (close popup)
