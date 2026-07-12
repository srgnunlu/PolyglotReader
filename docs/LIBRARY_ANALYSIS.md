# Kütüphane ve Klasörleme Sistemi — Kapsamlı Analiz Raporu

> **UYGULAMA DURUMU (2026-07-12): PLAN TAMAMLANDI.**
> Faz 1 (7/7) ✅ · Faz 2 (8/8) ✅ · Faz 3 (7/9) ✅ · Faz 4 (8/8) ✅
> Bilinçli atlananlar: 3.8 sayfalama (mevcut kütüphane boyutunda gereksiz; içerik aramasını
> bozacağından 500+ dosyada sunucu taraflı aramayla birlikte ele alınmalı) ve 3.9 toolbar
> `.searchable` dönüşümü (LiquidGlass tasarım diliyle çelişir, önerilmedi).
> Migration'lar canlıda: add_folder_icon, add_favorites_pagecount_content_search, add_files_soft_delete.

> Tarih: 2026-07-11 · Branch: `feature/ui-fixes-notebook-library-reader`
> Kapsam: `Views/Library/*`, `ViewModels/LibraryViewModel*`, `Services/FolderIconStore.swift`, `Services/Supabase/SupabaseFileService.swift`, `SupabaseService+TagsFolders.swift`, `SupabaseDatabaseService.swift`, `Views/Components/CompactFilterBar.swift`, thumbnail/cache servisleri.
> Not: Bu rapor salt analizdir — hiçbir kod değiştirilmedi.

---

## YÖNETİCİ ÖZETİ (TL;DR)

Kütüphane sayfası görsel olarak **iyi seviyede** (LiquidGlass tasarım dili, skeleton'lar, zoom geçişi, konfeti, erişilebilirlik). Ancak **klasörleme sistemi yarım kalmış durumda** ve üç ciddi işlevsel hata var:

1. **🔴 İç içe klasörler UI'da görünmüyor** — alt klasör oluşturulabiliyor ama bir klasörün içine girince alt klasörler asla render edilmiyor. Alt klasöre konan dosyalara UI'dan erişim yok.
2. **🔴 Klasör kartları her zaman "0 dosya" gösteriyor** — `getFolders` sorgusu `fileCount`'u hiç doldurmuyor.
3. **🔴 Klasör silme onayı yok** — tek uzun basma + "Sil" ile klasör anında siliniyor (içindeki dosyalar sessizce ana klasöre düşüyor).

Ayrıca **dosya/klasör yeniden adlandırma, paylaşma, favoriler, "son açılan" sıralaması, drag & drop ve dışarıdan PDF alma (share extension / "Open in")** tamamen eksik. Rakiplerle (PDF Expert, GoodNotes, Files) karşılaştırınca en büyük boşluklar bunlar.

---

## 1. KÜTÜPHANE SAYFASI UI

### 1.1 Genel Yapı

- Giriş noktası: [LibraryView.swift:21](PolyglotReader/Views/Library/LibraryView.swift#L21) — `NavigationStack` + `ZStack` (gradient arka plan) + `ScrollView`/`LazyVStack`.
- Üç durum ayrımı doğru kurulmuş: [LibraryView.swift:106-112](PolyglotReader/Views/Library/LibraryView.swift#L106) → `isLoading` → `LoadingView`, tamamen boş → `EmptyLibraryView`, aksi halde içerik.
- İçerik sırası: arama çubuğu (aktifse) → breadcrumb → `CompactFilterBar` → klasör bölümü → dosya grid/list.

**Güçlü yanlar**
- Tasarım dili tutarlı: `DSColor`, `DSFont`, `DSMotion`, `dsGlass` tasarım sistemi tokenları kullanılıyor ([LibraryView.swift:345-368](PolyglotReader/Views/Library/LibraryView.swift#L345)).
- iOS 18 zoom geçişi: karta dokununca okuyucu karttan "zoom out" ile açılıyor, iOS 17'de zarif fallback var ([LibraryView.swift:484-502](PolyglotReader/Views/Library/LibraryView.swift#L484)).
- Scroll transition: kartlar viewport kenarında hafifçe sönümleniyor, Reduce Motion'a saygılı ([LibraryView.swift:506-516](PolyglotReader/Views/Library/LibraryView.swift#L506)).
- İlk yükleme konfetisi — hoş bir "kazanılmış an" ([LibraryView.swift:72-89](PolyglotReader/Views/Library/LibraryView.swift#L72)).
- Erişilebilirlik ciddiyetle yapılmış: `accessibilityLabel/Hint/Identifier`, 44pt dokunma alanları, `reduceMotion` kontrolleri her animasyonda.

**Zayıf yanlar**
- **Toolbar kalabalık**: sağ üstte 4 buton (seçim, arama, klasör, +) + solda 2 buton. iPhone'da dar ekranda başlıkla yarışıyor. Rakipler (Files, PDF Expert) arama için native `.searchable`, diğerleri için tek "⋯" menüsü kullanır.
- **Arama native değil**: özel `LiquidGlassSearchBar` + toggle butonu ([LibraryView.swift:195-223](PolyglotReader/Views/Library/LibraryView.swift#L195)). `.searchable` kullanılsa pull-down arama, otomatik iptal, klavye yönetimi bedavaya gelirdi.
- **Grid sabit 2 sütun** ([LibraryView.swift:268-271](PolyglotReader/Views/Library/LibraryView.swift#L268)) — iPad'de/yatayda devasa kartlar. `.adaptive(minimum:)` yok, size class'a tepki yok.
- **Lokalizasyon karışık**: `"library.title".localized` gibi anahtarlar ile sabit Türkçe metinler ("Seçili … silinsin mi?", "Klasöre Taşı", "Tümü", "… seçili" — [LibraryView.swift:120-159](PolyglotReader/Views/Library/LibraryView.swift#L120)) aynı dosyada. `FolderViews.swift` neredeyse tamamen hardcoded.
- **Swipe aksiyonları yok**: liste `List` değil `LazyVStack` ([LibraryView.swift:307-333](PolyglotReader/Views/Library/LibraryView.swift#L307)) olduğundan `swipeActions` kullanılamıyor. Listede sola kaydırıp silme/taşıma — iOS kullanıcısının kas hafızası — mevcut değil.
- Hata mesajları `viewModel.errorMessage`'a yazılıyor ama LibraryView bunu **hiçbir yerde göstermiyor** (banner/alert bağlantısı yok; ErrorHandlingService kendi banner'ını basıyorsa bile `errorMessage` ölü durumda).

### 1.2 Liste / Grid Görünümü

- Grid kartı: [PDFCardView.swift:63-231](PolyglotReader/Views/Library/PDFCardView.swift#L63) — thumbnail (130pt) + isim + tarih/boyut + ilk 3 etiket rozeti. Kaliteli görünüm.
- Liste satırı: [PDFCardView.swift:234-362](PolyglotReader/Views/Library/PDFCardView.swift#L234) — 50×68 thumbnail + isim + boyut·tarih.
- Flip kart: [FlippablePDFCardView.swift](PolyglotReader/Views/Library/FlippablePDFCardView.swift) — sparkle butonuyla 3D dönüp AI özetini gösteriyor. Yaratıcı ve ayırt edici bir özellik. `compositingGroup` ile optimize edilmiş ([FlippablePDFCardView.swift:41](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L41)).

**Sorunlar**
- **Liste satırında etiketler görünmüyor** — grid kartında var ([PDFCardView.swift:201-226](PolyglotReader/Views/Library/PDFCardView.swift#L201)), listede yok. Liste modunu seçen kullanıcı etiket bilgisini kaybediyor.
- **Liste satırında "Klasöre Taşı" context menüsü yok** — grid'de var ([PDFCardView.swift:24-44](PolyglotReader/Views/Library/PDFCardView.swift#L24)), listede sadece "Sil" ([PDFCardView.swift:249-255](PolyglotReader/Views/Library/PDFCardView.swift#L249)). Görünüm modları arası özellik eşitsizliği.
- **Sayfa sayısı / okuma ilerlemesi kartlarda yok** — `reading_progress` tablosu mevcut ama kütüphane hiç sorgulamıyor. GoodNotes/Books'taki "%42 okundu" çubuğu ve "kaldığın yerden devam" yok.
- Flip kartın doc yorumu bayat: "Long press + drag ile" diyor ([FlippablePDFCardView.swift:5](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L5)) ama gerçek tetikleyici sparkle butonu.
- Flip kartta özet üretimi başarısız olursa `isGeneratingSummary` hiç sıfırlanmıyor → arka yüz **sonsuz "Özet hazırlanıyor…"** durumunda kalıyor ([FlippablePDFCardView.swift:43-47](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L43) — sadece `true` yapılıyor, hata yolunda `false` yok).
- `detectCategory(from:)` özet metninde kelime avcılığı yapıyor ([FlippablePDFCardView.swift:310-335](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L310)) — oysa AI etiketleme zaten `file.aiCategory` üretiyor ([LibraryViewModel+Upload.swift:194](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L194)). Var olan gerçek veri yerine kırılgan bir sezgisel kullanılıyor.

### 1.3 Thumbnail Kalitesi ve Yükleme

- Üretim: 600×800 px, JPEG 0.8 ([PDFPageRenderer.swift:48-57](PolyglotReader/Services/PDF/PDFPageRenderer.swift#L48)) — retina için yeterli, yakın zamanda 300px'ten yükseltilmiş. ✅
- Üç katmanlı cache: NSCache (100 adet/50MB, [CacheService.swift:13-17](PolyglotReader/Services/CacheService.swift#L13)) → disk (`pdf_thumbnail_cache/<id>_v2.jpg`, [LibraryViewModel+Thumbnails.swift:129-134](PolyglotReader/ViewModels/LibraryViewModel+Thumbnails.swift#L129)) → yeniden üretim.
- `ThumbnailImageProvider` decode edilmiş `UIImage`'ı paylaşıyor; scroll'da tekrar JPEG decode maliyeti sıfırlanmış ([ThumbnailImageProvider.swift:12-25](PolyglotReader/Views/Library/ThumbnailImageProvider.swift#L12)). İyi mühendislik. ✅
- Skeleton durumu reaktif: `pendingThumbnailIds` seti kart iskeletlerini sürüyor ([LibraryViewModel+Thumbnails.swift:10-12](PolyglotReader/ViewModels/LibraryViewModel+Thumbnails.swift#L10)).

**Sorunlar**
- **🟠 Thumbnail üretmek için PDF'in TAMAMI indiriliyor** ([LibraryViewModel+Thumbnails.swift:47-55](PolyglotReader/ViewModels/LibraryViewModel+Thumbnails.swift#L47)): 50 MB'lık bir kitap için kapak üretmek 50 MB indirme demek. Yeni cihaz/yeniden kurulumda tüm kütüphane baştan iner. Doğru çözüm: thumbnail'i yükleme anında üretip Supabase Storage'a küçük bir JPEG olarak koymak, listede sadece onu indirmek.
- **🟠 Sınırsız eşzamanlılık**: `loadFiles` tüm dosyalar için aynı anda thumbnail task'ı başlatıyor ([LibraryViewModel+Loading.swift:30-32](PolyglotReader/ViewModels/LibraryViewModel+Loading.swift#L30)). 40 dosyalık taze kurulumda 40 paralel tam-PDF indirmesi → ağ boğulması, bellek zirvesi. TaskGroup ile 3-4'lük eşzamanlılık sınırı gerekli. ("Lazy" yorumu yanıltıcı — görünürlük değil, liste yüklemesi tetikliyor.)
- Thumbnail verisi `files` dizisindeki modelde tutuluyor (`thumbnailData: Data?`) — yüzlerce dosyada hepsi bellekte. NSCache'in tahliye avantajı model dizisi için geçerli değil.

### 1.4 Sıralama, Arama, Filtre

- Sıralama: Tarih/İsim/Boyut pill'leri, yön toggle'ı, haptic ([CompactFilterBar.swift:28-43](PolyglotReader/Views/Components/CompactFilterBar.swift#L28), [LibraryViewModel+Sorting.swift:7-14](PolyglotReader/ViewModels/LibraryViewModel+Sorting.swift#L7)). ✅
- **"Son açılan" sıralaması yok** — kullanıcı isteği listende de vardı; `reading_progress.updated_at` verisi DB'de hazır ama modele hiç taşınmıyor.
- Arama: isim + etiket adı, 300ms debounce ([LibraryViewModel.swift:149-171](PolyglotReader/ViewModels/LibraryViewModel.swift#L149)). Debounce doğru kurulmuş. Ancak **içerik/özet araması yok** — RAG altyapısı (BM25 + vektör) mevcutken kütüphane araması bundan hiç faydalanmıyor. "Geçen hafta okuduğum sepsis makalesi" tarzı arama rakip fark yaratacak fırsat.
- Etiket filtresi: popover + medium/large detent sheet, dosya sayılı satırlar, "Temizle" ([CompactFilterBar.swift:125-189](PolyglotReader/Views/Components/CompactFilterBar.swift#L125)). OR mantığı (`isDisjoint`, [LibraryViewModel.swift:89-94](PolyglotReader/ViewModels/LibraryViewModel.swift#L89)) — AND seçeneği yok ama OR makul varsayılan. ✅
- Filtre sonucu boş vs klasör boş durumları ayrıştırılmış ([LibraryView.swift:239-255](PolyglotReader/Views/Library/LibraryView.swift#L239)) — ince bir detay, güzel. ✅

### 1.5 Empty / Loading / Refresh

- `EmptyLibraryView`: nefes alan ikon animasyonu, net CTA, Reduce Motion desteği ([LibraryViewComponents.swift:38-112](PolyglotReader/Views/Library/LibraryViewComponents.swift#L38)). ✅
- `LoadingView`: **spinner-only** ([LibraryViewComponents.swift:4-35](PolyglotReader/Views/Library/LibraryViewComponents.swift#L4)). Kart şeklinde skeleton grid gösterilse algılanan hız artardı — skeleton bileşeni zaten mevcut (`SkeletonBlock`).
- Pull-to-refresh: `.refreshable` ile dosya+klasör+etiket yeniliyor ([LibraryView.swift:47-50](PolyglotReader/Views/Library/LibraryView.swift#L47)). ✅

### 1.6 Çoklu Seçim

- Toggle → alt action bar (`safeAreaInset`): "Tümü", sayaç, taşı, sil ([LibraryView.swift:114-189](PolyglotReader/Views/Library/LibraryView.swift#L114)). Toplu sil onaylı, toplu taşı `confirmationDialog` ile. Temel akış sağlam. ✅
- Eksikler: uzun basarak seçim moduna girme (iOS standardı), sürükleyerek çoklu seçim, seçim modunda **toplu etiketleme** yok, taşıma dialog'u yalnız kök klasörleri listeliyor (bkz. §3).

### 1.7 Dark Mode / Animasyon / Profesyonellik

- Renkler ağırlıkla adaptif (`Color(.secondarySystemBackground)`, `.primary/.secondary`, DS tokenları). LiquidGlass'taki sabit `.white.opacity(...)` parlama katmanları ([FolderViews.swift:155-178](PolyglotReader/Views/Library/FolderViews.swift#L155)) koyu temada hafif "gri film" etkisi yaratabilir — cihazda kontrol edilmeli.
- Animasyon disiplini iyi: spring'ler, `contentTransition(.numericText)` upload yüzdesinde ([LibraryViewComponents.swift:154](PolyglotReader/Views/Library/LibraryViewComponents.swift#L154)), haptic'ler (`dsHaptic`, `DSHaptics.selection`).
- Genel profesyonellik: **görsel katman 8/10, işlevsel derinlik 5/10**. Görünüş "premium okuyucu" diyor; klasör/dosya yönetimi "MVP" seviyesinde.

---

## 2. KLASÖRLEME SİSTEMİ

### 2.1 Oluşturma — iyi durumda

`CreateFolderSheet` ([FolderViews.swift:322-447](PolyglotReader/Views/Library/FolderViews.swift#L322)): isim + üst klasör seçici + 16 SF Symbol ikonu + 8 renk + canlı önizleme. Boş isim engelli. Mevcut klasördeyken üst klasör otomatik seçiliyor ([FolderViews.swift:416-420](PolyglotReader/Views/Library/FolderViews.swift#L416)). Rakip seviyesinde bir oluşturma akışı. ✅

Sorunlar:
- Üst klasör picker'ı `viewModel.folders`'ı listeler — bu **yalnız mevcut seviyenin klasörleri** ([LibraryViewModel+Loading.swift:56](PolyglotReader/ViewModels/LibraryViewModel+Loading.swift#L56)). Kökteyken alt-alt klasöre klasör açamazsın; hiyerarşinin tamamı hiçbir yerde listelenmiyor.
- Aynı isimli klasörde DB `UNIQUE(user_id, parent_id, name)` hatası ham şekilde `errorMessage`'a düşer; kullanıcıya "Bu isimde klasör zaten var" gibi anlaşılır Türkçe mesaj üretilmiyor.

### 2.2 İç içe klasörler — 🔴 KIRIK

Zincirin her halkası tek tek doğru ama uçtan uca kopuk:

1. Model destekliyor: `Folder.parentId` ([Models.swift:75](PolyglotReader/Models/Models.swift#L75)).
2. DB destekliyor: `getFolders(userId:parentId:)` alt klasörleri sorgular ([SupabaseDatabaseService.swift:419-457](PolyglotReader/Services/Supabase/SupabaseDatabaseService.swift#L419)).
3. VM destekliyor: `loadFoldersAndTags` mevcut klasörün altını yükler ([LibraryViewModel+Loading.swift:56](PolyglotReader/ViewModels/LibraryViewModel+Loading.swift#L56)).
4. **UI göstermiyor**: `CollapsibleFolderSection` yalnız `currentFolder == nil` iken render ediliyor ([LibraryView.swift:234-236](PolyglotReader/Views/Library/LibraryView.swift#L234)).

Sonuç: Bir klasörün içine girince alt klasörleri **görmek imkânsız**. `CreateFolderSheet` ile alt klasör oluşturup içine dosya taşıyan kullanıcı o dosyalara bir daha ulaşamaz (dosya filtresi de yalnız `folderId == currentFolder?.id` — [LibraryViewModel.swift:86](PolyglotReader/ViewModels/LibraryViewModel.swift#L86)). Tek satırlık koşul düzeltmesiyle çözülür; veri kaybı yok, erişim kaybı var.

### 2.3 Klasör sayacı — 🔴 her zaman 0

`getFolders` sonucu `Folder(...)`'a `fileCount` geçirmiyor → varsayılan `0` ([SupabaseDatabaseService.swift:447-456](PolyglotReader/Services/Supabase/SupabaseDatabaseService.swift#L447), [Models.swift:92](PolyglotReader/Models/Models.swift#L92)). Kart ise "\(folder.fileCount) dosya" basıyor ([FolderViews.swift:197](PolyglotReader/Views/Library/FolderViews.swift#L197)). CLAUDE.md'de `get_folders_with_count` RPC'si tanımlı ama **Swift tarafında hiç çağrılmıyor** (repo genelinde referans yok). Yani her klasör kartı yanlış bilgi ("0 dosya") gösteriyor — güven zedeleyen, görünür bir hata.

### 2.4 Silme — 🔴 onaysız ve bilgilendirmesiz

- Context menü "Sil" → doğrudan `deleteFolder` ([FolderViews.swift:259-265](PolyglotReader/Views/Library/FolderViews.swift#L259), [LibraryViewModel+Folders.swift:68-88](PolyglotReader/ViewModels/LibraryViewModel+Folders.swift#L68)). Dosya silmede onay dialog'u varken klasörde yok.
- Şemada `files.folder_id ... ON DELETE SET NULL` — içindeki dosyalar sessizce ana klasöre düşüyor. Kullanıcıya "İçindeki 12 dosya ana klasöre taşınacak" tarzı bilgi verilmiyor. Alt klasörlerin `parent_id`'si de NULL'a düşüp kökte beliriyor.

### 2.5 Yeniden adlandırma / düzenleme — YOK

Repo genelinde `renameFolder`/`updateFolder` yok. Oluşturduktan sonra klasörün **adı, rengi ve ikonu değiştirilemez**. Rakiplerde (Files dahil) temel beklenti.

### 2.6 İkonlar — çalışıyor ama yerel hapiste

`FolderIconStore` ikonları UserDefaults'ta tutuyor ([FolderIconStore.swift:9-51](PolyglotReader/Services/FolderIconStore.swift#L9)); şema değişikliği gerektirmeyen pragmatik çözüm. Ancak: cihaz değişiminde/yeniden kurulumda kaybolur, web uygulaması göremez, oluşturma sonrası değiştirilemez (rename olmadığı için). Doğru kalıcı çözüm `folders` tablosuna `icon TEXT` kolonu.

### 2.7 Navigasyon — breadcrumb hatası

- İleri/geri: `navigateToFolder` / `navigateBack` path yönetimi doğru ve her ikisi `loadFoldersAndTags` çağırıyor ([LibraryViewModel+Folders.swift:8-29](PolyglotReader/ViewModels/LibraryViewModel+Folders.swift#L8)).
- **🟠 Breadcrumb'dan orta seviyeye atlama eksik yükleme yapıyor**: buton doğrudan `folderPath`/`currentFolder`'ı değiştiriyor ama `loadFoldersAndTags` **çağrılmıyor** ([FolderViews.swift:304-311](PolyglotReader/Views/Library/FolderViews.swift#L304)). `folders` listesi eski seviyenin verisiyle kalıyor (şu an alt klasörler render edilmediği için maskelenmiş — §2.2 düzeltilince görünür hale gelecek). VM'deki navigasyon mantığının view içinde kopyalanması da katman ihlali.

---

## 3. DOSYA TAŞIMA

- Tekil taşıma: grid kartı context menüsü → "Klasöre Taşı" → klasör listesi ([PDFCardView.swift:24-44](PolyglotReader/Views/Library/PDFCardView.swift#L24)); optimistic güncelleme ile `files[index].folderId` anında değişiyor ([LibraryViewModel+Folders.swift:91-115](PolyglotReader/ViewModels/LibraryViewModel+Folders.swift#L91)). ✅
- Toplu taşıma: seçim modu → klasör dialog'u → sıralı döngü, hata sayacı, "N dosya taşınamadı" mesajı ([LibraryViewModel+Selection.swift:71-95](PolyglotReader/ViewModels/LibraryViewModel+Selection.swift#L71)). ✅

**Eksikler / sorunlar**
- **Hedef listesi yalnız görünür seviyenin klasörleri**: `viewModel.folders` mevcut seviyeye ait ([LibraryView.swift:137-141](PolyglotReader/Views/Library/LibraryView.swift#L137)). Kökteyken alt klasöre, klasör içindeyken kardeş klasöre taşımak imkânsız. Hiyerarşik klasör seçici (ağaç görünümlü sheet) gerekli.
- **Liste modunda taşıma menüsü hiç yok** (§1.2).
- **Drag & drop yok**: `draggable`/`dropDestination` kütüphanede hiç kullanılmamış. Kartı klasör kartının üstüne sürükleme — Files/GoodNotes standardı — mevcut değil. iPad'de özellikle hissedilir.
- **Geri alma (undo) yok**: ne taşımada ne silmede. En azından taşıma sonrası "Geri Al" butonlu geçici snackbar kolay kazanım.
- `confirmationDialog` uzun klasör listesinde hantallaşır (10+ klasörde ekranı kaplar); sheet + arama daha ölçeklenebilir.

---

## 4. DOSYA YÖNETİMİ

### 4.1 Yükleme

- `fileImporter` yalnız `.pdf`, **tek dosya** ([LibraryView.swift:28-34](PolyglotReader/Views/Library/LibraryView.swift#L28)). Çoklu seçim kapalı — 10 makale yükleyecek akademisyen için 10 ayrı tur.
- Akış zengin: progress overlay (gerçek byte-bazlı progress, `UploadProgressDelegate` — [SupabaseStorageService.swift:36-123](PolyglotReader/Services/Supabase/SupabaseStorageService.swift#L36)) → %100'de checkmark anı → arka planda özet + AI etiket + RAG indeksleme ([LibraryViewModel+Upload.swift:104-113](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L104)). RAG metin çıkarımı `Task.detached` ile main thread'den alınmış ([LibraryViewModel+Upload.swift:125-129](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L125)). Offline kontrolü var ([LibraryViewModel+Upload.swift:10-14](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L10)). ✅
- **🟠 Dışarıdan PDF almanın hiçbir yolu yok**: Info.plist'te `CFBundleDocumentTypes` / `LSSupportsOpeningDocumentsInPlace` tanımlı değil; share extension yok. Safari'de/Mail'de açılan bir PDF "Corio Docs'a kopyala" diyemiyor. Bir PDF okuyucu için **en kritik edinim kanalı kapalı**.
- Klasör içindeyken yüklenen dosya iki adımda (upload → move) klasöre bağlanıyor ([LibraryViewModel+Upload.swift:69-86](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L69)); move başarısız olursa dosya sessizce kökte kalıyor (yalnız log).
- `fetchFileData` tüm dosyayı belleğe okuyor ([LibraryViewModel+Upload.swift:61-67](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L61)) — 200 MB PDF'te bellek zirvesi. Upload zaten Data istediği için kısa vadede kabul edilebilir, sınır/uyarı yok.

### 4.2 Silme

- Tekil: context menü → onay dialog'u → storage + DB + thumbnail/özet cache + RAG chunk temizliği + etiket temizliği ([LibraryViewModel+Deletion.swift:7-68](PolyglotReader/ViewModels/LibraryViewModel+Deletion.swift#L7)). Kapsamlı ve doğru sıralı. ✅
- Toplu: aynı temizlik, hata sayacıyla ([LibraryViewModel+Selection.swift:41-68](PolyglotReader/ViewModels/LibraryViewModel+Selection.swift#L41)). ✅
- Eksik: **çöp kutusu / soft delete yok** — silme kalıcı. Undo yok. Rakiplerde (PDF Expert, Files) "Son Silinenler" standart güvenlik ağı.

### 4.3 Yeniden adlandırma — YOK

Dosya adı hiçbir yerden değiştirilemiyor (repo genelinde rename kodu yok). "IMG_2043 copy.pdf" adıyla yüklenen dosya sonsuza dek öyle kalıyor. `files.name` kolonunu güncellemek tek UPDATE — düşük maliyet, yüksek değer.

### 4.4 Paylaşma / Export — YOK

Reader içi metin/görsel paylaşımı var ama **kütüphaneden PDF'in kendisini paylaşmak/dışa aktarmak imkânsız** (`ShareLink` yok). "Dosyayı hocama göndereyim" akışı yok.

### 4.5 Dosya bilgileri

Kartta isim, boyut, tarih, etiketler var. **Sayfa sayısı yok** (modelde alan yok), "dosya bilgisi" detay sheet'i yok, son açılma bilgisi yok, favori/yıldız yok (Notebook'taki favoriler annotation'lara ait, dosyalara değil).

---

## 5. PERFORMANS

**İyi yapılmış**
- N+1 etiket sorunu çözülmüş: `getFileTagsBatch` tek sorgu (~6sn → ~200ms, [LibraryViewModel+Loading.swift:16-24](PolyglotReader/ViewModels/LibraryViewModel+Loading.swift#L16)). ✅
- Liste ve grid `LazyVStack`/`LazyVGrid` ([LibraryView.swift:307-310](PolyglotReader/Views/Library/LibraryView.swift#L307)). ✅
- Decode edilmiş thumbnail paylaşımı (§1.3). ✅
- Arama debounce (300ms). ✅
- NSCache limitleri makul; memory warning'de temizlik var.

**Riskler**
- **Sayfalama yok**: `listFiles` tüm dosyaları tek seferde çekiyor ([SupabaseFileService.swift:73-82](PolyglotReader/Services/Supabase/SupabaseFileService.swift#L73)). 500+ dosyada ilk açılış yavaşlar; `.range()` ile sayfalama veya en azından limit düşünülmeli.
- **Thumbnail = tam PDF indirme + sınırsız paralellik** (§1.3) — mevcut en büyük performans/veri riski.
- `filteredFiles` her erişimde filtre+sort yapıyor ([LibraryViewModel.swift:82-120](PolyglotReader/ViewModels/LibraryViewModel.swift#L82)); computed property olduğu için body başına birden çok kez çağrılabiliyor. ~100 dosyada sorun değil, 1000+ dosyada `@Published` önbellekli sonuca geçilmeli.
- `visibleTags` da benzer şekilde her body'de O(n·m) hesap ([LibraryViewModel.swift:123-144](PolyglotReader/ViewModels/LibraryViewModel.swift#L123)).
- Liste↔grid geçişi animasyonlu ve state korunuyor; ancak `viewMode` kalıcı değil (`@AppStorage` değil) — uygulama yeniden açılınca hep grid'e döner. Sıralama tercihi de kalıcı değil.

---

## 6. RAKİP KARŞILAŞTIRMASI

| Özellik | Corio Docs | Files (Apple) | PDF Expert | GoodNotes |
|---|---|---|---|---|
| Klasör oluşturma (ikon+renk) | ✅ (rakiplerden zengin) | ➖ | ✅ | ✅ (kapak) |
| İç içe klasör gezinme | 🔴 kırık | ✅ | ✅ | ✅ |
| Klasör/dosya rename | ❌ | ✅ | ✅ | ✅ |
| Drag & drop taşıma | ❌ | ✅ | ✅ | ✅ |
| Swipe aksiyonları | ❌ | ✅ | ✅ | ➖ |
| Çoklu dosya import | ❌ | ✅ | ✅ | ✅ |
| "Open in / Share to" ile alma | ❌ | ✅ | ✅ | ✅ |
| Dosya paylaşma/export | ❌ | ✅ | ✅ | ✅ |
| Son silinenler / undo | ❌ | ✅ | ✅ | ✅ |
| Favoriler | ❌ | ✅ | ✅ | ➖ |
| Son açılanlar / devam et | ❌ | ✅ | ✅ | ✅ |
| Okuma ilerlemesi göstergesi | ❌ | ➖ | ✅ | ✅ |
| AI özet kartı (flip) | ✅ **benzersiz** | ❌ | ❌ | ❌ |
| AI otomatik etiket | ✅ **benzersiz** | ❌ | ❌ | ❌ |
| İçerik (RAG) altyapısı | ✅ (aramaya bağlı değil) | ➖ | ✅ içerik arama | ✅ el yazısı arama |
| Etiket filtreleme | ✅ | ✅ | ➖ | ➖ |

**Özet**: AI katmanında rakiplerin önünde, dosya yönetimi temellerinde rakiplerin gerisinde. Strateji: temelleri kapat (Faz 1-2), AI farkını aramaya taşı (Faz 4).

---

## 7. GELİŞTİRME IMPLEMENTATION PLANI

Etki: 🔥🔥🔥 yüksek · 🔥🔥 orta · 🔥 düşük — Çaba: S (saatler), M (1-2 gün), L (3+ gün)

### FAZ 1 — Kritik UX Düzeltmeleri (hata giderme; 1-2 gün)

| # | İş | Etki | Çaba | Not |
|---|---|---|---|---|
| 1.1 | Alt klasörleri klasör içinde göster: [LibraryView.swift:234](PolyglotReader/Views/Library/LibraryView.swift#L234) koşulunu `!viewModel.folders.isEmpty` yap | 🔥🔥🔥 | S | Kırık özelliği açan tek satır |
| 1.2 | Klasör dosya sayacı: `get_folders_with_count` RPC'sini `getFolders`'a bağla (yoksa migration ile oluştur) | 🔥🔥🔥 | S | "0 dosya" yalanını bitirir |
| 1.3 | Klasör silme onayı + "içindeki N dosya ana klasöre taşınır" mesajı | 🔥🔥🔥 | S | Veri güveni |
| 1.4 | Breadcrumb navigasyonunu VM'e taşı (`navigateToPathFolder`), `loadFoldersAndTags` çağır ([FolderViews.swift:304](PolyglotReader/Views/Library/FolderViews.swift#L304)) | 🔥🔥 | S | 1.1 ile birlikte şart |
| 1.5 | Flip kartta özet hatasında `isGeneratingSummary`'yi sıfırla (sonsuz spinner) | 🔥🔥 | S | Timeout/failure callback |
| 1.6 | Liste satırına "Klasöre Taşı" context menüsü + etiket rozetleri ekle (grid ile eşitle) | 🔥🔥 | S | Görünüm eşitliği |
| 1.7 | `errorMessage`'ı UI'a bağla (banner/alert) veya kaldırıp ErrorHandlingService'e devret | 🔥🔥 | S | Sessiz hatalar |

### FAZ 2 — Klasörleme ve Dosya Yönetimi Temelleri (1-1.5 hafta)

| # | İş | Etki | Çaba | Not |
|---|---|---|---|---|
| 2.1 | Dosya yeniden adlandırma (context menü + alert/sheet, `files.name` UPDATE) | 🔥🔥🔥 | S | En çok istenecek temel özellik |
| 2.2 | Klasör düzenleme: rename + renk + ikon değiştirme (CreateFolderSheet'i EditFolderSheet olarak yeniden kullan) | 🔥🔥🔥 | M | 2.3 ile birlikte |
| 2.3 | `folders.icon` kolonu migration'ı; FolderIconStore'dan DB'ye geçiş (web de görsün) | 🔥🔥 | S | UserDefaults fallback korunabilir |
| 2.4 | Hiyerarşik klasör seçici sheet (taşıma + oluşturma + toplu taşıma için ortak ağaç görünümü) | 🔥🔥🔥 | M | confirmationDialog'ların yerini alır |
| 2.5 | Kütüphaneden PDF paylaşma (`ShareLink` / UIActivityVC, signed URL'den indirilen dosyayla) | 🔥🔥🔥 | S | |
| 2.6 | Çoklu dosya yükleme (`allowsMultipleSelection: true` + kuyruklu progress: "3/10 yükleniyor") | 🔥🔥🔥 | M | |
| 2.7 | "Open in" desteği: Info.plist `CFBundleDocumentTypes` + `onOpenURL`'de dosya import akışı | 🔥🔥🔥 | M | En kritik edinim kanalı |
| 2.8 | Taşıma/silme sonrası "Geri Al" snackbar'ı (taşıma: eski folderId'ye dön; silme için Faz 4'teki çöp kutusuna kadar sadece taşıma) | 🔥🔥 | M | |

### FAZ 3 — UI Modernizasyonu ve Performans (1 hafta)

| # | İş | Etki | Çaba | Not |
|---|---|---|---|---|
| 3.1 | Thumbnail'i upload anında Storage'a yaz; listede tam PDF yerine küçük JPEG indir | 🔥🔥🔥 | M | Veri kullanımı + hız; migration: eski dosyalar için lazy backfill |
| 3.2 | Thumbnail üretiminde eşzamanlılık sınırı (TaskGroup, maks 3-4) | 🔥🔥 | S | 3.1 gelene kadar ara çözüm |
| 3.3 | Grid'i `.adaptive(minimum: 160)` yap — iPad/landscape düzeni | 🔥🔥 | S | |
| 3.4 | Liste modunu `List` tabanına taşı → `swipeActions` (sil/taşı/paylaş) | 🔥🔥 | M | iOS kas hafızası |
| 3.5 | `viewMode` + sıralama tercihini `@AppStorage`'a al | 🔥🔥 | S | |
| 3.6 | LoadingView yerine skeleton kart grid'i | 🔥 | S | SkeletonBlock hazır |
| 3.7 | Lokalizasyon temizliği: FolderViews/LibraryView'daki hardcoded Türkçe metinleri Localizable.strings'e taşı | 🔥 | M | SwiftLint custom rule zaten uyarıyor |
| 3.8 | 500+ dosya için `listFiles` sayfalama (`range`) veya lazy batch | 🔥 | M | Kütüphane büyüyünce |
| 3.9 | Toolbar sadeleştirme: arama `.searchable`'a, ikincil aksiyonlar tek menüye | 🔥 | M | Tasarım kararı gerektirir |

### FAZ 4 — Yeni Özellikler / Fark Yaratanlar (2+ hafta, öncelik sırasıyla)

| # | İş | Etki | Çaba | Not |
|---|---|---|---|---|
| 4.1 | Okuma ilerlemesi: `reading_progress`'i listeye join'le → kartta progress bar + "Son açılan" sıralaması + "Kaldığın yerden devam" şeridi | 🔥🔥🔥 | M | Veri DB'de hazır, sadece UI |
| 4.2 | Favori/yıldız: `files.is_favorite` kolonu + filtre + kart rozeti | 🔥🔥 | S | |
| 4.3 | Drag & drop: kartı klasör kartına sürükleme (`draggable`/`dropDestination`), iPad'de Files'tan içeri sürükleme | 🔥🔥 | M | |
| 4.4 | İçerik araması: arama kutusuna "içerikte ara" sekmesi — mevcut BM25/hybrid RAG RPC'lerini kütüphane aramasına bağla | 🔥🔥🔥 | M | **Rakiplerin taklit edemeyeceği fark**; altyapı hazır |
| 4.5 | Çöp kutusu (soft delete): `files.deleted_at` + "Son Silinenler" görünümü + 30 gün otomatik temizlik | 🔥🔥 | M | |
| 4.6 | Dosya bilgi sheet'i: sayfa sayısı, eklenme/son açılma, boyut, etiketler, özet, RAG durumu | 🔥 | S | |
| 4.7 | Toplu etiketleme (seçim modunda etiket ata/kaldır) | 🔥 | S | |
| 4.8 | İstatistikler (Defterim'e de uyar): toplam okunan sayfa, haftalık okuma, en çok açılan dosyalar | 🔥 | M | Doçentlik dönemi motivasyonu 🙂 |

### Önerilen sıra ve gerekçe

1. **Faz 1 hemen** — üçü de kullanıcı gözünde "bozuk uygulama" sinyali veren, saatlik düzeltmeler.
2. **Faz 2'den 2.1, 2.5, 2.7 öne alınabilir** — rename, paylaş ve "Open in" tek başına App Store yorumlarını belirleyen temel beklentiler.
3. **3.1 (thumbnail mimarisi)** kütüphane büyümeden yapılmalı; sonrası migration maliyeti artar.
4. **4.4 (RAG içerik araması)** pazarlanabilir en güçlü özellik — altyapının %90'ı zaten yazılmış durumda.

---

## EK: Tespit Edilen Hata Listesi (özet)

| Önem | Hata | Konum |
|---|---|---|
| 🔴 | Alt klasörler klasör içinde render edilmiyor | [LibraryView.swift:234](PolyglotReader/Views/Library/LibraryView.swift#L234) |
| 🔴 | Klasör kartları her zaman "0 dosya" | [SupabaseDatabaseService.swift:447](PolyglotReader/Services/Supabase/SupabaseDatabaseService.swift#L447) |
| 🔴 | Klasör silme onaysız; dosyaların köke düşeceği söylenmiyor | [FolderViews.swift:259](PolyglotReader/Views/Library/FolderViews.swift#L259) |
| 🟠 | Breadcrumb atlama `loadFoldersAndTags` çağırmıyor | [FolderViews.swift:304](PolyglotReader/Views/Library/FolderViews.swift#L304) |
| 🟠 | Thumbnail için tam PDF indirme + sınırsız paralel task | [LibraryViewModel+Thumbnails.swift:47](PolyglotReader/ViewModels/LibraryViewModel+Thumbnails.swift#L47), [LibraryViewModel+Loading.swift:30](PolyglotReader/ViewModels/LibraryViewModel+Loading.swift#L30) |
| 🟠 | Flip kartta özet hatası → sonsuz "Özet hazırlanıyor…" | [FlippablePDFCardView.swift:43](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L43) |
| 🟠 | `errorMessage` UI'da hiç gösterilmiyor | [LibraryViewModel.swift:14](PolyglotReader/ViewModels/LibraryViewModel.swift#L14) |
| 🟡 | Liste modunda taşıma menüsü ve etiketler yok | [PDFCardView.swift:249](PolyglotReader/Views/Library/PDFCardView.swift#L249) |
| 🟡 | Taşıma/oluşturma hedef listesi yalnız mevcut seviye klasörleri | [LibraryView.swift:137](PolyglotReader/Views/Library/LibraryView.swift#L137), [FolderViews.swift:350](PolyglotReader/Views/Library/FolderViews.swift#L350) |
| 🟡 | Upload sonrası klasöre bağlama hatası sessizce yutulur | [LibraryViewModel+Upload.swift:79-85](PolyglotReader/ViewModels/LibraryViewModel+Upload.swift#L79) |
| 🟡 | `detectCategory` sezgiseli `aiCategory` varken kullanılıyor | [FlippablePDFCardView.swift:310](PolyglotReader/Views/Library/FlippablePDFCardView.swift#L310) |
| 🟡 | viewMode/sıralama tercihi kalıcı değil | [LibraryViewModel.swift:20-22](PolyglotReader/ViewModels/LibraryViewModel.swift#L20) |
| 🟡 | Hardcoded Türkçe metinler (lokalizasyon karışık) | FolderViews.swift geneli, [LibraryView.swift:120](PolyglotReader/Views/Library/LibraryView.swift#L120) |
