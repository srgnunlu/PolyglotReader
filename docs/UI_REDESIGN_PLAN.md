# PolyglotReader (Corio Docs) — UI Yeniden Tasarım ve Premium Deneyim Planı

> **Tarih:** 2026-07-10 · **Kapsam:** iOS uygulaması (SwiftUI) · **Durum:** Plan — henüz kod değişikliği yok
> **Hazırlanma yöntemi:** Tüm `Views/` katmanının (48 dosya, ~12.300 satır) dosya dosya envanteri + 2025-2026 iOS tasarım trendleri, Apple HIG / Liquid Glass, SwiftUI animasyon API'leri ve rakip uygulama (PDF Expert, GoodNotes, Flow, LiquidText, Readlang, LingQ) web araştırması.

---

## Vizyon

**"İçerik önde, chrome geride, her dokunuş hissedilir."**

PolyglotReader'ı; akademik/teknik doküman okuyan bir kullanıcının elinde **milyon dolarlık bir ürün gibi hissettiren** — akıcı, derinlikli, dokunsal ve zarif — bir PDF okuyucuya dönüştürmek. Kuzey yıldızımız Apple Design Award kazananlarının ortak paydası: **netlik + odak + düşük bilişsel yük + ölçülü ama gerçek "delight"**. Görsel maksimalizm değil; her animasyonun bir şey *anlattığı*, her cam yüzeyin "bu içeriğin üzerinde yüzüyor" dediği bir arayüz.

Üç stratejik dayanak:

1. **Killer feature'ı taçlandır:** Metin seç → anlık çeviri popup'ı zaten teknik olarak sofistike (sürüklenebilir, pinch-zoom, akıllı konumlandırma, test edilebilir layout matematiği). Onu **Readlang hızı + LingQ derinliği** modeliyle dünya standardına taşı.
2. **Var olan cam dilini sistemleştir:** Uygulamada dağınık ama tutarlı bir "liquid glass" estetiği zaten var (`LiquidGlassComponents.swift`, katmanlı materyaller, indigo-mor gradyanlar). Eksik olan görsel kimlik değil — **token sistemi, tutarlılık ve iOS 26 Liquid Glass'a köprü**.
3. **Hissi tamamla:** Haptic'ler 5 noktada var, 20 noktada eksik. Kahraman geçişler (hero transition) hiç yok. Onboarding hiç yok. Bunlar "iyi uygulama" ile "premium uygulama" arasındaki fark.

---

## Mevcut Durum Analizi

### Ekran ekran mevcut hal

| Ekran | Dosya (satır) | Mevcut Durum | Değerlendirme |
|---|---|---|---|
| **Auth / Giriş** | `AuthView.swift` (501) | Animasyonlu mesh arka plan, 3 yüzen blur blob, glassmorphic logo, kademeli giriş animasyonları, Apple/Google butonları | ✅ En cilalı ekran — koru, ince ayar yeter |
| **Kütüphane** | `LibraryView.swift` (473) + `PDFCardView` (422) + `FlippablePDFCardView` (408) | 2 sütun cam kart grid'i, 3D flip ile AI özet, breadcrumb, filtre barı, çoklu seçim | 🟡 İyi temel; kart → okuyucu geçişi animasyonsuz, thumbnail yüklemede skeleton yok |
| **PDF Okuyucu** | `PDFReaderView.swift` (280) + 21 yardımcı dosya | Otomatik gizlenen cam üst/alt barlar, PageSpinner, OCR banner'ı, TTS şeridi | 🟡 İşlevsel ve modüler; bar tasarımı "yüzen dock" hissinden uzak, açılış geçişi ani |
| **Çeviri Popup** | `QuickTranslationPopup.swift` (256) + Layout/Chrome/ContentArea | 5 katmanlı cam, sürükle + pinch-zoom, akıllı flip/clamp yerleşim, oturum içi ölçek hafızası | 🟢 Teknik olarak güçlü; giriş animasyonu ve çeviri "reveal" anı sıradan, haptic yok, derinlik katmanı (detay görünümü) yok |
| **Seçim Popup** | `TextSelectionPopup.swift` (483) | 4 renk vurgu noktası, inline çeviri, AI, kopyala, not ekle | 🟡 İşlevsel ama kalabalık; renk seçiminde haptic/animasyon yok |
| **Chat** | `ChatView.swift` (627) | Bubble UI, typing indicator, akış sırasında debounced scroll, akıllı öneri çipleri, RAG durum banner'ı | 🟡 Zengin ama görsel olarak jenerik; mesaj girişi animasyonu, streaming metin efekti yok |
| **Quiz** | `QuizView.swift` (518) | Renk kodlu şıklar, açıklama kartı, skor halkası | 🟡 Doğru/yanlış anları duygusuz — kutlama/haptic yok |
| **Defterim** | `NotebookView` (357) + Dashboard (412) + Category (388) | Stat kartları, kategori kartları, annotation kartları | 🟡 Dashboard standart sistem kartları kullanıyor — cam dilinin dışında kalmış |
| **Ayarlar** | `SettingsView.swift` (287) | Standart grouped List | ⚪ Bilinçli sade — böyle kalabilir, mikro rötuş yeter |
| **Onboarding** | — | **YOK** | 🔴 En büyük boşluk: ilk açılış deneyimi, killer feature tanıtımı yok |
| **Splash** | — | **YOK** (AuthView fiilen karşılama görevi görüyor) | 🔴 Marka anı kaçırılıyor |

### Güçlü yanlar (KORU)

- **Tutarlı görsel imza:** Katmanlı materyal + indigo/mor radyal parıltı + çift gölge (siyah ambient + renkli glow) neredeyse her yüzeyde. Bu bir kimlik — sıfırlama, sistemleştir.
- **Durum kapsaması mükemmel:** Neredeyse her ekranın loading/empty/error varyantı var; global hata banner'ı, offline farkındalığı, retry akışları.
- **Modern SwiftUI mimarisi:** `NavigationStack` + tip güvenli rotalar, presentation detents, okuyucunun 22 odaklı dosyaya bölünmüş olması.
- **Reduce-motion desteği** ana yüzeylerde, 44pt dokunma hedefleri bilinçli.
- **Çeviri popup layout matematiği** saf fonksiyon + unit test edilebilir (`TranslationPopupLayout.swift`) — üzerine inşa edilecek sağlam temel.

### Zayıf yanlar (DEĞİŞTİR)

1. **Token sistemi yok:** `ThemeColors` (`Extensions/ViewExtensions.swift`) tanımlı ama **fiilen kullanılmıyor**; ekranlar doğrudan `.indigo`/`.purple` çağırıyor. ~25 hardcoded hex; 4 renkli vurgu paleti (`#fef08a`, `#bbf7d0`, `#fbcfe8`, `#bae6fd`) birden çok dosyada string olarak kopyalanmış. Spacing/radius tamamen magic number.
2. **Dynamic Type kırık:** Popup ve barlarda `.system(size: 12/14/16)` sabit boyutlar — erişilebilirlik ve HIG ihlali.
3. **Hero geçiş yok:** `matchedGeometryEffect` hiçbir yerde kullanılmıyor; kart → okuyucu `fullScreenCover` ile aniden açılıyor.
4. **Haptic boşlukları:** Vurgulama, çeviri tamamlanma, quiz cevabı, kütüphane aksiyonlarında sıfır haptic; mevcut 5 nokta da eski `UIImpactFeedbackGenerator` API'siyle.
5. **Ölü/ikili kod:** `LiquidGlassTabBar` inşa edilmiş ama kullanılmıyor (native TabView aktif); `glassmorphism()`/`cardStyle()`/`bounceEffect()` modifier'ları atıl; `CorioScan.` bildirim isimleri eski ürün adından kalma.
6. **Karışık lokalizasyon:** `Localizable.strings` var ama arayüzün büyük kısmı hardcoded Türkçe.
7. **Okuyucu popup'ları reduce-motion'a saygı göstermiyor.**

---

## Tasarım Dili (Design Language)

Tek dosyalık bir **DesignSystem** modülü (`PolyglotReader/DesignSystem/` klasörü) tüm token'ları toplar. Aşağıdaki her değer koddan (mevcut fiili kullanım) türetildi ve sistemleştirildi.

### Renk paleti — `DSColor`

Asset catalog'a taşınacak semantik renkler (dark/light varyantlı):

| Token | Değer (Light) | Kullanım |
|---|---|---|
| `brand` | Indigo `#6366F1` | Ana marka, CTA'lar, aktif durumlar |
| `brandSecondary` | Mor `#8B5CF6` | Gradyan eşi, AI özellikleri vurgusu |
| `brandGradient` | `[brand, brandSecondary]` | İkon dolguları, CTA butonları, parıltılar |
| `aiAccent` | Mor `#A855F7` | Sparkle/AI anları (özet, derin arama) |
| `success` / `warning` / `danger` | Sistem yeşil/turuncu/kırmızı | Semantik durumlar |
| `highlightYellow/Green/Pink/Blue` | `#fef08a` `#bbf7d0` `#fbcfe8` `#bae6fd` | Vurgu paleti — **tek kaynaktan**, string kopyaları silinir |
| `surfacePrimary/Secondary` | Sistem grouped background'lar | İçerik yüzeyleri (mevcut doğru kullanım korunur) |
| `glassGlow` | `brand.opacity(0.08–0.12)` | Cam yüzey renkli gölgesi |

**İlke:** Gradyan uygulamanın imzası — ama *sadece* ikon dolgusu, CTA ve parıltıda. Metin ve büyük yüzeylerde asla.

### Tipografi — `DSFont`

%100 SF Pro (custom font YOK — akademik okuyucu için doğru karar, korunuyor). Sabit boyutlar semantik stillere dönüştürülür:

| Token | Karşılık | Not |
|---|---|---|
| `displayTitle` | `.largeTitle.bold()` | Onboarding, boş durumlar |
| `screenTitle` | `.title2.bold()` | Ekran başlıkları |
| `cardTitle` | `.headline` | Kart adları |
| `body` | `.body` | Genel metin |
| `translation` | `.body` + `.rounded` design | Çeviri metni (mevcut rounded kimlik korunur, **Dynamic Type'a bağlanır**) |
| `aiSummary` | `.subheadline.italic()` + `.serif` | Flip kart özeti (mevcut serif imza korunur) |
| `caption` / `meta` | `.caption` / `.caption2` | Tarih, boyut, sayfa no |

**Kural:** `.system(size:)` yasak → SwiftLint custom rule ile denetlenir. Popup içinde ölçek gerekiyorsa `@ScaledMetric` kullanılır.

### Spacing — `DSSpacing`

4pt taban ızgara: `xxs=4, xs=8, sm=12, md=16, lg=24, xl=32, xxl=48`. Kart iç padding `md`, ekran kenar padding `md`, section arası `lg`.

### Radius & Gölge — `DSRadius`, `DSShadow`

Mevcut fiili değerler token'lanır: `small=12, medium=16, card=20, popup=24, dock=28`.
İmza çift gölge tek modifier olur: `.dsShadow(.floating)` = siyah `0.12` ambient + `glassGlow` renkli, `radius: 24, y: 12`.

### Cam / Derinlik Sistemi — `DSGlass` (⚠️ mimari karar)

Araştırmanın en net bulgusu: Apple'ın **Liquid Glass** dili (iOS 26) tam olarak bu uygulamanın estetiğine gidiyor, ama `glassEffect` API'leri **yalnızca iOS 26+**. Deployment target iOS 17 olduğundan **Backport wrapper** deseni uygulanır:

```
.dsGlass(.bar)        →  iOS 26: .glassEffect(.regular, in: shape)
                          iOS 17-25: mevcut LiquidGlassBackground (ultraThinMaterial
                          + gradyan sheen + ince stroke) — tek çağrı noktası
```

Kurallar (HIG'den):
- Cam **yalnızca navigasyon katmanında**: barlar, dock, popup, sheet. Asla içerik/arka plan üzerinde.
- Cam cama binmez (iOS 26'da `GlassEffectContainer` ile gruplanır).
- İçerik taban katmanda, kontroller **üstte yüzer** — Flow by Moleskine modeli.
- Reduced Transparency / Increased Contrast otomatik desteklenir (native API'de bedava; fallback'te `@Environment(\.accessibilityReduceTransparency)` ile mat yüzeye düşülür).

### Animasyon ilkeleri — `DSMotion`

- **Varsayılan dil spring:** `.smooth` (geçişler), `.snappy` (kontroller), `.bouncy(extraBounce: 0.1)` (yalnızca kutlama anları). Mevcut el ayarı `response/dampingFraction` çağrıları bu üç semantik preset'e taşınır.
- **Hero geçişler:** iOS 18+ `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource` — kart → okuyucu için; iOS 17 fallback: mevcut fade. Aynı ekran morph'ları için `matchedGeometryEffect`.
- **Koreografi:** Çok adımlı anlar (quiz sonucu, onboarding) `KeyframeAnimator`; dikkat döngüleri (çevriliyor nabzı) `PhaseAnimator`.
- **Scroll:** Kütüphane kartları `.scrollTransition` ile viewport'a girerken hafif fade+scale; parallax `visualEffect` ile (main-thread dostu).
- **Kural:** "Bu animasyon kullanıcıya ne söylüyor?" cevabı yoksa animasyon silinir. Süreler ≤0.4s (kutlamalar hariç ≤0.8s).
- **Reduce-motion her yerde:** Tek bir `dsAnimation(_:)` helper'ı `accessibilityReduceMotion`'ı merkezi kontrol eder — popup'lardaki mevcut boşluk kapanır.

### Haptic stratejisi — `DSHaptics`

Modern `.sensoryFeedback(_:trigger:)` API'sine geçiş (iOS 17+, mevcut `UIImpactFeedbackGenerator` çağrıları sarmalanır):

| An | Feedback |
|---|---|
| Metin seçimi tamamlandı | `.selection` |
| **Çeviri popup'ı belirdi** | `.impact(weight: .light)` |
| **Çeviri tamamlandı** | `.impact(flexibility: .soft)` |
| Vurgu rengi uygulandı | `.selection` |
| Quiz doğru / yanlış | `.success` / `.error` |
| Doküman yükleme tamamlandı | `.success` |
| Sayfa spinner (mevcut) | korunur, yeni API'ye taşınır |
| Kaydırma/yazma gibi yüksek frekanslı olaylar | **asla** |

### Dark/Light tutarlılığı

Mevcut yaklaşım sağlam (system colors + `colorScheme`e duyarlı cam). Tek zorunluluk: tüm hex'ler asset catalog'a taşınırken her birine dark varyant tanımlanır; `white.opacity` sheen'leri `DSGlass` içinde merkezileşir.

---

## Faz 1: Temel — Token Sistemi + Navigasyon + İlk İzlenim

*Önce altyapı: sonraki her faz bu token'ların üzerine kurulur.*

### 1.1 DesignSystem modülü
- `DesignSystem/` klasörü: `DSColor.swift`, `DSFont.swift`, `DSSpacing.swift`, `DSGlass.swift`, `DSMotion.swift`, `DSHaptics.swift`.
- Asset catalog'a semantik renkler (dark/light). Highlight paletinin string kopyaları tek kaynağa indirgenir.
- `.dsGlass()` backport wrapper — mevcut `LiquidGlassBackground` fallback motoru olur; `if #available(iOS 26.0, *)` dalı `glassEffect`e bağlanır.
- Atıl kod temizliği: kullanılmayan `LiquidGlassTabBar`, `glassmorphism()`, `cardStyle()`, `CompactFolderCardView` vb. silinir (git'te tarih duruyor).
- SwiftLint custom rule: `.system(size:` ve `Color(hex:` view dosyalarında uyarı.

### 1.2 Onboarding akışı (YENİ — en yüksek etkili boşluk)
3 sayfalık, kaydırmalı, `KeyframeAnimator` koreografili tanıtım:
1. **"Oku"** — PDF sayfası derinlikli parallax ile belirir.
2. **"Seç, anında anla"** — killer feature demosu: örnek İngilizce cümle üzerinde animasyonlu seçim vurgusu → çeviri popup'ı spring ile açılır (gerçek bileşenin kendisi kullanılır — sahte görsel değil).
3. **"Sor, sına, hatırla"** — AI chat/quiz/defter üçlüsü ikon morph'larıyla.
- Devam butonu gradyan kapsül; son sayfa doğrudan Auth'a akar. `@AppStorage("hasSeenOnboarding")`.

### 1.3 Splash / açılış anı
- Launch screen storyboard'una logo; açılışta logo → AuthView (veya oturum varsa Kütüphane) geçişinde logonun `matchedGeometryEffect` benzeri ölçek+fade "devir teslimi". 1 saniyeyi geçmez.

### 1.4 Kütüphane yenileme
- Kart grid'i `List`/optimize `LazyVGrid` + `.scrollTransition` giriş efekti; `.equatable()` satırlar.
- **Thumbnail skeleton + shimmer** (soldan sağa, yalnızca dinamik içerik) — mevcut `ShimmerModifier` genelleştirilir.
- Toolbar butonları `.dsGlass(.control)` ortak stiline bağlanır.
- Boş kütüphane durumu: mevcut pulsing glow korunur + "ilk PDF'ini yükle" mikro-illüstrasyon anı.

### 1.5 Navigasyon modernizasyonu
- Tab bar: **native TabView korunur** (araştırma bulgusu: 2026'da custom tab bar çoğunlukla anti-pattern) — iOS 26'da `.tabBarMinimizeBehavior(.onScrollDown)` bedavaya eklenir; atıl `LiquidGlassTabBar` silinir.
- Kart → Okuyucu: iOS 18+ `.zoom` navigationTransition (fullScreenCover yerine zoom kaynaklı sunum); iOS 17 fallback cross-fade + scale.

**Faz 1 çıktısı:** Görsel dil merkezileşti, ilk açılış deneyimi var, kütüphane 120fps akıyor.

---

## Faz 2: PDF Okuyucu Deneyimi — "Chrome Geride"

*Flow by Moleskine + Liquid Glass felsefesi: sayfa ekranın tamamı, kontroller üzerinde yüzen cam.*

### 2.1 Yüzen okuyucu chrome'u
- Üst bar + alt dock, kenarlara yapışık barlar yerine **serbest yüzen cam kapsüllere** dönüşür (`.dsGlass(.bar)`, ekran kenarından `md` boşluk).
- Otomatik gizlenme korunur; gizlenirken `spring(.smooth)` ile aşağı/yukarı kayar + collapsed pill göstergesi mevcut haliyle kalır. 10s zamanlayıcı 6s'ye iner (araştırma: içerik-öncelikli okuyucularda chrome daha erken çekilir).
- Sayfa sayacı doc başlığıyla morph'lanır (tek satır, `contentTransition(.numericText())` sayfa değişiminde).

### 2.2 Çeviri popup'ı — killer feature parlatması (⭐ en kritik iş)
**Model: Readlang hızı (varsayılan) + LingQ derinliği (istenirse).**
- **Giriş:** seçim biter bitmez `spring(.snappy)` + hafif ölçek (0.92→1.0) + `.impact(.light)` haptic. Mevcut flip/clamp yerleşim matematiği aynen korunur.
- **Çeviri "reveal" anı:** metin blok halinde belirmek yerine `contentTransition(.opacity)` + satır bazlı yumuşak fade (gerekirse `TextRenderer` ile — yalnızca kısa metinlerde, uzun metinde düz fade). Tamamlanınca `.soft` haptic.
- **Çevriliyor durumu:** spinner yerine `PhaseAnimator` ile nabız atan gradyan "çeviri dalgası" çizgisi — markalı bekleme anı.
- **Derinlik katmanı (YENİ):** popup altında "Detay" çekme kolu → kart `spring` ile genişler: tam bağlam çevirisi, alternatif anlamlar, "sohbete taşı" CTA'sı. (LingQ modeli — isteyene derinlik, istemeyene hız.)
- **Cam:** 5 katmanlı mevcut `TranslationPopupBackground` `.dsGlass(.popup)`a taşınır; iOS 26'da `.glassEffect(.regular.interactive())` — sürüklerken cam parıldar.
- Pinch-zoom ve sürükleme korunur; `sessionScale` static'i `PDFReaderViewModel`e taşınır (mevcut öz-işaretli tech-debt kapanır).
- Reduce-motion: tüm popup animasyonları `dsAnimation` üzerinden.

### 2.3 TextSelectionPopup (zengin mod) sadeleştirme
- Renk noktaları: seçimde `.selection` haptic + seçilen nokta `spring(.bouncy)` ile büyür, vurgu sayfada aynı renkte kısa bir "parıltı süpürmesi" ile belirir.
- Aksiyon barı ikonografisi `DSFont`/`DSColor` token'larına bağlanır; "..." menüsü yerine ikinci satıra genişleyen aksiyonlar (PDF Expert'in bağlamsal, moda göre değişen toolbar dersi).

### 2.4 Sayfa geçişleri
- PDFKit dikey sürekli mod korunur (akademik okuma için doğru). Eklenen: sayfa numarası değişiminde dock'taki sayaçta `numericText` geçişi; navigator'dan sayfaya atlarken kısa cross-fade.
- `PageSpinner` popover'ı `.dsGlass` + mevcut haptic'leri yeni API'ye taşınır.

### 2.5 OCR banner + TTS şeridi
- İkisi de yüzen cam kapsül diline geçer; TTS aktifken dock'taki hoparlör ikonu `PhaseAnimator` ile hafif nabız.

**Faz 2 çıktısı:** Okuyucu "uygulama içinde sayfa" değil, "sayfanın üzerinde yüzen zarif kontroller" hissi veriyor; çeviri anı ürünün imza anı.

---

## Faz 3: AI Özellikleri UI

### 3.1 Chat arayüzü
- Mesaj balonları `DSColor.brand` + `dsShadow(.subtle)`; model balonları cam değil düz yüzey (cam = yalnızca navigasyon kuralı).
- **Streaming metin:** karakter akarken alt kenarda yumuşak gradyan maskesi; tamamlanınca maske fade-out. Debounced scroll korunur.
- Mesaj gönderme: input alanından balona `matchedGeometryEffect` mikro-uçuş + `.impact(.light)`.
- Öneri çipleri `.scrollTransition` ile kademeli giriş; deep-search "beyin" toggle'ına `PhaseAnimator` aktif nabız.
- `IndexingStatusBanner` ilerleme çubuğu gradyan + yüzde `numericText`.
- `[Sayfa N](jump:N)` atıf linkleri: basınca okuyucuda hedef sayfada kısa sarı "parıltı" vurgusu (atıf-navigasyon geri bildirimi).

### 3.2 Quiz ekranı
- Şık seçimi: doğruysa yeşil dolgu `spring(.bouncy)` + `.success` haptic; yanlışsa kısa shake + `.error`.
- **Skor halkası:** `KeyframeAnimator` ile 0→skor koreografisi (halka çizilir, sayı `numericText` ile sayar, %80+ ise tek seferlik konfeti patlaması — *kazanılmış* kutlama, ambient değil).
- Soru geçişleri: kart sağdan `spring` slide + eski soru fade.

### 3.3 RAG / arama arayüzü
- `SearchSheet` sonuç satırları: eşleşen kelime `highlightYellow` arka planla; sonuçlar kademeli `scrollTransition`.
- Sonuca atlayınca okuyucuda aynı sarı parıltı vurgusu (3.1 ile aynı bileşen).

### 3.4 Çeviri geçmişi (YENİ özellik önerisi)
- Oturum içi çevirilen metinler `QuickTranslationPopup` kapanırken hafızaya alınır; Defterim'e "Çeviriler" kategorisi eklenir (mevcut kategori kartı deseniyle). Akademik kullanıcı için tekrar-görme (spaced review) değeri yüksek — quiz altyapısıyla ileride birleşebilir.
- Not: Bu, saf UI fazları içindeki tek "yeni veri" işi — Supabase'de küçük bir tablo gerektirir (RLS ile). İstenirse Faz 3'ten çıkarılıp ayrı ele alınabilir.

### 3.5 Flip kart (AI özet) rötuşu
- 3D flip korunur (zaten iyi); özet yüklenirken sparkle nabzı `PhaseAnimator`a taşınır; kırılgan Türkçe keyword kategori tespiti Gemini auto-tag çıktısına bağlanır (UI değil ama kartın güvenilirliği için not edildi).

**Faz 3 çıktısı:** AI özellikleri "eklenti" değil ürünün dokusu gibi hissediliyor; her AI anının kendine özgü mor/sparkle kimliği var.

---

## Faz 4: Detay & Polish

### 4.1 Micro-interactions
- Tüm butonlara ortak `DSButtonStyle`: basınca 0.96 ölçek + `spring(.snappy)` (mevcut `PDFCardButtonStyle` genelleştirilir).
- Pull-to-refresh: kütüphanede özel indigo gradyan spinner.
- Favori yıldızı: dolarken `spring(.bouncy)` ölçek + minik parıltı.
- Toggle'lar/kapsüller: durum değişiminde `.selection` haptic.

### 4.2 Loading states
- Skeleton + shimmer standardı: kütüphane kartları, defter dashboard istatistikleri, chat geçmişi yüklenirken. Kural: yalnızca dinamik içerik iskeletlenir, chrome asla.
- `UploadingOverlay` yüzdesi `numericText`; tamamlanınca `.success` haptic + kısa checkmark morph.

### 4.3 Empty states
- Mevcut kapsam iyi — her boş durum kendi özelliğine "native" görünecek şekilde ayrıştırılır (boş kütüphane ≠ boş arama ≠ boş filtre sonucu). Pulsing glow imzası korunur; metinler sıcak-ama-ölçülü Türkçe (akademik kitleye kartunsu ton yok).

### 4.4 Error states
- Global `ErrorBannerView` `.dsGlass(.banner)` diline taşınır; retry butonu belirgin. Hata anında `.error` haptic (yalnızca kullanıcı-tetikli işlemlerde).

### 4.5 Geçiş animasyonları
- Sheet'ler: tümü tutarlı detent + köşe yarıçapı; `NoteDetailSheet`in drag-to-dismiss'i standartlaştırılır.
- Tab değişimi: içerik cross-fade (`.animation(.smooth)` — mevcut NotificationCenter tab-atlama akışı dahil).

### 4.6 Lokalizasyon & erişilebilirlik borcu (polish'in parçası)
- Hardcoded Türkçe string'ler `Localizable.strings`e taşınır (mevcut altyapı var, disiplin eksik).
- `ReaderTopBar`/`DocumentNavigatorView`/`ScannedPageOCRBanner` eksik VoiceOver etiketleri tamamlanır; popup'lara reduce-motion bağlanır (Faz 2'de altyapısı kurulmuştu).

**Faz 4 çıktısı:** "Küçük şeylerin hepsi doğru" hissi — premium algının asıl kaynağı.

---

## Faz 5: Premium Touches (kazanılmış anlar)

*Araştırma bulgusu: 2026'da bunlar ancak nadir ve hak edilmiş olursa premium okunur; ambient olursa ucuzlatır.*

- **Particle/konfeti:** yalnızca iki anda — quiz %80+ skor, ilk PDF yükleme tamamlanması. Native `Canvas` + `TimelineView` (kütüphane yok).
- **3D transforms:** Flip kart zaten var; eklenen tek şey navigator thumbnail'ından sayfaya geçerken hafif perspektif derinliği. Sayfa kıvırma efekti **bilinçli olarak yapılmıyor** (akademik dikey okumada gimmick).
- **Parallax:** Onboarding sayfalarında + boş durum illüstrasyonlarında `visualEffect` tabanlı hafif derinlik. Okuyucu içinde parallax yok (odak ilkesi).
- **Custom gestures:** Okuyucuda iki parmak çift dokunuş → "odak modu" (tüm chrome + gizlenir, yalnız sayfa). Popup'ta aşağı fırlatma → zarif dismiss.
- **Ses tasarımı:** v1'de **yok** (opsiyonel bırakıldı) — akademik bağlamda sessizlik varsayılan; ileride yalnızca quiz kutlamasına incecik bir "tık" düşünülebilir.
- **iOS 26 tam Liquid Glass geçişi:** `DSGlass` wrapper sayesinde tek noktadan: `glassEffect` + `GlassEffectContainer` + `glassEffectID` morph'ları aktive edilir; `.tabBarMinimizeBehavior` açılır. iOS 17-25 kullanıcıları bilinçli tasarlanmış materyal fallback'i görmeye devam eder.

---

## Teknik Kararlar

| Karar | Seçim | Gerekçe |
|---|---|---|
| **Animasyon kütüphanesi** | **%100 SwiftUI native** (spring presets, PhaseAnimator, KeyframeAnimator, TextRenderer). Lottie **yok**. | Mikro-etkileşim ve geçişler için native daha ucuz ve GPU dostu; Lottie yalnızca AE-tabanlı illüstrasyon gerektirirdi — onboarding'i gerçek bileşenlerle yapıyoruz (daha otantik, bakımı kolay). Bağımlılık eklenmemesi güvenlik/bakım açısından da tercih. |
| **Cam efekti** | `DSGlass` backport wrapper: iOS 26 → `glassEffect`, iOS 17-25 → mevcut `LiquidGlassBackground` motoru | Tek çağrı noktası, `#available` dağılmaz, gelecek geçişi bedava. |
| **Hero geçişler** | iOS 18+ `.navigationTransition(.zoom)`; iOS 17 fallback fade+scale | `matchedGeometryEffect` NavigationStack sınırını aşamıyor; zoom native ve 3 satır. |
| **Haptics** | `.sensoryFeedback` (iOS 17+), `DSHaptics` sarmalayıcı | Deklaratif, test edilebilir, mevcut UIKit generator'ları tek noktada emekliye ayrılır. |
| **State management** | Mevcut MVVM + `@StateObject`/`@EnvironmentObject` **değişmez** | UI redesign'ı mimari refactor'a dönüştürmemek — animasyon durumları view-local `@State`, tema/tercihler mevcut `SettingsViewModel`. |
| **Component mimarisi** | `DesignSystem/` token'ları + `Views/Components/` yeniden kullanılabilir stiller (`DSButtonStyle`, `DSCard`, `SkeletonView`) | Mevcut klasör düzeni korunur; her bileşen tek dosya, ~250 satır altı hedef. |
| **Liste performansı** | Kütüphane/defter uzun listeleri `List` veya optimize LazyVGrid + `.equatable()` satırlar + `CacheService` thumbnail önbelleği | Araştırma: LazyVStack uzun listede 120fps'i tutturamıyor; AsyncImage yeniden-fetch tuzağı. |
| **Min. iOS** | **17.0 korunur** | Kullanıcı tabanı kaybetmeden `sensoryFeedback`/`PhaseAnimator`/`KeyframeAnimator` zaten kullanılabilir; 18/26 özellikleri `#available` ile artımlı. |

---

## Risk ve Dikkat Noktaları

1. **Performans (⚠️ en büyük risk):** PDF render + cam blur + animasyon aynı karede pahalı. Önlemler: cam yalnızca chrome'da (sayfa üzerinde tam ekran blur asla); `visualEffect`/`scrollTransition` tercih (`GeometryReader` tabanlı el yapımı parallax yasak); Instruments ile her fazın sonunda 120Hz ProMotion doğrulaması; `drawingGroup()` yalnızca ölçülüp kanıtlanınca.
2. **Bellek:** Büyük PDF + thumbnail önbelleği + animasyon katmanları. Mevcut `CacheService` (100MB LRU) sınırları korunur; `MemoryDebugger` ile onboarding/okuyucu geçişlerinde ölçüm.
3. **Erişilebilirlik gerilemesi:** Redesign sırasında mevcut (iyi durumda olan) VoiceOver etiketleri kırılmamalı — her fazın çıkış kriterine "VoiceOver smoke test + Dynamic Type XL ekran turu" yazıldı. Reduce-motion/-transparency her yeni animasyon ve cam yüzeyde zorunlu.
4. **Cam okunabilirliği:** `.clear` cam yalnızca arkasında karartma katmanı varsa; metin taşıyan yüzeylerde `.regular`. Increased Contrast testleri.
5. **iOS 17 fallback kalitesi:** Yarım-cam görünüm riskine karşı kural: fallback *bilinçli tasarlanmış* materyal görünümü — "eksik iOS 26" değil.
6. **Kapsam sürüklenmesi:** Bu bir UI planı; `MarkdownView` parser yeniden yazımı, lokalizasyon borcunun tamamı, `CorioScan` isim temizliği gibi işler yalnızca dokunulan dosyalarda fırsatçı yapılır, ayrı görev olarak takip edilir.
7. **TestFlight zamanlaması:** Branch şu an `chore/testflight-prep` — Faz 1 token altyapısı davranış değiştirmediği için güvenli; görsel değişiklikler (Faz 2+) TestFlight build'lerinden ayrı feature branch'lerde ilerlemeli.

---

## Etki × Çaba Matrisi

| Faz | İş | Etki | Çaba | Öncelik |
|---|---|---|---|---|
| 1 | DesignSystem token'ları + DSGlass wrapper | 🔥🔥🔥 (her şeyin temeli) | Orta | **P0** |
| 1 | Onboarding akışı | 🔥🔥🔥 (ilk izlenim + feature keşfi) | Orta | **P0** |
| 1 | Kütüphane skeleton/scroll polish | 🔥🔥 | Düşük | P1 |
| 1 | Splash devir-teslim anı | 🔥 | Düşük | P2 |
| 2 | **Çeviri popup parlatması** | 🔥🔥🔥 (killer feature = ürünün imzası) | Orta | **P0** |
| 2 | Yüzen okuyucu chrome'u | 🔥🔥🔥 | Orta | P1 |
| 2 | Kart → okuyucu zoom geçişi | 🔥🔥 | Düşük (iOS 18+) | P1 |
| 3 | Chat streaming + mikro-uçuş | 🔥🔥 | Orta | P1 |
| 3 | Quiz kutlama koreografisi | 🔥🔥 | Düşük | P1 |
| 3 | Çeviri geçmişi (yeni özellik) | 🔥🔥 | Yüksek (backend dahil) | P2 |
| 4 | Haptic sistemi + micro-interactions | 🔥🔥🔥 (premium "his"in yarısı) | Düşük | **P0** |
| 4 | Skeleton standardı + empty/error polish | 🔥🔥 | Düşük | P1 |
| 4 | Lokalizasyon + VoiceOver borcu | 🔥 (App Store kalitesi) | Orta | P2 |
| 5 | Kazanılmış kutlamalar (konfeti, odak modu) | 🔥 | Düşük | P2 |
| 5 | iOS 26 tam Liquid Glass geçişi | 🔥🔥 (gelecek) | Düşük (wrapper sayesinde) | P2 |

**Önerilen sıra:** Faz 1 → Faz 2.2 (popup) → Faz 4.1+4.2 (haptic+skeleton) → Faz 2 kalanı → Faz 3 → Faz 4 kalanı → Faz 5. Gerekçe: P0'lar (token + onboarding + popup + haptic) tek başına algılanan kaliteyi en çok sıçratan dörtlü; Faz 5 tamamen opsiyonel kremadır.

---

## Kaynaklar (araştırma)

- Apple — Liquid Glass Technology Overview: https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass
- Donny Wals — Designing custom UI with Liquid Glass: https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/
- Liquid Glass backport deseni: https://netanel.io/blog/backporting-liquid-glass/
- Apple — Animation timing/movement: https://developer.apple.com/documentation/SwiftUI/Controlling-the-timing-and-movements-of-your-animations
- Jacob's Tech Tavern — SwiftUI 120fps scroll performansı: https://blog.jacobstechtavern.com/p/swiftui-scroll-performance-the-120fps
- Hacking with Swift — sensoryFeedback: https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-haptic-effects-using-sensory-feedback
- Peter Friese — Hero animations: https://peterfriese.dev/blog/2024/hero-animation/
- PDF Expert toolbar yaklaşımı: https://support.readdle.com/pdfexpert/en_US/tips-and-tricks/work-with-pdf-tools-and-customize-the-toolbar
- Flow by Moleskine (içerik-öncelikli chrome): https://apps.apple.com/us/app/flow-by-moleskine-studio/id1271361459
- LiquidText vs MarginNote (akademik okuma): https://paperlike.com/blogs/paperlikers-insights/liquidtext-vs-marginnote
- LingQ vs Readlang (çeviri popup UX): https://languavibe.com/lingq-vs-readlang/
- Apple Design Awards 2025: https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/
- iOS UX trendleri 2026: https://www.asappstudio.com/ios-ux-design-trends-2026/
- Empty state rehberi: https://mobbin.com/glossary/empty-state
