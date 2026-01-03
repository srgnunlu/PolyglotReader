# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PolyglotReader is an AI-powered PDF reader and analysis application for iOS/macOS built with SwiftUI. It integrates Google Gemini for document analysis and Supabase for cloud storage and authentication.

## Build and Run

```bash
# Build the project
xcodebuild -scheme PolyglotReader -configuration Debug build

# Run in Xcode
# ⌘ + B  (Build)
# ⌘ + R  (Run)

# Clean build folder
xcodebuild -scheme PolyglotReader clean
```

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
    <string>gemini-1.5-pro</string>
    <key>SupabaseURL</key>
    <string>YOUR_SUPABASE_PROJECT_URL</string>
    <key>SupabaseAnonKey</key>
    <string>YOUR_SUPABASE_ANON_KEY</string>
</dict>
</plist>
```

Configuration is accessed via the `Config` enum in `Services/Config.swift`.

## Architecture

### MVVM Pattern

The app follows MVVM (Model-View-ViewModel) architecture:

- **Models/** - Data structures (`User`, `PDFDocumentMetadata`, `Annotation`, `ChatMessage`, etc.)
- **Views/** - SwiftUI views organized by feature (Auth, Library, Reader, Chat, Quiz, Settings, Notebook)
- **ViewModels/** - Business logic and state management (`AuthViewModel`, `PDFReaderViewModel`, `ChatViewModel`, etc.)
- **Services/** - Backend integrations and utilities

### Service Layer

**Core Services:**

1. **GeminiService** (`Services/GeminiService.swift`)
   - Singleton service (`GeminiService.shared`)
   - Handles all Google Gemini API interactions
   - Manages chat sessions with conversation history
   - Supports multimodal inputs (text + images)
   - Network monitoring with automatic retry logic
   - System instruction configures Gemini as a PDF analysis assistant with Turkish responses

2. **SupabaseService** (`Services/SupabaseService.swift`)
   - Singleton service (`SupabaseService.shared`)
   - Authentication (Apple, Google, OAuth)
   - File storage and retrieval
   - Database operations (annotations, chats, files)
   - Real-time subscriptions support

3. **RAGService** (`Services/RAGService.swift`)
   - Retrieval-Augmented Generation for context-aware chat
   - Text chunking with overlap (400 words per chunk, 100 word overlap)
   - Embedding generation via Gemini API
   - Semantic search using Supabase vector search
   - Stores chunks in `document_chunks` table with embeddings

4. **PDFService** (`Services/PDFService.swift`)
   - PDF loading and text extraction
   - Page rendering and thumbnail generation
   - Uses PDFKit for all PDF operations

5. **LoggingService** (`Services/LoggingService.swift`)
   - Centralized logging with levels (debug, info, warning, error)
   - Logs stored in UserDefaults for debug view
   - Global logging functions: `logDebug()`, `logInfo()`, `logWarning()`, `logError()`

### Data Flow

**Authentication Flow:**
1. User initiates OAuth login via `AuthViewModel`
2. `SupabaseService` opens OAuth URL in browser
3. App receives callback via `onOpenURL` in `PolyglotReaderApp`
4. Tokens extracted and session established
5. `AuthViewModel.currentUser` updated, triggering UI navigation

**PDF Reading + Chat Flow:**
1. User selects PDF in `LibraryView` → navigates to `PDFReaderView`
2. `PDFReaderViewModel.loadDocument()` downloads PDF via `SupabaseService`
3. PDF rendered using PDFKit, annotations loaded from Supabase
4. User opens chat → `ChatViewModel` initializes with file context
5. On first message, `RAGService` chunks document and generates embeddings
6. User messages trigger semantic search → relevant chunks retrieved
7. Context + user query sent to `GeminiService` for response
8. Chat history persisted to Supabase `chats` table

**Annotation System:**
- Annotations stored with percentage-based coordinates for device independence
- `AnnotationRect` uses percentages (0-100) instead of absolute coordinates
- Synced to Supabase `annotations` table with JSONB data field
- Supports highlights, underlines, strikethroughs with custom colors

### State Management

- `@StateObject` for view model ownership
- `@EnvironmentObject` for shared state (`AuthViewModel`, `SettingsViewModel`)
- `@Published` properties for reactive UI updates
- All services are `@MainActor` to ensure UI updates on main thread

### Key Dependencies

```swift
.package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.38.1")
.package(url: "https://github.com/google/generative-ai-swift.git", from: "0.5.6")
```

## Supabase Schema

The app expects these tables in Supabase:

```sql
-- Files table
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_type TEXT NOT NULL,
    size INT NOT NULL,
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

-- Document chunks for RAG (expected by RAGService)
CREATE TABLE document_chunks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index INT NOT NULL,
    content TEXT NOT NULL,
    page_number INT,
    embedding vector(768),  -- Gemini text-embedding-004 dimension
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('user_files', 'user_files', false);
```

## Platform Support

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Important Notes

- Never commit `Config.plist` - it contains sensitive API keys
- All ViewModels are `@MainActor` to ensure thread safety
- Gemini responses are configured for Turkish language
- RAG chunking uses page markers `"--- Sayfa X ---"` from `PDFService.extractText()`
- OAuth callback URL scheme is `polyglotreader://login-callback`
- Logging can be viewed in app via Settings → Debug Logs
