# PolyglotReader 📚

AI destekli akıllı PDF okuyucu ve analiz uygulaması.

## 🌟 Özellikler

- 📖 **PDF Okuyucu**: Gelişmiş PDF görüntüleme ve gezinme
- 🤖 **AI Asistan**: Google Gemini ile doküman analizi
- 🌍 **Çeviri**: Otomatik dil tanıma ve çeviri
- 📝 **Akıllı Notlar**: AI destekli not oluşturma
- 🎯 **Quiz**: Dokümandan otomatik quiz üretimi
- ☁️ **Cloud Sync**: Supabase ile senkronizasyon
- 🎨 **Vurgulama**: Renkli metin işaretleme ve notlar

## 🚀 Kurulum

### Gereksinimler

- Xcode 15.0+
- iOS 17.0+ / macOS 14.0+
- Swift 5.9+

### Adımlar

1. **Projeyi klonlayın**:
```bash
git clone <repository-url>
cd PolyglotReader
```

2. **Config.plist dosyasını oluşturun**:

Proje içinde zaten bir `Config.plist` dosyası var. Xcode'da bu dosyayı bulun ve API anahtarlarınızı girin:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GeminiAPIKey</key>
    <string>YOUR_GEMINI_API_KEY_HERE</string>
    <key>GeminiModelName</key>
    <string>gemini-1.5-pro</string>
    <key>SupabaseURL</key>
    <string>YOUR_SUPABASE_PROJECT_URL</string>
    <key>SupabaseAnonKey</key>
    <string>YOUR_SUPABASE_ANON_KEY</string>
</dict>
</plist>
```

3. **API Anahtarlarını Alın**:

#### Google Gemini API
1. https://aistudio.google.com/app/apikey adresine gidin
2. "Create API Key" butonuna tıklayın
3. Oluşturulan anahtarı `Config.plist` içindeki `GeminiAPIKey` alanına yapıştırın

#### Supabase
1. https://supabase.com adresine gidin ve proje oluşturun
2. Settings > API bölümünden:
   - **Project URL**'i `SupabaseURL` alanına
   - **anon/public key**'i `SupabaseAnonKey` alanına yapıştırın

3. SQL Editor'da aşağıdaki tabloları oluşturun:

```sql
-- Dosyalar tablosu
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_type TEXT NOT NULL,
    size INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat geçmişi tablosu
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Notlar/Annotations tablosu
CREATE TABLE annotations (
    id UUID PRIMARY KEY,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    page INT NOT NULL,
    type TEXT NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Storage bucket
INSERT INTO storage.buckets (id, name, public) 
VALUES ('user_files', 'user_files', false);
```

4. **Build ve Run**:
```bash
# Xcode'da
⌘ + B  # Build
⌘ + R  # Run
```

## 📁 Proje Yapısı

```
PolyglotReader/
├── Config.swift              # Yapılandırma yöneticisi
├── Config.plist             # API anahtarları (git'e eklenmez)
├── Services/
│   ├── GeminiService.swift  # Google Gemini entegrasyonu
│   └── SupabaseService.swift # Supabase entegrasyonu
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── LibraryViewModel.swift
│   └── ChatViewModel.swift
└── Views/
    ├── AuthView.swift
    ├── LibraryView.swift
    ├── NotebookView.swift
    └── ChatView.swift
```

## 🔒 Güvenlik

- ⚠️ **API anahtarlarınızı asla Git'e commit etmeyin!**
- `Config.plist` dosyası `.gitignore`'da yer alıyor
- Üretim ortamında backend üzerinden API anahtarları yönetin

## 🛠 Geliştirme

### Bağımlılıklar

```swift
dependencies: [
    .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.0.0"),
    .package(url: "https://github.com/google/generative-ai-swift.git", from: "0.5.0")
]
```

### Yapılandırmayı Doğrulama

Uygulamanın başlangıcında yapılandırmayı doğrulamak için:

```swift
// AppDelegate veya App init içinde
if !Config.validateConfiguration() {
    print("⚠️ Yapılandırma eksik! Config.plist dosyasını kontrol edin.")
}
```

## 📱 Platform Desteği

- ✅ iOS 17.0+
- ✅ macOS 14.0+
- ✅ iPad (native)

## 📄 Lisans

[Lisans bilgisi buraya eklenecek]

## 🤝 Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/amazing`)
3. Commit edin (`git commit -m 'Add amazing feature'`)
4. Push edin (`git push origin feature/amazing`)
5. Pull Request açın

## 📞 İletişim

Sorularınız için issue açabilirsiniz.

---

**Not**: Bu proje eğitim amaçlıdır. Üretim ortamında API anahtarlarını backend servisi üzerinden yönetin.
