# FORSERGEN.md - PolyglotReader'ın Hikayesi

*Bu dosya bir teknik dokümantasyon değil, bir öğrenme yolculuğu. PolyglotReader'ı inşa ederken öğrendiğim her şeyi burada bulacaksın.*

---

## İçindekiler

1. [Teknik Mimari - Büyük Resim](#1-teknik-mimari---büyük-resim)
2. [Kod Yapısı - Karakterlerle Tanışın](#2-kod-yapısı---karakterlerle-tanışın)
3. [Teknoloji Seçimleri - Neden Bunlar?](#3-teknoloji-seçimleri---neden-bunlar)
4. [Karşılaşılan Sorunlar ve Çözümleri](#4-karşılaşılan-sorunlar-ve-çözümleri)
5. [Potansiyel Tuzaklar - Mayın Haritası](#5-potansiyel-tuzaklar---mayın-haritası)
6. [Öğrenilen Dersler](#6-öğrenilen-dersler)
7. [Best Practice'ler - Altın Kurallar](#7-best-practiceler---altın-kurallar)

---

## 1. Teknik Mimari - Büyük Resim

### PolyglotReader Nedir?

Bir düşün: Elinde yüzlerce sayfalık bir PDF var. Belli bir konuyu arıyorsun ama nerede olduğunu hatırlamıyorsun. Normalde ne yaparsın? CTRL+F ile aramaya çalışırsın, sayfalarca scroll yaparsın, belki notlar alırsın... Yorucu, değil mi?

**PolyglotReader** işte tam bu problemi çözüyor. PDF'ini yükle, yapay zekaya sor: "Bu kitapta makine öğrenmesi nerede anlatılıyor?" - ve cevabı al. Üstelik sadece arama değil:

- **Akıllı sohbet**: PDF hakkında soru sor, cevap al
- **Çeviriler**: Metni seç, anında çevir
- **Notlar ve vurgular**: İstediğin yeri işaretle, not ekle
- **Quiz oluşturma**: PDF'ten otomatik sorular üret
- **Özet çıkarma**: Sayfalarca metni birkaç cümleye indir

### Mimari Hikayesi: Bir Gazete Üretim Hattı

PolyglotReader'ı anlamak için onu bir **gazete üretim hattı** gibi düşün:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        POLYGLOTREADER MİMARİSİ                              │
│                      (Gazete Üretim Hattı Analojisi)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐              │
│   │   KULLANICI  │     │    VIEWS     │     │  VIEWMODELS  │              │
│   │  (Okuyucu)   │────▶│   (Gazete)   │◀───▶│  (Editörler) │              │
│   └──────────────┘     └──────────────┘     └──────────────┘              │
│                              ▲                     │                        │
│                              │                     ▼                        │
│                        ┌─────┴─────────────────────┴─────┐                 │
│                        │          SERVICES               │                 │
│                        │      (Üretim Departmanları)     │                 │
│                        └─────────────────────────────────┘                 │
│                                      │                                      │
│          ┌───────────────────────────┼───────────────────────────┐         │
│          ▼                           ▼                           ▼         │
│   ┌──────────────┐          ┌──────────────┐          ┌──────────────┐    │
│   │   Supabase   │          │    Gemini    │          │   PDFKit     │    │
│   │  (Arşiv)     │          │   (Yazar)    │          │  (Matbaa)    │    │
│   └──────────────┘          └──────────────┘          └──────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Analoji Açıklaması:**

| Gazete Terimi | Uygulama Karşılığı | Görevi |
|---------------|-------------------|--------|
| **Okuyucu** | Kullanıcı | Gazeteyi (uygulamayı) kullanan kişi |
| **Gazete** | Views (SwiftUI) | Kullanıcının gördüğü ve dokunduğu ekranlar |
| **Editörler** | ViewModels | Neyin nerede gösterileceğine karar verir |
| **Arşiv** | Supabase | Tüm geçmiş gazeteler (dosyalar, notlar, sohbetler) |
| **Yazar** | Gemini AI | İçerik üretir, soruları yanıtlar |
| **Matbaa** | PDFKit | PDF'leri işler ve görüntüler |

### MVVM: Model-View-ViewModel

PolyglotReader **MVVM** pattern'ini kullanıyor. Bu ne demek?

```
┌─────────────────────────────────────────────────────────────────┐
│                         MVVM Akışı                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────┐    1. Gör        ┌──────────────┐                │
│   │  VIEW   │◀─────────────────│  VIEWMODEL   │                │
│   │         │                  │              │                │
│   │ SwiftUI │──────────────────▶ @Published   │                │
│   │ Ekranlar│    2. Bildir     │  Properties  │                │
│   └─────────┘                  └──────────────┘                │
│                                       │                         │
│                                       │ 3. Güncelle             │
│                                       ▼                         │
│                               ┌──────────────┐                 │
│                               │    MODEL     │                 │
│                               │  (Veri)      │                 │
│                               └──────────────┘                 │
│                                                                 │
│   Örnek:                                                        │
│   1. LibraryView, LibraryViewModel'deki "files" array'ini izler │
│   2. Kullanıcı "yükle" butonuna basar → viewModel.uploadFile()  │
│   3. ViewModel, Supabase'e dosya yükler                         │
│   4. files array'i güncellenir (@Published)                     │
│   5. SwiftUI otomatik olarak ekranı yeniler                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Veri Akışı: Bir PDF'in Yolculuğu

Kullanıcı bir PDF yüklediğinde neler oluyor? Hadi adım adım takip edelim:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PDF YÜKLEME YOLCULUĞU                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Kullanıcı "+" butonuna basar                                           │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ LibraryView: fileImporter açılır                                 │      │
│  │ → Kullanıcı dosya seçer                                          │      │
│  │ → URL alınır                                                      │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ LibraryViewModel.uploadFile(url:)                                │      │
│  │ → isUploading = true (yükleme spinner'ı göster)                  │      │
│  │ → uploadProgress = 0                                              │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ SupabaseService.uploadFile()                                      │      │
│  │ → Dosya "user_files" bucket'ına yüklenir                         │      │
│  │ → Progress delegate ile ilerleme takip edilir                     │      │
│  │ → storage_path: "user_id/uuid.pdf"                               │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ SupabaseService.insertFileRecord()                               │      │
│  │ → files tablosuna metadata kaydedilir                            │      │
│  │ → { id, name, size, storage_path, user_id, created_at }          │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ LibraryViewModel                                                  │      │
│  │ → files.append(newPDFMetadata)                                   │      │
│  │ → isUploading = false                                            │      │
│  │ → generateThumbnail() arka planda çalışır                        │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │ LibraryView (SwiftUI)                                             │      │
│  │ → @StateObject viewModel izleniyor                               │      │
│  │ → files değişti → ekran otomatik yenilenir                       │      │
│  │ → Yeni PDF kartı görünür!                                        │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### RAG: Yapay Zekanın Hafızası

**RAG (Retrieval-Augmented Generation)** - Bu isim kulağa karmaşık geliyor ama aslında çok basit bir fikir:

> "Yapay zeka her şeyi bilmez. Ama ona gerekli bilgiyi verirsen, çok akıllı cevaplar verebilir."

Nasıl çalışıyor? Şöyle düşün:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RAG SİSTEMİ                                         │
│                  (Kütüphaneci Analojisi)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Soru: "Bu kitapta nöroplastisite konusu nerede anlatılıyor?"              │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │ ADIM 1: İndeksleme (Kitabı kataloglamak)                       │        │
│  │                                                                 │        │
│  │   PDF Metni ──▶ Parçalara Böl ──▶ Her Parçayı Vektörleştir     │        │
│  │                    (chunks)           (embeddings)              │        │
│  │                                                                 │        │
│  │   "Sayfa 1: Giriş..."   ──▶  [0.12, -0.34, 0.56, ...]         │        │
│  │   "Sayfa 2: Beyin..."   ──▶  [0.45, 0.23, -0.12, ...]         │        │
│  │   "Sayfa 3: Nöronlar..."──▶  [0.78, -0.91, 0.34, ...]         │        │
│  │                                                                 │        │
│  │   → Bu vektörler Supabase'e kaydedilir (pgvector)              │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                           │                                                 │
│                           ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │ ADIM 2: Arama (Soruyu vektörleştir, benzer parçaları bul)     │        │
│  │                                                                 │        │
│  │   "nöroplastisite"  ──▶  [0.76, -0.88, 0.31, ...]             │        │
│  │                                ↓                                │        │
│  │                    ┌───────────────────┐                       │        │
│  │                    │ Vektör Karşılaştır│                       │        │
│  │                    │ (cosine similarity)│                      │        │
│  │                    └───────────────────┘                       │        │
│  │                                ↓                                │        │
│  │   En yakın 5 parça: Sayfa 45, 47, 12, 89, 3                   │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                           │                                                 │
│                           ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │ ADIM 3: Yanıt (Bağlamı Gemini'ye gönder)                      │        │
│  │                                                                 │        │
│  │   Prompt:                                                       │        │
│  │   "Aşağıdaki bağlamı kullanarak soruyu yanıtla:               │        │
│  │    [Sayfa 45 içeriği...]                                       │        │
│  │    [Sayfa 47 içeriği...]                                       │        │
│  │    Soru: nöroplastisite nerede anlatılıyor?"                  │        │
│  │                                                                 │        │
│  │   Gemini yanıtlar:                                             │        │
│  │   "Nöroplastisite konusu kitabın 45. sayfasında..."           │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Neden RAG kullanıyoruz?**

1. **Gemini'nin bilgi kesim tarihi var** - 2024 öncesi bilgileri biliyor ama senin PDF'ini bilmiyor
2. **Context window sınırlı** - 500 sayfalık PDF'i tek seferde gönderemezsin
3. **Daha doğru cevaplar** - Alakalı bölümleri bulup gönderince hallüsinasyon azalıyor

---

## 2. Kod Yapısı - Karakterlerle Tanışın

### Klasör Yapısı: Şehrin Haritası

```
PolyglotReader/
│
├── 🏛️ App/                          # Belediye Binası - Her şey buradan başlar
│   └── PolyglotReaderApp.swift      # Belediye Başkanı
│
├── 📦 Models/                        # Şehir Planları - Veri yapıları
│   ├── Models.swift                  # Ana blueprint'ler
│   ├── AppError.swift               # Acil durum kodları
│   └── ChatSuggestion.swift         # Öneri kartları
│
├── 🎭 ViewModels/                    # Departman Müdürleri
│   ├── AuthViewModel.swift          # Güvenlik Müdürü
│   ├── LibraryViewModel.swift       # Kütüphane Müdürü
│   ├── PDFReaderViewModel.swift     # Okuma Salonu Sorumlusu
│   ├── ChatViewModel.swift          # İletişim Koordinatörü
│   ├── NotebookViewModel.swift      # Arşiv Sorumlusu
│   └── QuizViewModel.swift          # Sınav Komisyonu
│
├── 🖼️ Views/                         # Şehrin Binaları - Kullanıcının gördüğü
│   ├── Auth/                         # Şehir Kapıları
│   ├── Library/                      # Kütüphane
│   ├── Reader/                       # Okuma Salonu
│   ├── Chat/                         # İletişim Merkezi
│   ├── Notebook/                     # Arşiv
│   ├── Quiz/                         # Sınav Salonu
│   └── Settings/                     # Belediye Ayarları
│
├── ⚙️ Services/                      # Altyapı Hizmetleri
│   ├── Config.swift                  # Şehir Ayarları
│   ├── GeminiService.swift          # Yapay Zeka Danışmanı
│   ├── RAGService.swift             # Kütüphaneci
│   ├── PDFService.swift             # Matbaa
│   ├── LoggingService.swift         # Şehir Kaydedicisi
│   ├── NetworkMonitor.swift         # İnternet Denetçisi
│   ├── CacheService.swift           # Depo Sorumlusu
│   │
│   ├── Supabase/                     # Bulut Arşivi
│   ├── Gemini/                       # AI Alt Birimleri
│   ├── RAG/                          # Arama Sistemi
│   └── PDF/                          # PDF İşleme
│
└── 📚 Resources/                     # Şehir Kaynakları
    └── Localizable.strings           # Çeviri Kitabı
```

### Karakterler: Dosyaların Hikayeleri

#### 🏛️ `PolyglotReaderApp.swift` - Belediye Başkanı

```swift
@main
struct PolyglotReaderApp: App {
    // "Ben buradayım, şehri başlatıyorum!"

    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)  // "Herkese güvenlik kartı dağıt"
                .environmentObject(settingsViewModel)  // "Ayarları paylaş"
                .onOpenURL { url in
                    // "Kapıda biri var! OAuth callback mi?"
                    handleOAuthCallback(url)
                }
        }
    }
}
```

**Görevi:** Uygulama başladığında her şeyi ayağa kaldırır. OAuth callback'leri yakalar, global state'leri dağıtır.

---

#### 🔐 `AuthViewModel.swift` - Güvenlik Müdürü

```swift
@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false  // "Kapı açık mı?"
    @Published var currentUser: User?       // "Kim içeride?"
    @Published var isLoading = false        // "Kimlik kontrol ediliyor..."

    func signInWithGoogle() async {
        // "Google'a sor: Bu kişi kim?"
    }

    func signOut() async {
        // "Herkesi dışarı çıkar, kapıları kilitle"
    }
}
```

**Görevi:** Kim içeri girebilir, kim çıkmalı? Tüm giriş/çıkış işlemleri onun sorumluluğunda.

---

#### 📚 `LibraryViewModel.swift` - Kütüphane Müdürü

Bu arkadaş o kadar çok iş yapıyor ki, kendini 10 dosyaya bölmek zorunda kaldı:

```
LibraryViewModel.swift          # Ana merkez
├── +Upload.swift               # "Yeni kitap geldi!"
├── +Deletion.swift            # "Bu kitabı raftan kaldır"
├── +Folders.swift             # "Rafları düzenle"
├── +Loading.swift             # "Kitapları getir"
├── +Tags.swift                # "Etiketleri yapıştır"
├── +Summary.swift             # "Özet çıkar"
├── +Thumbnails.swift          # "Kapak fotoğrafı çek"
├── +Sorting.swift             # "Alfabetik mi, tarihe göre mi?"
└── +FileAccess.swift          # "Bu kitap nerede?"
```

**Görevi:** Tüm PDF'lerin yönetimi. Yükleme, silme, düzenleme, arama...

---

#### 📖 `PDFReaderViewModel.swift` - Okuma Salonu Sorumlusu

```swift
@MainActor
class PDFReaderViewModel: ObservableObject {
    @Published var document: PDFDocument?     // "Açık kitap"
    @Published var currentPage = 1            // "Hangi sayfa açık?"
    @Published var annotations: [Annotation]  // "Fosforlu kalem izleri"
    @Published var selectedText: String?      // "Seçili metin"

    func loadDocument() async {
        // 1. Önce depoya bak (cache)
        // 2. Yoksa buluttan indir (Supabase)
        // 3. Matbaaya gönder (PDFKit)
        // 4. Kitabı aç!
    }

    func addAnnotation(_ annotation: Annotation) {
        // "Buraya fosforlu kalemle çiz"
    }
}
```

**Görevi:** PDF görüntüleme, sayfa navigasyonu, vurgulama, not ekleme...

---

#### 💬 `ChatViewModel.swift` - İletişim Koordinatörü

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage]    // "Sohbet geçmişi"
    @Published var isDocumentIndexed = false  // "Kitap kataloglandı mı?"
    @Published var smartSuggestions: [String] // "Sormak isteyebileceğin sorular"

    func sendMessage(_ text: String) async {
        // 1. Kitap kataloglanmadıysa, önce katalogla (RAG indexing)
        // 2. Kullanıcının sorusuna benzer bölümleri bul (semantic search)
        // 3. Bağlamı Gemini'ye gönder
        // 4. Cevabı göster
    }
}
```

**Görevi:** Kullanıcı ile yapay zeka arasındaki köprü. Mesajları alır, RAG ile zenginleştirir, Gemini'ye gönderir.

---

#### 🤖 `GeminiService.swift` - Yapay Zeka Danışmanı

```swift
@MainActor
class GeminiService {
    static let shared = GeminiService()  // "Şehirde tek yapay zeka var"

    // Alt danışmanlar
    private let chatService = GeminiChatService()
    private let analysisService = GeminiAnalysisService()
    private let ragService = GeminiRAGService()

    func translateText(_ text: String) async throws -> String {
        // analysisService'e delege et
    }

    func sendMessageWithContext(_ message: String, context: String) async throws {
        // chatService'e delege et
    }
}
```

**Görevi:** Tüm yapay zeka işlemlerinin tek noktası. Çeviri, özet, sohbet, quiz... Hepsi buradan geçer.

---

#### 📑 `RAGService.swift` - Kütüphaneci

```swift
@MainActor
class RAGService {
    static let shared = RAGService()

    let chunker = RAGChunker.shared           // "Kitabı parçalara bölen"
    let embeddingService = RAGEmbeddingService.shared  // "Vektörleştiren"
    let searchService = RAGSearchService.shared        // "Arayan"

    func indexDocument(text: String, fileId: UUID) async throws {
        // 1. Metni parçalara böl (400 kelime, 100 overlap)
        // 2. Her parçayı vektörleştir (Gemini embedding API)
        // 3. Supabase'e kaydet
    }

    func search(query: String, fileId: UUID) async throws -> [RAGResult] {
        // 1. Sorguyu vektörleştir
        // 2. Benzer parçaları bul (cosine similarity)
        // 3. Sonuçları döndür
    }
}
```

**Görevi:** PDF'leri akıllı arama için hazırlamak ve sorguları yanıtlamak.

---

#### ☁️ `SupabaseService.swift` - Bulut Arşivi

```swift
@MainActor
class SupabaseService {
    static let shared = SupabaseService()

    // Departmanlar
    let auth = SupabaseAuthService()
    let storage = SupabaseStorageService()
    let files = SupabaseFileService()
    let database = SupabaseDatabaseService()
    let annotations = SupabaseAnnotationService()
}
```

**Görevi:** Tüm bulut işlemleri. Giriş, dosya yükleme/indirme, veritabanı sorguları...

---

### Dosya Bağımlılık Haritası

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       BAĞIMLILIK HARİTASI                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PolyglotReaderApp                                                         │
│         │                                                                   │
│         ├──▶ AuthViewModel ───▶ SupabaseService.auth                       │
│         │                                                                   │
│         └──▶ ContentView                                                   │
│                   │                                                         │
│                   ├──▶ LibraryView ───▶ LibraryViewModel                   │
│                   │         │                  │                            │
│                   │         │                  ├──▶ SupabaseService.files   │
│                   │         │                  └──▶ GeminiService (özet)    │
│                   │         │                                               │
│                   │         └──▶ PDFReaderView ───▶ PDFReaderViewModel     │
│                   │                   │                   │                 │
│                   │                   │                   ├──▶ PDFService   │
│                   │                   │                   ├──▶ CacheService │
│                   │                   │                   └──▶ Supabase     │
│                   │                   │                                     │
│                   │                   └──▶ ChatView ───▶ ChatViewModel     │
│                   │                                          │              │
│                   │                                          ├──▶ RAGService│
│                   │                                          └──▶ Gemini    │
│                   │                                                         │
│                   ├──▶ NotebookView ───▶ NotebookViewModel ──▶ Supabase    │
│                   │                                                         │
│                   └──▶ SettingsView ───▶ SettingsViewModel                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Teknoloji Seçimleri - Neden Bunlar?

### Kullandığımız Teknolojiler

| Teknoloji | Ne İçin | Neden Bu |
|-----------|---------|----------|
| **SwiftUI** | UI Framework | Native iOS/macOS, declarative, reactive |
| **Supabase** | Backend-as-a-Service | Open source Firebase alternatifi, PostgreSQL, pgvector desteği |
| **Google Gemini** | Yapay Zeka | Hızlı, ucuz, multimodal, Türkçe desteği iyi |
| **PDFKit** | PDF İşleme | Apple'ın native PDF framework'ü |
| **pgvector** | Vector DB | Supabase içinde, ayrı servis gerekmez |

### Neden SwiftUI?

**Alternatifler:**
- UIKit (eski, imperative)
- React Native (cross-platform ama native değil)
- Flutter (Dart öğrenmek lazım)

**Neden SwiftUI seçtik:**
1. **Declarative UI** - "Bu butona basınca şunu yap" yerine "buton böyle görünsün, state böyle olunca değişsin"
2. **Native performance** - Köprü yok, direkt iOS/macOS
3. **Preview'lar** - Kod yazarken anında görmek
4. **Combine entegrasyonu** - @Published ile reactive programlama

```swift
// UIKit (imperative - adım adım anlat)
button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
@objc func buttonTapped() {
    label.text = "Tıklandı!"
}

// SwiftUI (declarative - sonucu anlat)
Button("Tıkla") {
    text = "Tıklandı!"
}
Text(text)  // Otomatik güncellenir
```

### Neden Supabase?

**Alternatifler:**
- Firebase (Google, closed source)
- AWS Amplify (karmaşık, pahalı)
- Custom backend (çok iş)

**Neden Supabase seçtik:**
1. **Open source** - İstersen self-host yap
2. **PostgreSQL** - Gerçek bir veritabanı, SQL yazabilirsin
3. **pgvector** - RAG için vector search desteği
4. **Row Level Security** - Kullanıcı sadece kendi verisini görür
5. **Realtime** - Değişiklikler anında gelir
6. **Storage** - S3 benzeri dosya depolama dahil

**Dezavantajları:**
- Free tier sınırlı (500MB DB, 1GB storage)
- Edge functions Node.js değil Deno
- Türkiye'de sunucu yok (latency)

### Neden Gemini?

**Alternatifler:**
- OpenAI GPT-4 (pahalı, rate limit)
- Claude (pahalı)
- Llama (self-host lazım)
- Mistral (embedding yok)

**Neden Gemini seçtik:**
1. **Ücretsiz tier cömert** - 15 RPM, günlük limit yüksek
2. **Multimodal** - Hem metin hem görsel
3. **Embedding API** - Aynı servis içinde vektörleştirme
4. **Türkçe** - Türkçe yanıtlar kaliteli
5. **Hızlı** - 1.5-pro modeli dengeli

**Dezavantajları:**
- Bazen halüsinasyon yapıyor
- Context window GPT-4'ten küçük
- API bazen yavaşlıyor

### Neden PDFKit?

**Alternatifler:**
- PSPDFKit (ücretli, güçlü)
- pdf.js (web için, native değil)
- Quartz (düşük seviye)

**Neden PDFKit:**
1. **Native** - Apple'ın kendi framework'ü
2. **Ücretsiz** - Lisans yok
3. **Yeterli** - Temel ihtiyaçları karşılıyor
4. **UIKit/SwiftUI uyumu** - UIViewRepresentable ile kolay

**Dezavantajları:**
- Annotation API kısıtlı
- Performance büyük PDF'lerde düşüyor
- Text extraction bazen hatalı

### Gelecekte Değişebilecek Kararlar

| Karar | Risk | Alternatif |
|-------|------|------------|
| Supabase Free Tier | 500MB dolunca? | Paid plan veya self-host |
| Gemini 1.5-pro | Fiyat artarsa? | Gemini Flash veya Llama |
| pgvector | Ölçekleme | Pinecone, Qdrant |
| PDFKit | Kompleks annotation | PSPDFKit (ücretli) |

---

## 4. Karşılaşılan Sorunlar ve Çözümleri

### Bug #1: EXC_BAD_ACCESS - Hayalet String Hatası 👻

**Sorun:** Annotation kaydederken rastgele crash'ler. Özellikle uzun metinleri vurgularken.

**Hata mesajı:**
```
EXC_BAD_ACCESS (code=1, address=0x...)
Thread 1: Fatal error: String index is out of bounds
```

**Teşhis süreci:**

1. İlk düşünce: "Race condition olabilir" - Hayır, @MainActor kullanıyoruz
2. İkinci düşünce: "Optional unwrapping" - Hayır, guard let var
3. **Eureka anı:** Xcode Memory Graph ile baktık - string'in memory'si deallocate olmuş!

**Neden oluyordu:**

Swift'te String bir reference type. Async işlem sırasında original string deallocate olunca, annotation'daki referans "dangling pointer" oluyordu.

```swift
// Sorunlu kod
func addAnnotation(text: String) {
    let annotation = Annotation(text: text)  // text'in referansını tutuyor
    Task {
        await supabase.save(annotation)  // Bu sırada text deallocate olabilir!
    }
}
```

**Çözüm:** Annotation'ı JSON'a çevirip tekrar parse ederek yeni string allocation:

```swift
// Models.swift - Annotation extension
var safeForJSON: Annotation {
    // String'leri yeniden allocate et
    let encoder = JSONEncoder()
    let data = try! encoder.encode(self)
    return try! JSONDecoder().decode(Annotation.self, from: data)
}

// Kullanım
let safeAnnotation = annotation.safeForJSON
await supabase.save(safeAnnotation)
```

**Öğrenilen ders:** Async işlemlerde value type'ların kopyalandığından emin ol. String gibi "değer gibi davranan referans tipleri"ne dikkat!

---

### Bug #2: Sonsuz Loop - Combine Karadeliği 🌀

**Sorun:** Uygulama açılınca CPU %100'e çıkıyor, UI donuyor.

**Teşhis:**

Instruments ile CPU profiling yaptık. `LibraryViewModel.init()` sürekli çağrılıyordu.

**Neden oluyordu:**

```swift
// Sorunlu kod
struct LibraryView: View {
    @StateObject var viewModel = LibraryViewModel()  // ✓ Doğru

    var body: some View {
        NavigationView {
            List(viewModel.files) { file in
                NavigationLink {
                    PDFReaderView(viewModel: PDFReaderViewModel(file: file))  // Her render'da yeni ViewModel!
                } label: {
                    Text(file.name)
                }
            }
        }
    }
}
```

SwiftUI, body'yi her state değişikliğinde yeniden çalıştırıyor. `PDFReaderViewModel(file: file)` her seferinde yeni instance oluşturuyordu.

**Çözüm:**

```swift
// Düzeltilmiş kod
struct PDFReaderView: View {
    @StateObject private var viewModel: PDFReaderViewModel

    init(file: PDFDocumentMetadata) {
        // StateObject'i init'te oluştur, body'de değil
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(file: file))
    }
}
```

**Öğrenilen ders:** SwiftUI'da ViewModel'i body içinde oluşturma! `@StateObject` init'te, `@ObservedObject` parent'tan gelsin.

---

### Bug #3: Annotation Koordinat Kabusu 📍

**Sorun:** iPhone'da eklediğim vurgu, iPad'de farklı yerde görünüyor.

**Teşhis:**

Annotation koordinatlarını loglayınca gördük:
- iPhone: `CGRect(x: 50, y: 100, width: 200, height: 20)`
- iPad'de aynı annotation: Yanlış yerde!

**Neden oluyordu:**

Screen coordinate kullanıyorduk. Ama ekran boyutları farklı!

```
iPhone 14:       iPad Pro:
┌──────────┐     ┌─────────────────┐
│ PDF      │     │ PDF             │
│ ████     │     │                 │
│          │     │        ████     │  ← Aynı pixel koordinatı
│          │     │                 │     farklı yerde!
└──────────┘     └─────────────────┘
```

**Çözüm:** Percentage-based koordinatlar:

```swift
struct AnnotationRect: Codable {
    var x: CGFloat       // 0-100 arası yüzde
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    // Screen → Percentage
    static func fromScreen(_ rect: CGRect, pageSize: CGSize) -> AnnotationRect {
        AnnotationRect(
            x: (rect.origin.x / pageSize.width) * 100,
            y: (rect.origin.y / pageSize.height) * 100,
            width: (rect.width / pageSize.width) * 100,
            height: (rect.height / pageSize.height) * 100
        )
    }

    // Percentage → Screen
    func toScreen(pageSize: CGSize) -> CGRect {
        CGRect(
            x: (x / 100) * pageSize.width,
            y: (y / 100) * pageSize.height,
            width: (width / 100) * pageSize.width,
            height: (height / 100) * pageSize.height
        )
    }
}
```

**Öğrenilen ders:** Cross-device uygulamalarda mutlak koordinat kullanma, oransal düşün.

---

### Bug #4: Supabase Free Tier - Keep Alive ⏰

**Sorun:** Uygulama birkaç gün kullanılmayınca Supabase bağlantısı kopuyor.

**Neden oluyordu:**

Supabase free tier, 1 hafta inactivity sonrası projeyi "pause" ediyor.

**Çözüm:** KeepAliveService:

```swift
// Services/KeepAliveService.swift
@MainActor
class KeepAliveService {
    static let shared = KeepAliveService()

    func startKeepAlive() {
        // Her 6 günde bir basit sorgu at
        Timer.scheduledTimer(withTimeInterval: 6 * 24 * 60 * 60, repeats: true) { _ in
            Task {
                // Basit bir health check
                _ = try? await SupabaseService.shared.client.from("files").select("id").limit(1).execute()
                logInfo("KeepAlive", "Supabase pinged")
            }
        }
    }
}
```

**Öğrenilen ders:** Free tier servislerin sınırlarını bil, workaround planla.

---

### Bug #5: NaN/Infinity Koordinatlar 🔢

**Sorun:** Bazen annotation kaydedilmiyor, JSON encode hatası alıyoruz.

**Hata:**
```
invalidValue(nan, Swift.EncodingError.Context(...))
```

**Neden oluyordu:**

Bazı edge case'lerde bölme işlemi `0/0 = NaN` veya `1/0 = Infinity` üretiyordu.

```swift
let ratio = rect.width / pageSize.width  // pageSize.width = 0 ise Infinity!
```

**Çözüm:** Sanitize fonksiyonu:

```swift
struct AnnotationRect: Codable {
    // ...

    private static func sanitize(_ value: CGFloat) -> CGFloat {
        if value.isNaN || value.isInfinite {
            return 0
        }
        return max(0, min(100, value))  // 0-100 arası sınırla
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = Self.sanitize(x)
        self.y = Self.sanitize(y)
        self.width = Self.sanitize(width)
        self.height = Self.sanitize(height)
    }
}
```

**Öğrenilen ders:** Floating point aritmetiğe güvenme, edge case'leri handle et.

---

## 5. Potansiyel Tuzaklar - Mayın Haritası

### 🚨 Kritik Alanlar

#### 1. Memory Management - PDF'ler Büyük!

```
⚠️ MAYINLI ALAN: PDFReaderViewModel
```

100+ sayfalık PDF açıldığında tüm sayfaları memory'de tutmaya çalışırsan, uygulama crash olur.

**Tuzak:**
```swift
// YAPMA!
var allPageImages: [UIImage] = []
for i in 0..<document.pageCount {
    allPageImages.append(renderPage(i))  // 💥 Memory explosion
}
```

**Doğrusu:**
```swift
// Sadece görünen + komşu sayfaları cache'le
var pageCache: [Int: UIImage] = [:]  // Max 3-5 sayfa

func displayPage(_ pageNumber: Int) {
    // Önceki cache'i temizle
    pageCache = pageCache.filter { abs($0.key - pageNumber) <= 1 }

    // Yeni sayfaları yükle
    for i in (pageNumber-1)...(pageNumber+1) {
        if pageCache[i] == nil {
            pageCache[i] = renderPage(i)
        }
    }
}
```

#### 2. Async/Await - Task Cancellation

```
⚠️ MAYINLI ALAN: ChatViewModel.sendMessage()
```

Kullanıcı mesaj gönderirken sayfayı değiştirirse, Task devam eder mi?

**Tuzak:**
```swift
func sendMessage() async {
    isLoading = true
    let response = await gemini.send(message)  // Kullanıcı gitti, bu hala çalışıyor
    messages.append(response)  // 💥 View artık yok, crash!
    isLoading = false
}
```

**Doğrusu:**
```swift
private var sendTask: Task<Void, Never>?

func sendMessage() {
    sendTask?.cancel()  // Önceki task'ı iptal et

    sendTask = Task {
        isLoading = true

        do {
            let response = try await gemini.send(message)

            // Task iptal edildi mi kontrol et
            guard !Task.isCancelled else { return }

            messages.append(response)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

deinit {
    sendTask?.cancel()
}
```

#### 3. Supabase RLS - Row Level Security

```
⚠️ MAYINLI ALAN: Tüm veritabanı işlemleri
```

RLS policy unutursan, kullanıcılar birbirinin verilerini görebilir!

**Tuzak:**
```sql
-- RLS olmadan herkes her şeyi görür!
CREATE TABLE files (...);
```

**Doğrusu:**
```sql
-- RLS aktif
ALTER TABLE files ENABLE ROW LEVEL SECURITY;

-- Policy: Sadece kendi dosyalarını gör
CREATE POLICY "Users can view own files"
ON files FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Sadece kendi dosyalarını sil
CREATE POLICY "Users can delete own files"
ON files FOR DELETE
USING (auth.uid() = user_id);
```

#### 4. Config.plist - API Keys

```
⚠️ MAYINLI ALAN: Config.swift
```

API key'leri yanlışlıkla commit edersen, kötü niyetli kişiler kullanabilir.

**Kontrol listesi:**
- [ ] `Config.plist` .gitignore'da mı?
- [ ] GitHub'da yanlışlıkla push edilmedi mi?
- [ ] CI/CD environment variable kullanıyor mu?

#### 5. PDFKit Text Extraction - Encoding Issues

```
⚠️ MAYINLI ALAN: PDFTextExtractor
```

Bazı PDF'lerde text extraction çöp karakterler döndürüyor.

**Neden:** PDF font encoding sorunlu, özellikle eski PDF'ler veya scan edilmiş dokümanlar.

**Workaround:**
```swift
func extractText(from page: PDFPage) -> String {
    guard let text = page.string else { return "" }

    // Çöp karakterleri temizle
    let cleaned = text
        .replacingOccurrences(of: "\u{FFFD}", with: "")  // Replacement character
        .replacingOccurrences(of: "\0", with: "")        // Null character
        .trimmingCharacters(in: .controlCharacters)

    // Çok kısa ise muhtemelen OCR gerekli
    if cleaned.count < 10 && page.pageRef != nil {
        logWarning("PDF", "Page may need OCR: \(page.pageRef!.pageNumber)")
    }

    return cleaned
}
```

### 🔍 Edge Cases

| Durum | Risk | Handle |
|-------|------|--------|
| PDF 0 sayfa | Crash | Guard check |
| PDF 1000+ sayfa | Memory | Lazy loading |
| PDF şifreli | Açılmaz | Error message |
| PDF bozuk | Crash | Try-catch |
| Network yok | Data yok | Offline cache |
| Token expired | 401 error | Auto refresh |
| Gemini rate limit | 429 error | Exponential backoff |

---

## 6. Öğrenilen Dersler

### 🎓 Ders 1: "Önce Çalışsın, Sonra Güzel Olsun"

İlk versiyonda her şeyi mükemmel yapmaya çalıştım. Result: 3 hafta boyunca hiçbir şey çalışmadı.

**Yanlış yaklaşım:**
```
"Önce mükemmel bir error handling sistemi kurayım"
"Generic repository pattern olsun"
"Dependency injection container lazım"
→ 3 hafta sonra: Hala hello world aşamasında
```

**Doğru yaklaşım:**
```
1. Çalışan en basit versiyonu yap (hardcoded, ugly, çalışıyor)
2. Kullan, test et, sorunları bul
3. Refactor et, güzelleştir
4. Tekrarla
```

### 🎓 Ders 2: "Singleton Tembellik Değil, Gereklilik"

Başta "singleton kötü" diye her yere dependency injection yaptım. Sonuç: 50 satırlık init'ler, geçilemeyen parametreler.

**Gerçek:**
- iOS'ta AppDelegate/SceneDelegate zaten singleton
- SwiftUI'da `@EnvironmentObject` de bir nevi singleton
- Service katmanı için singleton mantıklı

**Singleton kullan:**
- Network servisleri
- Database servisleri
- Logging

**Singleton kullanma:**
- ViewModel'ler (her View'ın kendi instance'ı olmalı)
- Stateful objeler

### 🎓 Ders 3: "@MainActor Her Yerde"

Başta sadece "gerekli" yerlere `@MainActor` koydum. Sonuç: Rastgele crash'ler, "UI must be updated on main thread" hataları.

**Kural:** ViewModel ve Service'lerin hepsine `@MainActor` koy. Sonra gerçekten background'da çalışması gerekenleri ayır.

```swift
@MainActor  // Default olarak main thread
class MyViewModel: ObservableObject {

    func doHeavyWork() {
        Task.detached {  // Bilinçli olarak background'a al
            let result = await self.heavyComputation()
            await MainActor.run {
                self.result = result
            }
        }
    }
}
```

### 🎓 Ders 4: "Logging Hayat Kurtarır"

Production'da bir bug var, kullanıcı "çalışmıyor" diyor. Nasıl debug edeceksin?

**LoggingService'i ilk günden kur:**

```swift
// Her önemli işlemde log
func uploadFile() async {
    logInfo("Upload", "Starting upload: \(file.name)")

    do {
        let result = try await supabase.upload(file)
        logInfo("Upload", "Success: \(result.id)")
    } catch {
        logError("Upload", "Failed", error: error)
    }
}
```

### 🎓 Ders 5: "Cache'le, Ama Akıllıca"

Her şeyi cache'lemek = memory dolması.
Hiçbir şeyi cache'lememek = yavaş uygulama.

**Strateji:**
1. **Memory cache:** Sık erişilen, küçük veriler (current page image)
2. **Disk cache:** Büyük, nadir değişen veriler (PDF files)
3. **TTL (Time To Live):** Cache'in ne kadar süre geçerli olacağı

```swift
class CacheService {
    // Memory cache - max 50MB
    private var memoryCache = NSCache<NSString, AnyObject>()

    // Disk cache - max 500MB, 7 gün
    private let diskCachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    init() {
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50MB
        cleanOldDiskCache()
    }
}
```

### 🎓 Ders 6: "Error Handling Kullanıcı İçin"

Geliştirici olarak `NSError domain=... code=...` anlamlı. Kullanıcı için: "???"

**Kural:** Her hatanın kullanıcı dostu mesajı olmalı.

```swift
enum AppError: Error {
    case network(NetworkError)
    case storage(StorageError)

    var userMessage: String {
        switch self {
        case .network(.noConnection):
            return "İnternet bağlantınızı kontrol edin"
        case .network(.timeout):
            return "Sunucu yanıt vermiyor, lütfen tekrar deneyin"
        case .storage(.insufficientSpace):
            return "Cihazınızda yeterli alan yok"
        // ...
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .network:
            return "Wi-Fi veya mobil veri açık mı kontrol edin"
        // ...
        }
    }
}
```

---

## 7. Best Practice'ler - Altın Kurallar

### 📝 Kod Kalitesi

#### Rule #1: Bir Fonksiyon, Bir İş

```swift
// ❌ KÖTÜ
func handlePDF(url: URL) async {
    // Download
    // Parse
    // Extract text
    // Generate thumbnail
    // Save to database
    // Update UI
    // 200 satır kod...
}

// ✅ İYİ
func handlePDF(url: URL) async {
    let data = try await downloadPDF(url)
    let document = try parsePDF(data)
    let text = extractText(from: document)
    let thumbnail = await generateThumbnail(document)
    try await saveToDatabase(document, text: text, thumbnail: thumbnail)
    updateUI()
}
```

#### Rule #2: Guard Early, Return Early

```swift
// ❌ KÖTÜ - Nested if'ler
func processFile(file: File?) {
    if let file = file {
        if file.isValid {
            if file.size < maxSize {
                // Asıl iş burada
            }
        }
    }
}

// ✅ İYİ - Guard ve early return
func processFile(file: File?) {
    guard let file = file else { return }
    guard file.isValid else { return }
    guard file.size < maxSize else { return }

    // Asıl iş burada - düz, okunabilir
}
```

#### Rule #3: Magic Number Yok

```swift
// ❌ KÖTÜ
let chunks = text.split(every: 400)
if retryCount > 3 { throw error }
cache.setObject(data, forKey: key, cost: 1048576)

// ✅ İYİ
private enum Constants {
    static let chunkSize = 400
    static let maxRetryCount = 3
    static let maxCacheSizeBytes = 1024 * 1024  // 1MB
}

let chunks = text.split(every: Constants.chunkSize)
if retryCount > Constants.maxRetryCount { throw error }
cache.setObject(data, forKey: key, cost: Constants.maxCacheSizeBytes)
```

### 🧪 Test Stratejisi

#### Unit Test - Service Layer

```swift
class RAGChunkerTests: XCTestCase {
    var sut: RAGChunker!

    override func setUp() {
        sut = RAGChunker()
    }

    func testChunkingPreservesPageMarkers() {
        let text = "--- Sayfa 1 ---\nİçerik\n--- Sayfa 2 ---\nDaha fazla içerik"
        let chunks = sut.chunk(text)

        XCTAssertTrue(chunks[0].pageNumber == 1)
        XCTAssertTrue(chunks[1].pageNumber == 2)
    }

    func testEmptyTextReturnsEmptyArray() {
        let chunks = sut.chunk("")
        XCTAssertTrue(chunks.isEmpty)
    }
}
```

#### Mock'lar - Dependency Isolation

```swift
// Mock service for testing
class MockGeminiService: GeminiServiceProtocol {
    var mockResponse: String = "Test response"
    var shouldFail = false

    func sendMessage(_ message: String) async throws -> String {
        if shouldFail {
            throw AppError.ai(.requestFailed)
        }
        return mockResponse
    }
}

// Test with mock
func testChatViewModelHandlesError() async {
    let mockGemini = MockGeminiService()
    mockGemini.shouldFail = true

    let viewModel = ChatViewModel(geminiService: mockGemini)
    await viewModel.sendMessage("Test")

    XCTAssertNotNil(viewModel.errorMessage)
}
```

### 🔒 Güvenlik

#### API Key Güvenliği

```swift
// Config.swift
enum Config {
    static var geminiAPIKey: String {
        // 1. Önce environment variable dene (CI/CD için)
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            return envKey
        }

        // 2. Config.plist'ten oku
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let key = config["GeminiAPIKey"] as? String else {
            fatalError("Config.plist not found or GeminiAPIKey missing")
        }

        // 3. Obfuscated key ise decode et
        if key.hasPrefix("OBF:") {
            return deobfuscate(key)
        }

        return key
    }
}
```

#### Input Validation

```swift
func validateFileName(_ name: String) -> Result<String, ValidationError> {
    // Length check
    guard name.count >= 1 && name.count <= 255 else {
        return .failure(.invalidLength)
    }

    // Character check
    let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
    guard name.rangeOfCharacter(from: invalidChars) == nil else {
        return .failure(.invalidCharacters)
    }

    // Extension check
    guard name.hasSuffix(".pdf") else {
        return .failure(.invalidExtension)
    }

    return .success(name)
}
```

### ⚡ Performance

#### Lazy Loading

```swift
struct LibraryView: View {
    @StateObject var viewModel = LibraryViewModel()

    var body: some View {
        ScrollView {
            LazyVStack {  // ✅ Sadece görünen öğeleri render et
                ForEach(viewModel.files) { file in
                    PDFCardView(file: file)
                        .onAppear {
                            // Pagination: Son öğeye yaklaşınca daha fazla yükle
                            if file == viewModel.files.last {
                                viewModel.loadMore()
                            }
                        }
                }
            }
        }
    }
}
```

#### Debouncing

```swift
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [SearchResult] = []

    private var searchTask: Task<Void, Never>?

    init() {
        // Debounce: Her keystroke'ta aramak yerine 300ms bekle
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performSearch(text)
            }
            .store(in: &cancellables)
    }
}
```

---

## Son Söz

Bu dosyayı okuduysan, PolyglotReader'ın "neden" böyle tasarlandığını artık biliyorsun. Sadece "ne" yapıldığını değil, arkasındaki düşünce sürecini anladın.

Yazılım geliştirme bir yolculuk. Her bug bir ders, her refactor bir gelişme. Bu dosya, o yolculuğun haritası.

**Unutma:**
- Mükemmel kod diye bir şey yok, sadece "şu an için yeterince iyi" kod var
- Her karmaşık sistem basit parçalardan oluşur
- Dokümantasyon yazmak, gelecekteki kendine mektup yazmaktır

---

*Bu dosya her güncellendiğinde, sen biraz daha iyi bir geliştirici oluyorsun.*

---

**Son Güncelleme:** 2026-01-26
**Versiyon:** 1.0
