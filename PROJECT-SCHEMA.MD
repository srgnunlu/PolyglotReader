# PolyglotReader - Project Schema

## Project Identity
- **Name**: PolyglotReader
- **Purpose**: AI-powered PDF reader and analysis application for iOS/macOS
- **Type**: Native iOS/macOS App (SwiftUI)
- **Status**: Development Complete → Production Readiness Phase

## Core Features
1. **PDF Reading & Annotation** - View PDFs, highlight, underline, add notes
2. **AI Chat Integration** - Gemini-powered document Q&A with RAG
3. **Cloud Sync** - Supabase authentication and storage
4. **Quiz Generation** - AI-generated quizzes from document content
5. **Notebook** - Personal notes linked to documents

## Technical Architecture

### Tech Stack
- **Frontend**: SwiftUI (iOS 17.0+ / macOS 14.0+)
- **AI Service**: Google Gemini API (gemini-1.5-pro)
- **Backend**: Supabase (Auth, Database, Storage)
- **PDF Engine**: PDFKit
- **Architecture**: MVVM

### File Structure
PolyglotReader/
├── Models/
│   ├── User.swift
│   ├── PDFDocumentMetadata.swift
│   ├── Annotation.swift
│   └── ChatMessage.swift
├── Views/
│   ├── Auth/
│   ├── Library/
│   ├── Reader/
│   ├── Chat/
│   ├── Quiz/
│   ├── Settings/
│   └── Notebook/
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── PDFReaderViewModel.swift
│   ├── ChatViewModel.swift
│   └── ...
├── Services/
│   ├── Config.swift
│   ├── GeminiService.swift
│   ├── Gemini/
│   ├── SupabaseService.swift
│   ├── Supabase/
│   ├── RAGService.swift
│   ├── RAG/
│   ├── PDFService.swift
│   ├── PDF/
│   └── LoggingService.swift
└── Resources/
└── Config.plist (gitignored)

### Key Technical Decisions
- **Singleton Services**: GeminiService.shared, SupabaseService.shared for centralized access
- **@MainActor ViewModels**: Thread safety for UI updates
- **Percentage-based Annotations**: Device-independent coordinate system
- **RAG with 768-dim Embeddings**: Gemini text-embedding-004 for semantic search

## Production Readiness Phases

- ✅ Phase 1: Code Quality & Static Analysis - COMPLETE
  - ✅ SwiftLint integration (0 errors, 0 warnings)
  - ✅ SupabaseService refactored (7 modules)
  - ✅ PDFService refactored (5 modules)
  - ✅ GeminiService refactored (4 modules)
  - ✅ RAGService refactored (4 modules)
  - ✅ PDFImageService refactoring (Phase 1-F)
  - ✅ All services lint-clean
  - ✅ Localization foundation added
- ✅ Phase 2: Security Audit & Hardening - COMPLETE
- ✅ Phase 3: Error Handling & Crash Prevention
- ✅ Phase 4: Performance Optimization - COMPLETE
  - ✅ CacheService with NSCache (100MB limit, LRU eviction)
  - ✅ Image+Optimized extension (downsampling, background thumbnails)
  - ✅ PDF page pre-rendering (1 page ahead/behind)
  - ✅ Search debouncing (300ms delay)
  - ✅ Memory warning handling
- ⬜ Phase 5: Memory Management & Leaks
- ⬜ Phase 6: Network Resilience
- ⬜ Phase 7: Test Coverage
- ⬜ Phase 8: Accessibility & Localization
- ⬜ Phase 9: App Store Preparation
- ⬜ Phase 10: CI/CD & Monitoring

## Current Status
- **Last Completed**: Phase 4: Performance Optimization
- **In Progress**: -
- **Next Up**: Phase 5: Memory Management & Leaks
- **Next Step**: Proceed to Prompt 5: Memory Management
- **Technical Debt**: SwiftLint exclusions remain for large UI/utility files (Phase 2)

## External Dependencies
- supabase-swift (2.38.1+)
- generative-ai-swift (0.5.6+)
