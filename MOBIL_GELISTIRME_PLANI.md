# CorioScan (PolyglotReader) — Mobil Uygulama (iOS/macOS) Geliştirme Planı

**Hazırlayan:** Ürün danışmanı incelemesi (SwiftUI mobil katmanı)
**Tarih:** 2026-06-13
**Kapsam:** SADECE iOS/macOS uygulaması (`PolyglotReader/`) — 121 Swift dosyası, ~27.300 satır. Web uygulaması kapsam dışı.
**Yöntem:** Tüm view, viewmodel, model, servis ve config dosyaları baştan sona okundu. Hiçbir dosya değiştirilmedi.

---

## 0. Yönetici Özeti (TLDR)

**Ne buldum:** Mimari ve servis katmanı olgun ve disiplinli (modüler MVVM, gerçek retry/backoff, hibrit RAG arama, katmanlı cache, log sanitizasyonu, sertifika pinning iskeleti). Ancak **App Store'a gönderimi bugün bloke eden 3 kritik (P0) sorun**, **kullanıcıyı doğrudan etkileyen birkaç ciddi (P1) hata** ve yaygın bir **light-mode / lokalizasyon yarım-bırakılmışlığı** var.

**En acil 3 şey (App Store blokeri):**
1. **`PrivacyInfo.xcprivacy` privacy manifest YOK** → Apple Mayıs 2024'ten beri manifestsiz uygulamayı yüklemede reddediyor. **P0**
2. **Uygulama içi hesap silme YOK** → Kılavuz 5.1.1(v) gereği hesap açan her uygulamada zorunlu. Kesin red. **P0**
3. **Gemini API anahtarı cihazda gömülü** (`Config.plist`) ve embedding çağrısında URL'de düz metin gidiyor; XOR "obfuscation" kolayca geri çözülür → kota hırsızlığı/faturalandırma riski. Web tarafı bunu zaten sunucuda doğru yapıyor. **P0/P1 (Güvenlik)**

**Kullanıcıyı en çok yaralayan ürün hataları:**
- **Chat'teki kaynak atıf linkleri (`[etiket](jump:N)`) tıklanmıyor** — RAG doküman-sohbetinin amiral özelliği sessizce ölü. **P0**
- **Tek paylaşılan `chatSession`** → ikinci doküman açılınca sohbet bağlamı bozuluyor, kullanıcı yanlış PDF'le konuşabiliyor. **P0**
- **Doküman içi arama yarım** (sonuç parçacığı/listesi yok), **quiz'de yanlış cevap incelemesi/retry yok**, **kopyala/kaydet onayı yok**.

**Ne yapmalıyım:** Aşağıdaki §9 yol haritasını izle. Sprint 0 (App Store blokerleri + P0 hatalar) gönderim için zorunlu; gerisi kalite ve büyüme.

> **Genel not:** Bu rapordaki bulgular dosya:satır kanıtıyla işaretlendi. Aksiyona geçmeden önce, özellikle Apple Sign-In entitlement'ı ve canlı Supabase RPC adları gibi "repoda görünmeyen ama Xcode/sunucuda olabilecek" maddeleri doğrulamak gerekiyor (§7'de işaretli).

---

## 1. UI/UX Kalitesi — Ekran Ekran

### 1.1 Auth / Onboarding (`AuthView.swift`)
Görsel olarak en cilalı ekran (mesh arka plan, glass kartlar, kademeli giriş animasyonları, `reduceMotion` saygılı). Ama fonksiyonel ve light-mode sorunları var.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Apple Sign-In hataları sessizce yutuluyor** — sadece `logError`, kullanıcıya hiçbir geri bildirim yok. Kullanıcı Apple'a basıyor, hiçbir şey olmuyor. | `AuthView.swift:204-206` | **P1** | S |
| **İlk-açılış onboarding / değer turu yok** — login kartındaki 3 özellik satırı tüm "onboarding". Sync/gizlilik anlatılmıyor. | `AuthView.swift:140-190` | P2 | M |
| **Sözleşme/Gizlilik metni tıklanamaz** — düz `Text`. Oysa Settings'te gerçek URL'ler var (`:196-208`). App Review 5.1.1 erişilebilir şart bekler. | `AuthView.swift:300-308` | **P1** | S |
| **Yükleme sırasında butonlar disable değil** → çift gönderim riski. | `AuthView.swift:193-263` | P2 | S |
| **Sahte Google "G"** (gradient daire + "G" metni) — Google marka kılavuzunu ihlal eder, resmi asset kullanılmalı. | `AuthView.swift:224-238` | P2 | S |
| Yalnız OAuth; e-posta/şifre veya misafir yok (v1 için kabul edilebilir). | `signInSection` | P3 | M |

### 1.2 Kütüphane / Ana ekran (`LibraryView`, `PDFCardView`, `FlippablePDFCardView`, `FolderViews`)
Özellik açısından zengin (klasör, etiket, sıralama, grid/liste, AI özet flip). v1'e göre güçlü. Sorun: keşfedilebilirlik, flip jesti çakışması, gömülü renkler.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Flip-to-özet jesti keşfedilemez, gereksiz ve çakışıyor** — `LongPress(0.3)→Drag` ipucu yok; aynı işi yapan bir `sparkle` butonu zaten var; ayrıca kartın `contextMenu` long-press'iyle çakışıyor. | `FlippablePDFCardView.swift:297-335`, `PDFCardView.swift:36` | **P1** | M |
| **Çoklu seçim / toplu işlem yok** — sil ve klasöre-taşı sadece kart başına context menu. PDF Expert/Files'ta standart. | `PDFCardView.swift:36-64` | P2 | L |
| **Liste satırları klasöre taşınamıyor / flip edilemiyor** — grid ile liste arasında özellik paritesi kırık. | `LibraryView` `PDFListRowView:211-279` | P2 | S |
| **Kategori tespiti gömülü Türkçe keyword eşleştirmesi** (`contains("tıp")...`) — kırılgan, sadece TR, backend'in `ai_category`'siyle çakışıyor. | `FlippablePDFCardView.swift:339-364` | P2 | S |
| **Klasör oluşturma sığ** — şemada `parent_id` ve `sfSymbol` var ama UI'da iç-içe klasör seçimi ve ikon seçimi yok (yarım). | `FolderViews.swift:344-423` | P2 | M |
| Boş-klasör durumu CTA'sız sade ikon+metin (üst seviye boş durum zengin ama). | `LibraryView:124-135` | P3 | S |

### 1.3 PDF Okuyucu Deneyimi (`PDFReaderView`, `PDFKitView`, `PDFKitCoordinator`, `CustomPDFView`)
En ağır ekran (1128 satırlık tek `body`). İşlevsel ama hem keşfedilebilirlik hem teknik kırılganlık burada yoğunlaşıyor.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Doküman içi arama yarım** — sonuç parçacığı/listesi yok, hiç arama yapılmadan "Sonuç bulunamadı" gösteriliyor, eşleşen metin gösterilmiyor. Preview/PDF Expert'in çok altında. | `PDFReaderView.swift:725-798` | **P1** | L |
| **PDF arka planında gömülü `Color.white`** → dark mode'da sayfa boşlukları beyaz parlıyor (PDFKit zaten `.systemGray6` kullanıyor — tutarsız). | `PDFReaderView.swift:82,101` vs `PDFKitView.swift:61` | **P1** | S |
| **Genel PDF yükleme-hata ekranı** — sebep ne olursa olsun "tekrar deneyin", offline farkındalığı yok (oysa `NetworkMonitor` mevcut). | `PDFReaderView.swift:226-259` | **P1** | M |
| **İlk sayfaya gitmeden önce 0.6s sabit `sleep`** — yavaş cihazda yarış (atlama başarısız), hızlı cihazda gereksiz gecikme. `onRenderComplete`'e bağlanmalı. | `PDFReaderView.swift:374-379` | **P1** | S |
| **Sayfa-senkron döngüsü** — `syncCurrentPage` programatik vs scroll değişimini ayırt edemiyor, hızlı scroll'da sayfayı geri çekebiliyor ("PDF kayıyor" şikayeti). | `PDFKitView.swift:163-180` | **P1** | M |
| **İlerleme yazımı throttle'sız** — `reportProgress` her scroll tikinde tetikleniyor; Supabase'e gidiyorsa yazma fırtınası. | `PDFKitCoordinator.swift:393-395` | **P1** | S |
| **Hiç in-feature onboarding yok** — tap-to-toggle-bar, long-press-image, quick-translate toggle, pinch-to-scale tamamen keşfedilemez. | `PDFReaderView.swift:69-72`, `:19` | P2 | M |
| Metin seçim popup'ı 1.0s gecikmeyle açılıyor (sluggish; 0.3-0.4s tipik). | `PDFKitCoordinator.swift:26` | P2 | S |
| `canPerformAction` her şeye `false` → düzenleme menüsünü ve Erişilebilirlik "Konuş"u da kapatıyor; ayrıca her `layoutSubviews`'ta menü-kaldırma recursion'ı ağır. | `CustomPDFView.swift:104-106,75-80` | P2 | M |

### 1.4 Çeviri Popup / Overlay (`TextSelectionPopup`, `QuickTranslationPopup`, `ImageSelectionPopup`)

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Kopyala/Kaydet onayı yok** — `showCopiedToast`/`showSavedToast` state'leri set ediliyor ama hiç render edilmiyor (ölü state). Kullanıcı kopyaladığını/kaydettiğini bilmiyor. | `TextSelectionPopup.swift:408`, `ImageSelectionPopup.swift:402-420` | **P1** | S |
| **Fotoğrafa kaydetme izni reddedilirse sessiz başarısızlık** — denied dalı boş; ayrıca yazma tamamlama/hata handler'ı yok. | `ImageSelectionPopup.swift:408-423` | **P1** | S |
| **Vurgu rengi swatch'larında seçili durum/etiket yok** — hangi renk aktif belli değil. | `TextSelectionPopup.swift:210-222` | P2 | S |
| **Popup pozisyonu bir kez hesaplanıp güncellenmiyor** — döndürme/klavye açılınca ekran dışına düşebilir; `UIScreen.main.bounds` kullanımı iPad çoklu pencerede yanlış. | `TextSelectionPopup.swift:48-51`, `QuickTranslationPopup.swift:42-57` | P2 | M |
| `QuickTranslationPopup`'ta `dismiss()` hiçbir şeye bağlı değil (kapatma butonu yok); ölü kod. | `QuickTranslationPopup.swift:341-349` | P2 | S |
| `QuickTranslationPopup` paylaşılan `LiquidGlassBackground` yerine gömülü `.white.opacity` gradyan kullanıyor → dark mode'da yıkanıyor. | `QuickTranslationPopup.swift:216-267` | P2 | S |
| Tam ekran görüntüde zoom'luyken pan/sürükleme yok (köşeyi inceleyemezsin). | `ImageSelectionPopupSupport.swift:29-61` | P2 | M |

### 1.5 Chat Arayüzü (`ChatView`, `MarkdownView`)
**En iyi inşa edilmiş ekranlardan biri** — `accessibilityIdentifier` kapsamı iyi, `reduceMotion` saygılı, 44pt hedefler. Ama Markdown render'ında kritik bir hata var.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **🔴 Kaynak atıf linkleri TIKLANMIYOR** — `[etiket](jump:N)` indigo+altı çizili render ediliyor ama dokunma hedefi yok ve `onNavigateToPage` hiç çağrılmıyor. RAG doküman-sohbetinin amiral özelliği (kaynağa atla) tamamen ölü. | `MarkdownView.swift:340-355` | **P0** | M |
| **Geniş tablolar kesiliyor** — yatay scroll yok, her sütun `maxWidth:.infinity`'ye sıkışıp kırpılıyor (akademik PDF'lerde ilaç/doz tabloları için kötü). | `MarkdownView.swift:427-477` | **P1** | M |
| **Başarısız mesaj için hata baloncuğu/retry yok** transkriptte. | `ChatView.swift` (mesaj akışı) | **P1** | M |
| **Akış durdurma/iptal butonu yok** — uzun üretim sırasında kullanıcı durduramıyor. | `ChatView.swift` (`isLoading`) | P2 | M |
| Öneri çipleri sadece `messages.count <= 1` iken görünür → ilk mesajdan sonra takip önerileri kalıcı kayboluyor. | `ChatView.swift:76` | P2 | M |
| `text.hashValue` parse cache anahtarı olarak kullanılıyor — stabil/çakışmasız değil; ayrıca `static var parseCache` view render'ından mutate ediliyor (data-race riski). | `MarkdownView.swift:21,60-66` | P2 | M |
| `MessageContent` ve `SuggestionChip` ölü kod. | `ChatView.swift:383-391,431-460` | P3 | S |

### 1.6 Quiz Özelliği (`QuizView`)

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Bitince yanlış cevap incelemesi yok** — sonuç ekranı sadece yüzde halkası + Kapat; soru-soru özet/retry/yeniden-dene yok. Quizlet/Anki standardının altında. | `QuizView.swift:295-347` | **P1** | M |
| **Hata ekranı çıkmaz sokak** — sadece "Kapat", retry yok (oysa `generateQuiz()` yeniden çalıştırılabilir). | `QuizView.swift:98-118` | **P1** | S |
| Quiz konfigürasyonu yok (soru sayısı, zorluk, sayfa aralığı sabit). | `QuizView.swift` | P2 | M |
| Görsel ilerleme çubuğu yok (sadece "1/10" metni). | `QuizView.swift:129` | P2 | S |
| Cevap dokununca anında kilitleniyor, yanlış-dokunma düzeltilemiyor. | `QuizView.swift:158,282` | P3 | S |

### 1.7 Notlar / Anotasyonlar (`NotebookView`, `NotebookDashboardView`, `NotebookCategoryView`, `AllFilesView`)
Kavramsal olarak en iyi tasarlanmış bölüm, ama navigasyon elle-yazılmış ve içerik Türkçe gömülü.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Navigasyon `NavigationStack` değil, tek `ZStack` içinde elle-yazılmış state makinesi** (`showingAllFiles`/`showingCategory`/`showingFileId` boolean'ları) → swipe-back, large-title, deep-link kaybı; kırılgan. En büyük yapısal risk. | `NotebookView.swift:12-100` | **P1** | L |
| **Boş-defter CTA'sı no-op** — yeni kullanıcı metin görüyor ama anotasyon oluşturma yolu yok (closure boş). | `NotebookView.swift:68-71` | **P1** | S |
| **İçerik tamamen gömülü Türkçe ve diakritik düşmüş** ("isaretlediginiz", "Vazgec", "gorunecek") — profesyonel durmuyor, İngilizce'yi de bozuyor. | `NotebookDashboardView.swift:52-318`, `NotebookCategoryView.swift:216-223,370-375` | **P1** | M |
| **Anotasyon kartları/satırları VoiceOver gruplaması yok + 44pt altı hedefler.** | `NotebookDashboardView.swift:124-179`, `NotebookCategoryView.swift:259-377` | **P1** | M |
| **Toplu anotasyon export/paylaş yok** (Highlights'ın amiral özelliği) — akademik kullanıcı için belirgin boşluk. | `NotebookDashboardView.swift` | P2 | M |
| İki ayrı arama çubuğu yeniden-yazılmış, Library'deki ile tutarsız. | `NotebookCategoryView.swift:159`, `AllFilesView.swift:67` | P2 | S |
| Stat kartları (Toplam/Favoriler/Notlar) tıklanamıyor — filtre beklenirdi. | `NotebookDashboardView.swift:73-99` | P3 | S |

### 1.8 Ayarlar (`SettingsView`, `DebugLogsView`)
En platform-yerel ekran (semantik renkler, iyi a11y), ama bir güvenlik ve birkaç eksiklik var.

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **⚠️ Debug Logs export'u tüm kullanıcılara açık** — public "Hakkında"dan erişilip tüm log dosyası paylaşılabiliyor. `#if DEBUG`/`isAdmin` ardına alınmalı. | `SettingsView.swift:177-194`, `DebugLogsView.swift:114-120` | **P1** | S |
| **Hesap yönetimi yok (hesap silme!)** — App Store 5.1.1(v) blokeri (§2 ile çapraz). Ayrıca cache/depolama yönetimi, varsayılan okuyucu ayarları, veri temizleme yok. | `SettingsView.swift` (tüm dosya) | **P0** (silme) / P2 | M |
| **Versiyon "1.0.0" hardcoded** — `Bundle`'dan okunmalı, sonraki sürümde yalan söyleyecek. | `SettingsView.swift:170` | P2 | S |
| Tema seçici var ama yaygın gömülü `.white` overlay'ler yüzünden light mode'a zorlayınca bozuk görünecek (§1.9 ile çapraz). | `SettingsView.swift:55-60` | P2 | S |

### 1.9 Navigasyon, Animasyon, Dark Mode, Erişilebilirlik (çapraz-kesen)

- **Navigasyon:** TabView (Kütüphane/Defterim/Ayarlar) standart. Ama Notebook'ta elle-yazılmış state-makinesi navigasyonu (§1.7 N1) platforma karşı savaşıyor.
- **Animasyonlar:** Giriş animasyonları ve glass efektleri cilalı; `reduceMotion` çoğu yerde saygılı. Ama `ShimmerModifier` `reduceMotion`'ı yok sayıp `repeatForever` çalışıyor (`ViewExtensions.swift:58-82`) — hareket-hassas kullanıcı için regresyon. **P2/S**
- **🔴 Dark/Light mode — kök neden:** `LiquidGlassBackground` tüm parıltı/stroke'ları `colorScheme`'den bağımsız `.white.opacity()` ile sabit (`LiquidGlassComponents.swift:17-60`). Bu **tek dosya**, light mode'da görünmez kenarlıklar ve aşırı-parlak parıltılar üreten kök neden — Auth, Library toolbar, kartlar, arama, banner'lar hepsi buradan besleniyor. Burada bir kez `colorScheme` dallanması ekle, çoğu light-mode bulgusu çözülür. **P1 / M**
- **Erişilebilirlik (önemli desen):** Chrome (toolbar, boş durumlar) güçlü etiketli; ama **içerik zayıf** — okuyucu chrome'u (`PDFReaderView.swift:475-722`), popup aksiyon butonları/renk swatch'ları, anotasyon satırları, tag çipleri (`TagViews.swift:34-35`) ve compact action butonları (`CompactActionControls.swift:14,41`) VoiceOver etiketi ve 44pt hedeflerden yoksun. **P1 / M**
- **Mantık hatası:** `OfflineBannerView.swift:171` — `!isConnected == false && ...` okunması imkânsız (yanlışlıkla doğru çalışıyor). **P2/S**

---

## 2. Kod Kalitesi — Mimari, Eşzamanlılık, Bellek, Hata Yönetimi

### 2.1 Eşzamanlılık & Data Race (en kritik teknik alan)

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **🔴 `GeminiService.shared` tek paylaşılan `chatSession` tutuyor** — tüm uygulama için TEK sohbet oturumu. İkinci doküman açılınca (veya arka plandaki `prepareChatAsync` sürerken yeniden açılınca) birincinin bağlamı eziliyor; kullanıcı **yanlış PDF'in bağlamıyla** konuşabiliyor, hatasız. | `GeminiChatService.swift:8`, `PDFReaderViewModel.swift:270` | **P0** | M |
| **`Annotation.safeForJSON` JSON round-trip "yeni bellek için" + detached PDFKit erişimi** = çözülmemiş off-main data race'in band-aid'i (gerçek çözüm değil). `EXC_BAD_ACCESS` yorumları gerçek bir threading hatasına işaret. | `Models.swift:285-340`, `PDFReaderViewModel.swift:246` | **P1** | M |
| **`Task.detached` uzun-ömürlü arka plan işlerinde `self`'i strong yakalıyor** (RAG indeksleme, chat hazırlık, görsel analizi) — view kapatılınca VM canlı kalıyor. Diğer yerlerde `[weak self]` doğru kullanılmış (tutarsız). | `PDFReaderViewModel.swift:238,285`, `ChatViewModel+ImageHandling.swift:206,269` | **P1** | S |
| C sinyal handler'ı içinde `Task { @MainActor }` + UserDefaults — async-signal-safe değil; crash raporu çoğu zaman flush olmadan ölür (güvenilmez telemetri). | `ErrorHandlingService+Crash.swift:46-50` | P2 | S |
| `renderAdjacentPages` skaler okumak için 3 kez ayrı MainActor hop'u (tutarsız snapshot riski). | `PDFReaderViewModel.swift:600-602` | P2 | S |

### 2.2 Bellek Yönetimi

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **MemoryDebugger init'te artırıyor ama deinit'te azaltmıyor** (`logDeinit` atlanıyor) → sızıntı dedektörü her VM için kalıcı false-positive; ayrıca `print()` projenin kendi SwiftLint kuralını ihlal ediyor. | tüm VM `deinit`leri, örn. `AuthViewModel.swift:46-53` | P2/P3 | S |
| **Blok-tabanlı NotificationCenter observer `removeObserver(self)` ile kaldırılmıyor** — closure uygulama ömrü boyunca sızıyor (`[weak self]` sayesinde VM sızmıyor ama closure kalıyor). Token saklanıp `removeObserver(token)` gerekir. | `AuthViewModel.swift:19-27,51` | P2 | S |
| Singleton cache'ler (`CacheService`/`PDFCacheService`/`PDFPageCacheService`) per-file state biriktiriyor; `cleanup()` güvenilir çağrılmazsa sınırsız büyüme riski. | `PDFReaderViewModel.swift:657` | P2 | M |

### 2.3 MVVM / Mimari Tutarlılık

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **`ChatViewModel` god object** — messaging + RAG orkestrasyon + görsel çıkarma/analiz batch + smart suggestion + sayfa-bağlam + indeksleme-state + regex sayfa-referans tespiti hepsi içinde. Görsel-analiz pipeline'ı bir servise taşınmalı. | `ChatViewModel+ImageHandling.swift:288-370` | **P1** | M |
| **Disk-cache dosya I/O ve UserDefaults kalıcılığı VM içinde** (yanlış katman); AI özet kaynağı 3 yere dağılmış (`files` dizisi, UserDefaults, Supabase) → drift riski. | `LibraryViewModel+Thumbnails.swift:92-162`, `+Summary.swift:80-94` | P2 | M |
| **⚠️ İstemci tarafı gömülü `isAdmin` e-postası** (`adminEmails = ["sergennunluu@gmail.com"]` — kullanıcının gerçek e-postasıyla uyuşmuyor, muhtemelen typo). İstemci admin kontrolü kolayca atlatılır; rol kontrolü sunucuda (RLS/claim) olmalı. | `Models.swift:35-38` | P2 | S |
| Extension-splitting deseni çoğunlukla tutarlı ama düzensiz: `+Sorting.swift` 16 satır (tek metot), `+Tags.swift` 21 satır — satır-sayısı için bölme. Churn'e değmez ama not. | `LibraryViewModel+*` | P3 | — |

### 2.4 Hata Yönetimi & State

`AppError` + `ErrorHandlingService` katmanı **gerçekten iyi tasarlanmış** (kapsamlı mapping, suppression penceresi, retry policy, presentation kuyruğu). Sorunlar lokalize:

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **Force-unwrap `UUID(uuidString: metadata.id)!`** upload-sonrası RAG yolunda (kod tabanındaki tek korumasız nokta; gerisi `guard let` ile korumalı). SwiftLint'te error seviyesi. | `LibraryViewModel+Upload.swift:131` | **P1** | S |
| **`signInWithApple()` üretimde discard edilmiş stub** (`_ = ASAuthorizationController(...)`, "gerçek uygulamada delegate set edersin" yorumu). Ya Apple sign-in başka yerde, ya gerçekten bozuk — doğrula. | `AuthViewModel.swift:93-105` | **P1** | S |
| **İndeksleme observer'ı, indeksleme BAŞARISIZ olsa bile dokümanı `.ready/indexed` işaretliyor** → sonraki sorgular sessizce boş/kısmi index'le çalışıyor. | `ChatViewModel.swift:211-216` | P2 | S |
| `NotebookViewModel` ham `error.localizedDescription` (İngilizce) gösteriyor Türkçe UI'da; `+FileAccess` hatayı loglamadan yutuyor. | `NotebookViewModel.swift:246,357`, `LibraryViewModel+FileAccess.swift:10-13` | P2 | S |
| Auth state'in 4 yazarı var (Combine sink + 3 imperatif set) — yarış riski; tek kaynak (Combine) yeterli. | `AuthViewModel.swift:29-81` | P2 | S |
| `filteredFiles`/`filteredAnnotations` her render'da O(n log n) yeniden hesaplanıyor (ölçekte ısırır). | `LibraryViewModel.swift:74-112`, `NotebookViewModel.swift:135-196` | P2 | S |
| Liste satırlarında her erişimde yeni `DateFormatter` alloc'lanıyor (pahalı). | `NotebookViewModel.swift:412-424`, `Models.swift:145-150` | P3 | S |

---

## 3. Özellik Analizi & Rakip Karşılaştırma

### 3.1 Mevcut özellikler — tam mı yarım mı?

| Özellik | Durum | Not |
|---|---|---|
| PDF görüntüleme (PDFKit) | ✅ Tam | Pre-render, cache, koruma sınırları iyi |
| Metin seçimi + vurgu/altçizgi/üstçizgi | ✅ Tam | Yüzde-tabanlı koordinat (cihaz bağımsız) — iyi |
| AI çeviri popup | 🟡 Yarım | Çalışıyor ama kapatma yok, onay yok, pozisyon güncellenmiyor |
| AI sohbet (RAG) | 🟡 Yarım | **Kaynak atıf linkleri ölü (P0)**, tek paylaşılan oturum (P0), tablo kırpma |
| Quiz | 🟡 Yarım | Yanlış-cevap incelemesi/retry/konfig yok |
| Anotasyon defteri | 🟡 Yarım | Dashboard iyi ama navigasyon elle-yazılmış, toplu export yok |
| Klasör/etiket organizasyonu | 🟡 Yarım | İç-içe klasör ve çoklu seçim yok |
| Doküman içi arama | 🔴 Yarım | Sonuç listesi/parçacığı yok |
| Görsel çıkarma + Vision analizi | ✅ Tam | İyi |
| Offline/sync | 🟡 Yarım | Sync queue retry sayacı bozuk (§4) |
| Okuma ilerlemesi senkronu | 🟡 Yarım | Throttle yok, senkron döngüsü riski |

### 3.2 Rakiplerle karşılaştırma

- **vs PDF Expert:** Çoklu-seçim/toplu işlem, gelişmiş arama (sonuç listesi), PDF düzenleme/imza, sayfa küçük resim navigasyonu eksik. CorioScan'in artısı: yerleşik AI sohbet/çeviri/quiz.
- **vs Highlights:** Highlights'ın amiral özelliği **toplu vurgu export'u** (Markdown/Word'e) — CorioScan'de notebook seviyesinde yok. CorioScan'in artısı: RAG sohbet ve otomatik kategorizasyon.
- **vs Zotero iOS:** Zotero'nun referans/atıf yönetimi, koleksiyon senkronu, PDF metadata/DOI yakalama, alıntı oluşturma (Vancouver vb.) çok daha derin — **bu Sergen'in akademik iş akışı için kritik bir boşluk** (CLAUDE.md: AJEM, Vancouver). CorioScan'in artısı: doküman-içi AI sohbet.

### 3.3 Eksik / iyileştirilebilir kritik özellikler
- **Tıklanabilir kaynak atıfları** (zaten yarım yazılmış — P0 düzeltme).
- **Sayfa küçük-resim/TOC navigasyonu** okuyucuda.
- **Toplu vurgu/not export'u** (Markdown, Word, Vancouver atıf) — akademik kullanıcı için.
- **Çoklu-seçim** kütüphanede.
- **Doküman-içi arama sonuç listesi.**
- **Quiz inceleme modu + flashcard/SRS** (Anki tarzı tekrar).

---

## 4. Performans

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **PDF metin çıkarma senkron + döngü içinde regex compile + `while contains("  ")` (kuadratik)** — 300 sayfalık akademik PDF'te çok-saniyelik takılma; main thread blokajı. Regex'leri static lazy'ye taşı, off-main çalıştır, tek regex pass kullan. | `PDFTextExtractor.swift:50-94,159,239-241` | **P1** | M |
| **Embedding indeksleme tamamen seri + her chunk arası 100ms sleep** — yüzlerce chunk → dakikalarca ilk-chat gecikmesi. Oysa paralel `getBatchEmbeddings` (5'erli) zaten var ama indexer kullanmıyor. Bunu kullan → büyük kazanç. | `RAGService.swift:142-182` vs `RAGEmbeddingService.swift:77-105` | **P1** | M |
| Legacy chat init'te tüm doküman (`prefix(100000)` karakter) Gemini'ye gidiyor — token/maliyet/gecikme. RAG yolu doğru; legacy sadece fallback olmalı. | `GeminiChatService.swift:25` | P2 | S |
| HyDE embedding hesaplanıp atılıyor ("Kullanım dışı") — boşa Gemini çağrısı. | `RAGService.swift:410-412` | P3 | S |
| Disk cache sadece ilk 3 sayfa; hızlı geri-scroll re-render. | `CacheService.swift:104,126` | P2 | S |

**Pozitifler:** `Image+Optimized` ImageIO downsampling (bellek-verimli, off-main); memory-warning observer tüm cache'leri flush ediyor; `PDFService` aşırı-boyut/şifreli/boş PDF'e karşı guard'lı (OOM koruması); vektör+BM25 `async let` ile paralel.

---

## 5. Offline Çalışma

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **🔴 Sync queue retry sayacı asla artmıyor (value-copy hatası)** — `if var op = ...first { op.retryCount += 1 }` kopyayı mutate ediyor, geri yazılmıyor. `maxRetries` asla tetiklenmez; başarısız ops sonsuza dek her ağ-dönüşünde backoff'suz tekrar dener. Retry/backoff tasarımı çalışmıyor. Index üzerinden mutate et + persist + backoff. | `SyncQueue.swift:186-194` | **P1** | M |
| Conflict resolution yok — last-write-wins; iki cihazda offline düzenlenen anotasyon sessizce eziliyor (`reading_progress` upsert'le güvende ama anotasyon değil). | `SyncQueue.swift:249-298` | P2 | M |
| Offline dosya yükleme desteklenmiyor (`notSupported` throw) — MVP kabul edilebilir ama enum case'i kafa karıştırıcı. | `SyncQueue.swift:232-233` | P2 | S |

**Pozitifler:** Queue UserDefaults'a persist edip launch'ta yeniden yüklüyor; `networkDidBecomeAvailable`'da işliyor; `NetworkMonitor` temiz tek-kaynak (`isExpensive`/`isConstrained` farkında).

---

## 6. App Store Hazırlığı

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **🔴 `PrivacyInfo.xcprivacy` privacy manifest YOK** — Apple Mayıs 2024'ten beri yüklemede reddediyor. UserDefaults (`CA92.1`), FileTimestamp (`C617.1`) required-reason API'leri + toplanan veri tipleri (e-posta/ad, PDF/chat/anotasyon içeriği, Gemini'ye gönderilen doküman metni) deklare edilmeli. SPM paketlerinin (Supabase, GoogleGenerativeAI) kendi manifestlerini taşıdığını doğrula. | (dosya yok) | **P0** | M |
| **🔴 Uygulama içi hesap silme YOK** — Kılavuz 5.1.1(v). Settings'e "Hesabı Sil" + service-role Edge Function (FK `ON DELETE CASCADE` ile temizler) + Keychain temizliği gerekiyor. | `SupabaseAuthService.swift` (sadece `signOut`) | **P0** | M |
| **Export-compliance anahtarı eksik** — `ITSAppUsesNonExemptEncryption` yok; her TestFlight/submit'te şifreleme anketi çıkar. `<false/>` ekle. | `Info.plist` | **P1** | S |
| **Sign in with Apple entitlement repoda yok** — `pbxproj`'da `applesignin` referansı sıfır. Google sunuluyorsa Apple Sign-In zorunlu (4.8/5.1). Xcode projesinde entitlement'ın gerçekten olduğunu doğrula — yoksa hem işlev hem review blokeri. | `AuthView`/`AuthViewModel`, pbxproj | **P1** | S |
| **3. parti crash reporting yok** (Crashlytics/Sentry yok). Üretimde crash'lere kör kalırsın; en azından MetricKit (SDK'sız, gizlilik-dostu) ekle. | `ErrorHandlingService+Crash.swift` | P2 | M |
| OAuth callback token'ları URL fragment'tan elle parse ediyor (loglama dikkatli — değer loglanmıyor, iyi). | `PolyglotReaderApp.swift:31-65` | P3 | — |

---

## 7. Güvenlik & Gizlilik

| Bulgu | Kanıt | Öncelik | Efor |
|---|---|---|---|
| **⚠️ GÜVENLİK: Gemini API anahtarı cihazda + URL'de düz metin** — `Config.plist` IPA'ya gömülü; embedding çağrısı `?key=...` query string'inde (proxy/log/crash'e sızabilir). XOR obfuscation (bundleId+versiyon'dan türeyen anahtar) dakikalar içinde geri çözülür. **Web zaten Edge Function ile doğru yapıyor — iOS yapmıyor.** Tüm Gemini çağrılarını (chat stream, analiz, embedding) Supabase Edge Function ardına al. **Tek en değerli güvenlik değişikliği.** | `Config.swift:38-44,114-137`, `GeminiConfig.swift:7`, `RAGEmbeddingService.swift:253` | **P1** | L |
| **⚠️ Sertifika pinning fiilen no-op** — pinler Info.plist'te yok, `pinsByHost` boş; Release'te zorlanan host'lar yalnız default trust'tan geçiyor. Ya SPKI hash'leri (yedek pin'le) ekle ya ölü karmaşıklığı kaldır. **KRİTİK:** pin eklersen Supabase cert rotasyonunda uygulamayı kilitlememek için intermediate CA'ya pinle veya yedek pin koy. | `SecurityManager.swift:358-387`, `+Pinning.swift:42-49` | **P1** | S |
| Config bütünlük hash'i placeholder (`REPLACE_WITH_CONFIG_SHA256`) → tamper tespiti kapalı. Anahtar sunucuya taşınınca gereksiz; kaldır. | `SecurityManager.swift:243-252` | P1 | S |
| ⚠️ Supabase oturumu cihaz-kilidi koruması olmadan saklanıyor (`accessControl = .none`); biyometrik kapı yok. Tıbbi PDF'ler hassas olabilir → opsiyonel biyometrik kilit sun. | `SecurityManager.swift:180`, `KeychainService.swift:60` | P2 | S |
| Jailbreak "tespiti" sandbox dışına (`/private/jailbreak_check.txt`) yazıyor — App Review statik analizinin işaretlediği davranış; değeri düşük, kaldır. | `SecurityManager.swift:347-354` | P2 | S |

**Pozitifler:** **Log sanitizasyonu mükemmel** — JWT/bearer/token/apikey ve **e-postalar** loglanmadan önce maskeleniyor, embedding/base64 stripleniyor (`LoggingService.swift:77-181`). Ham hasta verisi loglaması bulunmadı. ATS sıkı; `Config.plist` gitignore'lu; kaynak kodda hardcoded secret yok; ephemeral URLSession (cache/cookie kapalı); 15dk arka plan force-logout + zamanlı token refresh düşünceli.

> **Doğrulama gereken (repoda görünmeyenler):** (1) Canlı Supabase RPC adları — kod `match_chunks`/`search_chunks_bm25` çağırıyor ama CLAUDE.md `match_document_chunks_v2`/`hybrid_search_chunks` diyor; uyuşmazsa hibrit arama sessizce geniş-chunk fallback'e düşüp cevap kalitesini bozuyor (`SupabaseService+RAG.swift:110,127`). (2) Apple Sign-In entitlement. (3) Google reversed-client-id URL şeması gerekip gerekmediği.

---

## 8. Ek Özellik Önerileri & Monetizasyon

### 8.1 Etkileyici yenilikler (akademik/tıp odaklı — Sergen'in profili)
- **Tıklanabilir kaynak atıfları + sayfa highlight** (zaten yarım — önce onu bitir): AI cevabındaki her iddia, kaynak sayfaya atlayan link olsun. RAG ürününün vitrin özelliği.
- **Otomatik atıf/referans çıkarma (Vancouver)**: PDF'in DOI/PMID'sini yakalayıp tek dokunuşla Vancouver atıfı üret — Zotero boşluğunu kapatır, Sergen'in AJEM iş akışına doğrudan değer.
- **Toplu vurgu/not export'u**: Markdown/Word/PDF olarak; "literatür özeti" üretimi.
- **AI "literatür sentezi"**: Birden fazla PDF üzerinde çapraz-doküman sohbet (mevcut RAG tek-doküman; çoklu-doküman koleksiyonu güçlü olur).
- **Flashcard/SRS modu**: Quiz'i Anki-tarzı aralıklı tekrara çevir — sınav/doçentlik çalışması için yapışkan özellik.
- **Sesli okuma (TTS) + dinleme modu**: Uzun makaleleri yürürken dinleme.

### 8.2 UX'i üst seviyeye çıkaracaklar
- In-feature onboarding/coachmark katmanı (tap/long-press/pinch jestleri için).
- Sayfa küçük-resim navigasyon şeridi + TOC.
- Okuyucu ayarları (scroll modu, tema, varsayılan zoom).
- iPad çoklu-pencere / Split View desteği (mevcut `UIScreen.main` kullanımları bunu bozuyor).

### 8.3 Monetizasyon fırsatları
- **Freemium + abonelik (önerilen):** Ücretsiz = sınırlı PDF/ay + temel okuma; **Pro (aylık/yıllık)** = sınırsız AI sohbet/quiz/çeviri, çoklu-doküman sentezi, atıf export. AI maliyeti (Gemini) kullanım-bazlı olduğu için abonelik doğal eşleşme. **Not:** AI çağrıları sunucuya taşınınca (§7) kota/rate-limit'i abonelik katmanına bağlamak da mümkün olur.
- **Akademik/kurumsal lisans:** Üniversite/hastane grupları için toplu lisans (Sergen'in ağı buna uygun).
- **Maliyet uyarısı:** Cihazda anahtarla freemium yapılamaz (kota hırsızlığı) — monetizasyon, §7'deki sunucu-tarafı taşımaya bağımlı. Önce o, sonra paywall.

---

## 9. Önceliklendirilmiş Yol Haritası

### 🔴 Sprint 0 — App Store Blokerleri + P0 Hatalar (gönderimden ÖNCE zorunlu)
| # | İş | Öncelik | Efor |
|---|---|---|---|
| 1 | `PrivacyInfo.xcprivacy` manifest + Nutrition Label | P0 | M |
| 2 | Uygulama içi hesap silme (Settings + Edge Function) | P0 | M |
| 3 | Chat kaynak atıf linklerini tıklanabilir yap (`onNavigateToPage` bağla) | P0 | M |
| 4 | Tek paylaşılan `chatSession`'ı per-file yap | P0 | M |
| 5 | Gemini anahtarını Edge Function ardına taşı (güvenlik) | P0/P1 | L |
| 6 | `ITSAppUsesNonExemptEncryption=false` + Apple Sign-In entitlement doğrula | P1 | S |

### 🟠 Sprint 1 — Kullanıcıyı Yaralayan P1 Hatalar
| # | İş | Efor |
|---|---|---|
| 7 | Sync queue retry value-copy hatası | M |
| 8 | `LiquidGlassBackground` light-mode kök fix + PDF beyaz arka plan | M |
| 9 | Doküman içi arama sonuç listesi/parçacığı | L |
| 10 | Quiz inceleme modu + hata retry | M |
| 11 | Kopyala/Kaydet onay toast'ları + izin-reddi mesajı | S |
| 12 | Sayfa-senkron döngüsü + ilerleme throttle | S→M |
| 13 | Embedding indekslemeyi `getBatchEmbeddings`'e geçir (perf) | M |
| 14 | PDF metin çıkarma off-main + regex hoist (perf) | M |
| 15 | Force-unwrap `UUID(...)!` düzelt; `signInWithApple` stub'ını çöz | S |
| 16 | Apple Sign-In hata mesajı + buton disable + terms linkleri | S |
| 17 | Geniş tablo yatay scroll (Markdown) | M |
| 18 | Notebook boş-CTA no-op + içerik lokalizasyonu (diakritik) | M |
| 19 | Debug Logs export'unu `#if DEBUG`/admin ardına al | S |
| 20 | Okuyucu/popup VoiceOver etiketleri + 44pt hedefler | M |

### 🟡 Sprint 2 — Yapısal & Kalite (P2)
- Notebook navigasyonunu `NavigationStack`'e taşı (L)
- `ChatViewModel` god object'i ayrıştır (görsel-analiz servisi) (M)
- Çoklu-seçim/toplu işlem kütüphanede (L)
- Flip jestini kaldır/affordance ekle (M)
- İç-içe klasör + ikon seçimi (M)
- Sertifika pinning'i tamamla veya kaldır (S)
- Crash reporting (MetricKit) (M)
- İndeksleme-başarısızlık state'i, raw error mesajları, sunucu admin kontrolü (S–M her biri)

### 🟢 Sprint 3 — Büyüme & Farklılaşma (P3 + yeni özellikler)
- Tıklanabilir atıf üzerine: Vancouver atıf export, çoklu-doküman sentezi
- Toplu vurgu/not export (Markdown/Word)
- Flashcard/SRS, TTS, sayfa thumbnail/TOC navigasyon
- In-feature onboarding katmanı
- Freemium/abonelik paywall (sunucu-taşıma tamamlandıktan sonra)

---

## 10. Genel Değerlendirme

CorioScan iOS, **mühendislik açısından olgun ama ürün açısından yarım-bitik** bir uygulama. Servis katmanı, hata yönetimi ve güvenlik *altyapısı* (sanitizasyon, retry, cache) profesyonel seviyede — Phase D hardening'in meyveleri görülüyor. Buna karşılık:

1. **Vitrin AI özelliği (tıklanabilir kaynak atıfları) sessizce ölü** ve **paylaşılan chat oturumu bağlamı bozuyor** — bunlar bir RAG doküman-sohbet ürünü için varoluşsal.
2. **App Store'a bugün gönderilse 3 nedenle reddedilir** (privacy manifest, hesap silme, export compliance).
3. **Light mode ve lokalizasyon yarım uygulanmış** — tek kök fix (`LiquidGlassBackground`) ve tutarlı `.localized` kullanımı çoğunu çözer.
4. **Güvenlik altyapısı var ama anahtar cihazda** — en değerli iş, Gemini'yi sunucuya taşımak (bu aynı zamanda monetizasyonun da önkoşulu).

Sprint 0 + Sprint 1 tamamlandığında uygulama hem gönderilebilir hem de gerçekten "akıllı PDF okuyucu" vaadini tutar hâle gelir. Sprint 3'teki akademik özellikler (atıf export, çoklu-doküman sentezi, SRS) ise CorioScan'i Zotero+PDF Expert+Quizlet kesişiminde benzersiz bir konuma taşıyabilir — ki bu tam olarak hedef kullanıcının (akademisyen/klinisyen) iş akışıdır.
