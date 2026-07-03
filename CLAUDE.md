# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PolyglotReader (Corio Docs) is an AI-powered PDF reader and analysis application for iOS/macOS built with SwiftUI, with a companion Next.js web application. It integrates Google Gemini for document analysis (translation, summarization, quiz generation, RAG-based chat) and Supabase for cloud storage, authentication, and vector search. The app UI and Gemini responses are configured for Turkish language.

## Build and Run

```bash
# Build the project
xcodebuild -scheme PolyglotReader -configuration Debug build

# Run tests
xcodebuild -scheme PolyglotReader -destination 'platform=iOS Simulator,name=iPhone 16' test

# Clean build folder
xcodebuild -scheme PolyglotReader clean

# SwiftLint (from project root)
./Scripts/swiftlint.sh
./Scripts/swiftlint-autocorrect.sh
```

### Web Application

```bash
cd web
pnpm install
pnpm dev        # Development server
pnpm build      # Production build
pnpm lint       # ESLint
pnpm typecheck  # tsc --noEmit
pnpm test       # Vitest
```

Use pnpm only — npm/yarn are not used in this repo (`pnpm-lock.yaml` is the lockfile).

## Configuration

The app requires a `Config.plist` file with API keys. This file is gitignored and must be created manually:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GeminiAPIKey</key>
    <string>YOUR_GEMINI_API_KEY_HERE</string>
    <key>GeminiModelName</key>
    <string>gemini-3-flash-preview</string>
    <key>SupabaseURL</key>
    <string>YOUR_SUPABASE_PROJECT_URL</string>
    <key>SupabaseAnonKey</key>
    <string>YOUR_SUPABASE_ANON_KEY</string>
</dict>
</plist>
```

Configuration is accessed via the `Config` enum in `Services/Config.swift`.

The web app requires environment variables: `GEMINI_API_KEY`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Optional: `GEMINI_MODEL` (defaults to `gemini-3-flash-preview`, see `web/src/lib/server/gemini.ts`).

## Architecture

### MVVM Pattern

The app follows MVVM (Model-View-ViewModel) architecture:

```
PolyglotReader/
├── App/                    # App entry point (PolyglotReaderApp.swift)
├── Models/                 # Data structures
├── Views/                  # SwiftUI views organized by feature
│   ├── Auth/               # Authentication (Google, Apple sign-in)
│   ├── Library/            # PDF library with folders, tags, sorting
│   ├── Reader/             # PDF reader with annotations, text selection
│   ├── PDF/                # PDFKit wrapper and coordinator
│   ├── Chat/               # AI chat with markdown rendering
│   ├── Quiz/               # AI-generated quizzes
│   ├── Notebook/           # Annotation dashboard and categories
│   ├── Settings/           # Settings and debug logs
│   └── Components/         # Shared UI components
├── ViewModels/             # Business logic and state management
├── Services/               # Backend integrations (modular sub-services)
│   ├── Supabase/           # Auth, database, storage, files, annotations, RAG, tags/folders
│   ├── Gemini/             # Chat, analysis, RAG operations
│   ├── RAG/                # Chunker, embeddings, search, context builder
│   ├── PDF/                # Text extraction, rendering, images, caching, metadata
│   └── (core services)     # Config, Logging, Cache, Network, Security, Keychain, etc.
├── Extensions/             # View, String, Color, Image extensions
├── Debug/                  # Memory debugger (debug builds only)
└── Resources/              # Localizable.strings (Turkish UI strings)
```

### App Entry Point

`PolyglotReaderApp.swift` initializes three `@StateObject`s: `AuthViewModel`, `SettingsViewModel`, `ErrorHandlingService`. After authentication, the app shows `MainTabView` with three tabs:
- **Kütüphane** (Library) → `LibraryView`
- **Defterim** (Notebook) → `NotebookView`
- **Ayarlar** (Settings) → `SettingsView`

### Service Layer

All services are singletons (`*.shared`) and `@MainActor`. They are organized into modular sub-files:

**1. SupabaseService** (`Services/Supabase/`)
- `SupabaseService.swift` - Main facade
- `SupabaseAuthService.swift` - Authentication (Apple, Google, OAuth)
- `SupabaseDatabaseService.swift` - Database operations
- `SupabaseFileService.swift` - File CRUD operations
- `SupabaseStorageService.swift` - Storage bucket operations
- `SupabaseAnnotationService.swift` - Annotation CRUD
- Extension files: `+Auth`, `+Files`, `+Chat`, `+Annotations`, `+RAG`, `+TagsFolders`, `+ImageMetadata`
- `SupabaseConfig.swift`, `SupabaseTypes.swift`

**2. GeminiService** (`Services/GeminiService.swift` + `Services/Gemini/`)
- `GeminiService.swift` - Main facade, chat sessions, multimodal inputs
- `GeminiChatService.swift` - Chat operations with conversation history
- `GeminiAnalysisService.swift` - Translation, summarization, auto-tagging, quiz generation
- `GeminiRAGService.swift` - RAG-specific operations with reranking
- `GeminiConfig.swift` - Model configuration

**3. RAGService** (`Services/RAGService.swift` + `Services/RAG/`)
- Professional hybrid search: Vector (cosine similarity) + BM25 (full-text) with RRF fusion
- `RAGChunker.swift` - Text chunking with overlap (400 words/chunk, 100 word overlap)
- `RAGEmbeddingService.swift` - Gemini `text-embedding-004` (768-dim vectors)
- `RAGSearchService.swift` - Semantic + keyword search via Supabase RPC
- `RAGContextBuilder.swift` - Context assembly for Gemini prompts
- `RAGConfig.swift`, `RAGModels.swift`

**4. PDFService** (`Services/PDFService.swift` + `Services/PDF/`)
- `PDFTextExtractor.swift` - Text extraction with page markers (`"--- Sayfa X ---"`)
- `PDFPageRenderer.swift` - Page rendering with pre-rendering (1 page ahead/behind)
- `PDFImageService.swift` - Image extraction from PDFs
- `PDFImageVisionHelper.swift` - Vision API analysis for extracted images
- `PDFAnnotationHandler.swift` - Annotation coordinate handling
- `PDFCacheService.swift`, `PDFPageCacheService.swift` - Caching layers
- `PDFMetadataService.swift` - PDF metadata extraction

**5. ErrorHandlingService** (`Services/ErrorHandlingService.swift` + 8 extension files)
- Comprehensive error handling: mapping, retry with exponential backoff, analytics, crash reporting
- State persistence across sessions
- UI presentation via banners and alerts
- Extensions: `+Types`, `+Handling`, `+Mapping`, `+Presentation`, `+Retry`, `+Analytics`, `+Crash`, `+Persistence`

**6. Other Core Services**
- `LoggingService.swift` - Centralized logging (debug/info/warning/error), stored in UserDefaults
- `CacheService.swift` - NSCache-based caching (100MB limit, LRU eviction)
- `NetworkMonitor.swift` - NWPathMonitor-based connectivity monitoring
- `KeychainService.swift` - Secure keychain operations
- `SecurityManager.swift` + `+Pinning`, `+Supabase` - Certificate pinning, ATS configuration
- `KeepAliveService.swift` - Periodic Supabase keep-alive pings
- `SmartSuggestionService.swift` - Context-aware chat suggestions
- `SyncQueue.swift` - Offline operation queuing for later sync
- `AppLocalization.swift` - Localization support
- `ErrorRetryPolicy.swift` - Retry policies for different error scenarios

### Models
- `Models.swift` - Core types: `User`, `Folder`, `Tag`, `PDFDocumentMetadata`, `ChatMessage`, `Annotation`, `AnnotationWithFile`, `AnnotationStats`, `UserPreferences`
- `AppError.swift` - App error types
- `ChatSuggestion.swift` - Smart chat suggestion model
- `PDFImageInfo.swift` / `PDFImageMetadata.swift` - PDF image data structures

### ViewModels
- `AuthViewModel.swift` - Authentication state, OAuth flow
- `LibraryViewModel.swift` + extensions (`+Loading`, `+Upload`, `+FileAccess`, `+Deletion`, `+Folders`, `+Tags`, `+Selection`, `+Sorting`, `+Thumbnails`, `+Summary`)
- `PDFReaderViewModel.swift` - PDF reading state, page navigation, annotations
- `ChatViewModel.swift` + `+ImageHandling`, `+Messaging` - AI chat with RAG
- `QuizViewModel.swift` - AI quiz generation and management
- `NotebookViewModel.swift` - Annotation notebook and categories
- `SettingsViewModel.swift` - User preferences and settings

### Data Flow

**Authentication Flow:**
1. User initiates OAuth login via `AuthViewModel`
2. `SupabaseAuthService` opens OAuth URL in browser
3. App receives callback via `onOpenURL` (scheme: `coriodocs://`)
4. Tokens extracted and session established
5. `AuthViewModel.currentUser` updated, triggering UI navigation to `MainTabView`

**PDF Reading + Chat Flow:**
1. User selects PDF in `LibraryView` → navigates to `PDFReaderView`
2. `PDFReaderViewModel.loadDocument()` downloads PDF via `SupabaseStorageService`
3. PDF rendered via `PDFKitView`/`PDFKitCoordinator`, annotations loaded from Supabase
4. User opens chat → `ChatViewModel` initializes with file context
5. On first message, `RAGService` chunks document and generates embeddings
6. User messages trigger hybrid search (vector + BM25) → relevant chunks retrieved
7. `RAGContextBuilder` assembles context → sent to `GeminiService` with user query
8. Chat history persisted to Supabase `chats` table

**Annotation System:**
- Annotations stored with percentage-based coordinates for device independence
- `AnnotationRect` uses percentages (0-100) instead of absolute coordinates
- Synced to Supabase `annotations` table with JSONB data field
- Supports highlights, underlines, strikethroughs with custom colors
- `NotebookView` provides a dashboard to browse all annotations across documents

### State Management

- `@StateObject` for view model ownership
- `@EnvironmentObject` for shared state (`AuthViewModel`, `SettingsViewModel`, `ErrorHandlingService`)
- `@Published` properties for reactive UI updates
- All ViewModels and services are `@MainActor` to ensure UI updates on main thread
- Proper `Task` cancellation throughout for lifecycle management

### Key Dependencies

**iOS/macOS (Swift Package Manager):**
```swift
.package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.38.1")
.package(url: "https://github.com/google/generative-ai-swift.git", from: "0.5.6")
```

**Web (pnpm):**
- Next.js 16, React 19, TypeScript
- `@supabase/supabase-js`, `@supabase/ssr`
- `@google/generative-ai` (server-side only)
- `pdfjs-dist`, `react-pdf` for PDF rendering
- `zustand` for state management
- `react-markdown`, `remark-gfm` for markdown rendering

## Web Application (`web/`)

Companion Next.js app using the `src/` layout — all paths below are relative to `web/src/`:

- `app/(auth)/` - Authentication pages
- `app/auth/callback/` - OAuth callback handler
- `app/(app)/library/` - PDF library browser
- `app/(app)/reader/[id]/` - PDF reader with annotations
- `app/(app)/notes/` - Notes/annotations viewer
- `app/(app)/settings/` - Settings page
- `app/api/gemini/generate/` - Server-side non-streaming Gemini endpoint
- `app/api/gemini/stream/` - Server-side streaming Gemini chat endpoint
- `app/api/gemini/embed/` - Server-side embedding generation
- `components/` - React components (PDFViewer, ChatPanel, AnnotationLayer, etc.)
- `hooks/` - Custom hooks (useAuth, useDocuments, useFileUpload, usePDFRenderer, usePDFNavigation)
- `lib/` - Client/server helpers (`lib/server/gemini.ts` holds the Gemini model config)
- `stores/` - Zustand stores

All Gemini API operations are server-side to protect API keys. Authentication is required for all API routes.

## Supabase Schema

### Core Tables

```sql
-- Files table
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_type TEXT NOT NULL,
    size INT NOT NULL,
    folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
    ai_category TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat history
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Annotations
CREATE TABLE annotations (
    id UUID PRIMARY KEY,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    page INT NOT NULL,
    type TEXT NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Document chunks for RAG
CREATE TABLE document_chunks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index INT NOT NULL,
    content TEXT NOT NULL,
    page_number INT,
    embedding vector(768),       -- Gemini text-embedding-004 dimension
    ts_content tsvector,         -- Full-text search (auto-populated via trigger)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Reading progress (page, scroll position, zoom)
CREATE TABLE reading_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    file_id UUID REFERENCES files(id) ON DELETE CASCADE NOT NULL,
    page INTEGER NOT NULL DEFAULT 1,
    offset_x FLOAT8 NOT NULL DEFAULT 0,
    offset_y FLOAT8 NOT NULL DEFAULT 0,
    zoom_scale FLOAT8 NOT NULL DEFAULT 1.0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, file_id)
);

-- Folders (nested, per-user)
CREATE TABLE folders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#6366F1',
    parent_id UUID REFERENCES folders(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_folder_name_per_user_parent UNIQUE(user_id, parent_id, name)
);

-- Tags (per-user, supports AI auto-generation)
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#22C55E',
    is_auto_generated BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_tag_name_per_user UNIQUE(user_id, name)
);

-- File-Tag junction (many-to-many)
CREATE TABLE file_tags (
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (file_id, tag_id)
);

-- Storage bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('user_files', 'user_files', false);
```

### RPC Functions

- `match_document_chunks_v2` - Vector similarity search with threshold filtering
- `search_chunks_bm25` / `search_chunks_bm25_lang` - BM25 full-text search
- `hybrid_search_chunks` - Combined vector + BM25 with RRF (Reciprocal Rank Fusion)
- `search_image_captions` - Image caption similarity search
- `get_tags_with_count` / `get_folders_with_count` - Aggregation helpers

### SQL Migrations

Timestamped migration files live in `supabase/migrations/` and are applied with the Supabase CLI (`supabase db push`).

All tables have RLS (Row Level Security) enabled with `auth.uid() = user_id` policies.

## Testing

### Unit Tests (`PolyglotReaderTests/`)
- `Services/PDFServiceTests.swift`, `Services/CacheServiceTests.swift`
- `ViewModels/AuthViewModelTests.swift`, `ViewModels/ChatViewModelTests.swift`, `ViewModels/PDFReaderViewModelTests.swift`
- Test plan: `PolyglotReaderTests.xctestplan`

### UI Tests (`PolyglotReaderUITests/`)
- `Base/UITestBase.swift` - Base class for UI tests
- `LoginFlowUITests.swift` - Authentication flow tests
- `SettingsUITests.swift` - Settings screen tests

### Mocks (`PolyglotReaderTests/Mocks/`)
- `MockGeminiService.swift`, `MockSupabaseService.swift`, `MockPDFService.swift`, `MockRAGService.swift`

### Test Utilities
- `TestDataFactory.swift` - Test data generation
- `AsyncTestHelpers.swift` - Async/await test helpers

## Linting

SwiftLint is configured via `.swiftlint.yml` (Airbnb Swift Style Guide based):

- **Line length**: 120 warning / 150 error
- **File length**: 400 warning / 600 error
- **Function body**: 40 warning / 60 error
- **Force cast/try/unwrap**: error level
- **Custom rules**: No `print()` (use LoggingService), no hardcoded API keys, localization warnings
- **Analyzer rules**: `unused_import`, `unused_declaration`

**SwiftLint-excluded files** (tech debt, pending cleanup):
- `PDFReaderView.swift`, `MarkdownView.swift`, `LoggingService.swift`, `QuickTranslationPopup.swift`, `FlippablePDFCardView.swift`

## Platform Support

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+
- Web: Node.js 20.9+, Next.js 16

## Important Notes

- Never commit `Config.plist` - it contains sensitive API keys
- All ViewModels are `@MainActor` to ensure thread safety
- Gemini responses are configured for Turkish language
- RAG chunking uses page markers `"--- Sayfa X ---"` from `PDFTextExtractor`
- OAuth callback URL scheme is `coriodocs://` (configured in `Info.plist`, bundle: `com.corio.docs`)
- App Transport Security is strict: no arbitrary loads, no arbitrary web content loads, no local networking
- Logging can be viewed in app via Settings → Debug Logs
- Memory debugging available in debug builds via `MemoryDebugger`/`MemoryDebugView`
- Web app runs all Gemini operations server-side to protect API keys
- Coding rules are documented in `RULES.md` - follow them strictly
