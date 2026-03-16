# Corio Docs — Web UI Redesign Spec

## Overview

Redesign the PolyglotReader web application (`web/` directory) with a professional, warm, and trustworthy user experience. The PDF reader and AI interaction are the heart of the app. The redesign preserves all existing functionality while migrating from custom CSS to Tailwind + shadcn/ui.

**Brand:** Corio Docs
**Tagline:** "Belgeleriniz için AI destekli okuma asistanı"

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Brand name | Corio Docs | Short, professional, describes function |
| Landing page | Keep and redesign | First-time user onboarding, new design system |
| Scope | All 5 phases, sequential | Each phase leaves app in working state |
| Migration | Progressive | Old + new CSS coexist during transition, low risk |
| Color palette | Warm Cream + Terracotta | Claude + Apple aesthetic, approved via mockup |
| Translation popup | Frosted Light minimal tooltip | Target-language only, backdrop-blur, below selection |

## Tech Stack

### Existing (preserve)
- Next.js 16 (App Router), React 19, TypeScript
- Supabase (Auth, DB, Storage)
- `@google/generative-ai` (server-side)
- `pdfjs-dist` + `react-pdf`

### Add
- **shadcn/ui** + **Radix UI** — component library
- **Tailwind CSS** — utility-first styling (replaces custom CSS)
- **Framer Motion** — micro-animations, page transitions
- **Lucide React** — consistent icon set
- **next-themes** — light/dark/sepia mode
- **cmdk** — command palette (⌘+K)
- **Sonner** — toast notifications
- **Vaul** — mobile drawer/sheet

### Package Manager
- Current: npm (package-lock.json exists)
- Migration to pnpm is out of scope for this redesign — stay with npm for now
- All install commands use `npm install`

### State Management Migration
- Current: React Context (AnnotationContext) + hooks
- Target: Zustand stores (already installed, not used)
- Stores: `useThemeStore`, `useReaderStore`, `useLibraryStore`, `useChatStore`

## Design System — "Corio Design Language"

### Color Palette

```css
:root {
  /* Primary — Warm Cream */
  --background: #FDFAF6;
  --foreground: #2A2520;

  /* Surface layers */
  --surface-1: #F7F3EE;  /* card backgrounds */
  --surface-2: #F0EBE4;  /* hover states */
  --surface-3: #E4DDD5;  /* active states */

  /* Accent — Terracotta */
  --accent: #D4713C;
  --accent-hover: #C0632F;
  --accent-subtle: #FAF0E8;

  /* Semantic */
  --success: hsl(152 60% 42%);
  --warning: hsl(38 92% 55%);
  --destructive: hsl(0 72% 55%);
  --info: hsl(210 60% 52%);

  /* PDF Reader */
  --reader-bg: #FAF7F3;
  --highlight-yellow: #FEF08A;
  --highlight-green: #BBF7D0;
  --highlight-blue: #BFDBFE;
  --highlight-pink: #FBCFE8;

  /* Border */
  --border: #E0D8CF;
  --border-subtle: #EBE5DD;

  /* Shadows — warm tinted */
  --shadow-sm: 0 1px 2px rgba(42, 37, 32, 0.06);
  --shadow-md: 0 4px 12px rgba(42, 37, 32, 0.08);
  --shadow-lg: 0 12px 32px rgba(42, 37, 32, 0.12);
}

.dark {
  --background: #1C1917;
  --foreground: #EBE5DD;
  --surface-1: hsl(30 10% 13%);
  --surface-2: hsl(30 10% 16%);
  --surface-3: hsl(30 10% 20%);
  --accent: hsl(24 80% 60%);
  --border: hsl(30 10% 22%);
  --reader-bg: hsl(30 8% 12%);
}

.sepia {
  --background: #EDE4D3;
  --foreground: hsl(30 15% 18%);
  --surface-1: hsl(38 40% 88%);
  --surface-2: hsl(38 35% 84%);
  --surface-3: hsl(38 30% 78%);
  --accent: #D4713C;  /* same as light */
  --accent-hover: #C0632F;
  --accent-subtle: hsl(38 50% 88%);
  --border: hsl(36 25% 75%);
  --border-subtle: hsl(36 20% 80%);
  --reader-bg: hsl(38 50% 90%);
}
```

### Typography
- UI: Inter (sans-serif)
- Reading: Literata (serif, for PDF text overlay)
- Code: JetBrains Mono (monospace)

### Spacing
- 4px base scale: 4, 8, 12, 16, 24, 32px

### Radius
- sm: 6px, md: 10px, lg: 14px, xl: 20px, full: 9999px

### Motion
- Ease: cubic-bezier(0.22, 1, 0.36, 1)
- Fast: 150ms, Normal: 250ms, Slow: 400ms

## File Splitting Plan

Current violations of 400-line limit:

| File | Lines | Split Into |
|------|-------|-----------|
| PDFViewer.tsx | 973 | PDFViewer + PDFPage + usePDFRenderer + usePDFNavigation |
| rag.ts | 654 | rag-search.ts + rag-chunks.ts + rag-embeddings.ts |
| reader/page.tsx | 583 | page.tsx + ReaderLayout + useReaderState |
| ChatPanel.tsx | 498 | ChatPanel + ChatMessages + ChatInput + useChatSession |

Splitting happens as part of the progressive migration — each file is split when it gets redesigned.

## Existing Component Migration Map

Explicit mapping of existing components to their new counterparts:

| Existing File | Action | New File(s) |
|--------------|--------|------------|
| `SelectionPopup.tsx` + `.module.css` | Replace | `FloatingActionBar.tsx` (same functionality: highlight, note, translate, chat buttons) |
| `QuickTranslationPopup.tsx` + `.module.css` | Replace | `TranslationPopup.tsx` (Frosted Light redesign, minimal) |
| `ImageSelectionPopup.tsx` + `.module.css` | Merge into | `FloatingActionBar.tsx` (image actions added as conditional buttons) |
| `ChatIcons.tsx` (269 lines) | Replace with Lucide + keep brand | Most icons → Lucide React. `CorioLogo` extracted to `components/shared/CorioLogo.tsx` |
| `ProtectedRoute.tsx` | Keep | Stays at `components/auth/ProtectedRoute.tsx`, updated to use new design tokens |
| `PDFThumbnail.tsx` | Absorb | Logic merged into `PDFCard.tsx` (thumbnail rendering + metadata display) |
| `AnnotationContext.tsx` | Replace (Phase 5) | `stores/useReaderStore.ts` (Zustand) |

### CSS Modules to Remove (after migration)

These files are deleted when their corresponding page/component is migrated to Tailwind:

- `app/page.module.css` + `app/landing.module.css` → Phase 1 (landing page)
- `app/(auth)/login/login.module.css` → Phase 1 (login page)
- `app/library/library.module.css` → Phase 2
- `app/reader/[id]/reader.module.css` → Phase 3
- `app/notes/notes.module.css` → Phase 5
- `components/chat/ChatPanel.module.css` → Phase 4
- `components/reader/SelectionPopup.module.css` → Phase 4
- `components/reader/QuickTranslationPopup.module.css` → Phase 4
- `components/reader/ImageSelectionPopup.module.css` → Phase 4
- `components/annotations/AnnotationToolbar.module.css` → Phase 4

### Dead Files to Clean Up (Phase 1, step 0)

Remove before starting migration:
- `components/reader/PDFViewer.tsx.bak`
- `components/reader/PDFViewer.tsx.bak2`
- `components/reader/PDFViewer.tsx.bak3`
- `components/reader/PDFViewer.tsx.broken`
- `components/library/PDFThumbnail.tsx.bak`

## Target File Structure

```
src/
├── app/
│   ├── layout.tsx              # Root layout (theme provider, sidebar)
│   ├── page.tsx                # Landing page (redesigned)
│   ├── globals.css             # Design tokens + Tailwind
│   ├── (auth)/login/page.tsx   # Login page
│   ├── auth/callback/page.tsx  # OAuth callback (existing, untouched)
│   ├── library/page.tsx        # Library page
│   ├── reader/[id]/page.tsx    # PDF Reader page
│   ├── notes/page.tsx          # Notebook page
│   ├── settings/page.tsx       # Settings page
│   └── api/                    # API routes (if created later; currently none exist)
├── components/
│   ├── ui/                     # shadcn/ui (auto-generated)
│   ├── layout/
│   │   ├── AppSidebar.tsx
│   │   ├── MobileNav.tsx
│   │   ├── TopBar.tsx
│   │   └── CommandPalette.tsx
│   ├── library/
│   │   ├── PDFCard.tsx
│   │   ├── PDFGrid.tsx
│   │   ├── PDFList.tsx
│   │   ├── UploadArea.tsx
│   │   └── EmptyLibrary.tsx
│   ├── reader/
│   │   ├── PDFViewer.tsx
│   │   ├── PDFPage.tsx
│   │   ├── TranslationPopup.tsx    # Frosted Light minimal tooltip
│   │   ├── FloatingActionBar.tsx
│   │   ├── AnnotationToolbar.tsx
│   │   ├── AnnotationLayer.tsx
│   │   ├── ThumbnailSidebar.tsx
│   │   ├── ChatPanel.tsx
│   │   ├── PageNavigation.tsx
│   │   ├── ReadingProgress.tsx
│   │   └── ReaderToolbar.tsx
│   ├── chat/
│   │   ├── ChatMessage.tsx
│   │   ├── ChatInput.tsx
│   │   ├── SuggestedPrompts.tsx
│   │   └── TypingIndicator.tsx
│   ├── notebook/
│   │   ├── AnnotationCard.tsx
│   │   └── NotebookFilters.tsx
│   └── shared/
│       ├── CorioLogo.tsx        # Brand logo (extracted from ChatIcons.tsx)
│       ├── ThemeSwitcher.tsx
│       ├── LoadingSpinner.tsx
│       ├── EmptyState.tsx
│       └── ConfirmDialog.tsx
├── hooks/
│   ├── useAuth.ts              # Existing, updated
│   ├── useDocuments.ts         # Existing, updated
│   ├── usePDFRenderer.ts       # New, extracted from PDFViewer
│   ├── usePDFNavigation.ts     # New, extracted from PDFViewer
│   ├── useTextSelection.ts     # New
│   ├── useKeyboardShortcuts.ts # New
│   ├── useMediaQuery.ts        # New
│   ├── useTranslation.ts       # New
│   ├── useReaderState.ts       # New, extracted from reader page
│   └── useChatSession.ts       # New, extracted from ChatPanel
├── contexts/
│   └── AnnotationContext.tsx    # Existing, removed in Phase 5b (migrated to Zustand)
├── stores/
│   ├── useThemeStore.ts
│   ├── useReaderStore.ts
│   ├── useLibraryStore.ts
│   └── useChatStore.ts
├── lib/
│   ├── supabase.ts             # Existing, untouched
│   ├── gemini.ts               # Existing
│   ├── rag-search.ts           # Split from rag.ts
│   ├── rag-chunks.ts           # Split from rag.ts
│   ├── rag-embeddings.ts       # Split from rag.ts
│   ├── pdfCache.ts             # Existing
│   ├── pdfjs-config.ts         # Existing
│   ├── annotationSync.ts       # Existing
│   ├── chatSync.ts             # Existing
│   ├── thumbnailCache.ts       # Existing
│   └── utils.ts                # Utility functions
├── types/
│   └── models.ts               # Existing, extended
├── constants/
│   └── index.ts                # App-wide constants
└── styles/
    └── reader.css              # PDF reader specific styles
```

## Page Designs

### Landing Page (`/`)

Existing structure preserved (hero, features, how-it-works, CTA), redesigned with Corio Design Language:
- Warm gradient background (cream → soft amber)
- Brand: "Corio Docs" + tagline
- Google + Apple Sign-In CTAs
- Responsive: simplified on mobile

### Login Page (`/login`)

- Centered card (max-width: 420px)
- Warm gradient background
- Google + Apple OAuth (full width, branded)
- Email/password form (existing)
- Footer: terms of service link

### Library Page (`/library`)

- Desktop sidebar with folders/tags + main content grid
- **PDF Card:** thumbnail (3:4 aspect) + title (2 lines, ellipsis) + meta (date, size) + tags + reading progress bar
- **Interactions:** hover elevation, context menu, drag-and-drop upload
- **Controls:** grid/list toggle, search (300ms debounce), sort (name, date, size, last read)
- **Empty state:** illustrated prompt to upload first PDF

### PDF Reader (`/reader/[id]`) — Primary Focus

#### Layout by Breakpoint

**Desktop (≥1280px) — 3 panels:**
- Thumbnail sidebar (left, 72px, collapsible via ⌘+T)
- PDF content (center, flex-1, warm cream background)
- Chat panel (right, 300-400px, resizable via ⌘+J)

**Tablet (768-1279px) — 1 panel + drawers:**
- Thumbnail: hidden, toggle to open
- Chat: right slide-in sheet (Vaul)
- Annotation toolbar: floating bottom bar

**Mobile (<768px) — full-screen + sheets:**
- PDF full-screen, minimal top bar
- Chat: full-screen bottom sheet (drag up)
- Thumbnail: horizontal swipeable strip

#### Text Selection Flow (3-stage)

1. **User selects text** → Floating action bar appears above selection:
   `[🌐 Çevir] [🖌️ Vurgula] [📝 Not] [💬 Chat'e Gönder]`

2. **"Çevir" clicked** → Frosted Light popup below selection:
   - Target-language translation only (original is already selected)
   - Light semi-transparent background + backdrop-blur
   - Bottom row: medical term badge + `EN → TR` + copy icon
   - On mobile: mini bottom sheet

3. **"Vurgula" clicked** → Highlight with selected color, sync to Supabase

#### Quick Translation Mode

- Toggle in top bar
- When active: text selection skips the floating action bar, directly shows Frosted Light translation popup
- Faster flow: select → see translation → continue reading

#### Annotation System

- 4 colors (yellow, green, blue, pink) + custom
- 3 types: highlight, underline, strikethrough
- Hover on highlight → note tooltip
- Percentage-based coordinates (compatible with iOS app)
- Keyboard: 1-4 for color selection

#### AI Chat Panel

- Markdown rendering (react-markdown + remark-gfm)
- Clickable page references → PDF scrolls to that page
- Contextual suggested prompts (change per page)
- Streaming response (existing, preserved)
- Resizable panel width

#### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘+K | Command palette |
| ⌘+\ | Sidebar toggle |
| ⌘+J | Chat panel toggle |
| ⌘+T | Thumbnail sidebar toggle |
| ⌘+F | PDF search |
| ← → | Previous/next page |
| Space / Shift+Space | Scroll down/up |
| T | Translate selected text |
| H | Highlight selected text |
| N | Add note to selection |
| Esc | Close popup/panel |
| ⌘+1/2/3 | Switch theme |

### Notebook Page (`/notes`)

- Masonry or list layout
- Annotation cards: highlight color + text + source PDF + page reference
- Filters: color, PDF, date, search
- Click → navigate to PDF page
- Export: Markdown

### Settings Page (`/settings`)

- iOS Settings style, grouped sections with shadcn Card + Separator
- Sections: Account, Appearance (light/dark/sepia + font size), Reading, AI Assistant, Storage, About

### Command Palette (`⌘+K`)

- cmdk library, global search
- Search PDFs, navigate to pages, access settings
- Fuzzy search + recent items

## Responsive Breakpoints

| Breakpoint | Width | Layout |
|-----------|-------|--------|
| sm | 640px | Phone portrait |
| md | 768px | Tablet portrait / large phone landscape |
| lg | 1024px | Tablet landscape / small laptop |
| xl | 1280px | Laptop / desktop |
| 2xl | 1536px | Large screen |

**Critical thresholds:**
- `< lg`: Bottom nav, no sidebar, chat = bottom sheet
- `≥ lg`: Sidebar, resizable panels
- `< md`: Translation popup = bottom sheet
- `≥ md`: Translation popup = floating popover

## Migration Strategy

Progressive migration — old and new CSS coexist during transition:

1. Install Tailwind + shadcn/ui alongside existing custom CSS
2. Set up theme provider (next-themes) and design tokens
3. Build new components with Tailwind + shadcn
4. Migrate pages one at a time, replacing CSS Modules
5. After all pages migrated, remove old globals.css and CSS Modules
6. Migrate AnnotationContext → Zustand stores

## Implementation Phases

### Phase 0: Cleanup (Pre-migration)
0. Delete dead files (.bak, .bak2, .bak3, .broken)

### Phase 1: Foundation (Design System + Layout)
1. shadcn/ui setup + Tailwind config (color palette, typography)
2. Root layout + theme provider (next-themes)
3. AppSidebar + MobileNav
4. ThemeSwitcher (light/dark/sepia)
5. Landing page redesign
6. Login page redesign

### Phase 2: Library
7. PDFCard component
8. Library page (grid + list view)
9. Upload area (drag & drop)
10. Folder/tag filtering
11. Search + sort

### Phase 3: PDF Reader — Core
12. PDFViewer refactor + split (973 → ~4 files)
13. Page navigation + zoom controls
14. ThumbnailSidebar
15. Reading progress bar
16. Keyboard shortcuts (useKeyboardShortcuts)

### Phase 4: PDF Reader — AI Features
17. Text selection detection (useTextSelection)
18. FloatingActionBar
19. TranslationPopup (Frosted Light, minimal)
20. AnnotationToolbar + AnnotationLayer refactor
21. ChatPanel refactor + split (498 → ~4 files)
22. SuggestedPrompts (contextual)

### Phase 5a: Notebook + Settings + Command Palette
23. Notebook page
24. Settings page
25. Command palette (⌘+K)

### Phase 5b: Refactoring + Polish
26. Zustand migration (AnnotationContext → stores)
27. rag.ts split (654 → 3 files)
28. gemini.ts review (365 lines, split if needed)
29. Final responsive testing
30. Performance optimization (lazy loading, code splitting)
31. Animations & micro-interactions polish
32. Remove old globals.css utilities and remaining CSS Modules

## Constraints

1. **Do not touch backend services** — `lib/gemini.ts`, `lib/rag*.ts`, `lib/supabase.ts`, `lib/annotationSync.ts`, `lib/chatSync.ts` contain working business logic. Refactor their interfaces during migration but preserve behavior.
2. **Preserve Supabase client** — `lib/supabase.ts` existing config
3. **Server components preferred** — data fetching on server, interactivity on client
4. **Turkish UI** — all user-facing text in Turkish
5. **Accessibility** — ARIA labels, keyboard navigation, focus management
6. **Mobile-first** — design mobile first, expand to desktop
7. **Incremental** — each phase ends with working application
8. **Error states** — every component has loading, empty, error states
9. **Preserve pdfjs-dist infrastructure** — `public/pdf.worker.min.mjs` and `lib/pdfjs-config.ts` must remain untouched during PDFViewer refactor
10. **Package manager** — use npm (existing lockfile), not pnpm for this project
11. **Preserve react-pdf CSS imports** — `globals.css` imports `react-pdf/dist/Page/AnnotationLayer.css` and `TextLayer.css`; these must survive the globals.css migration
12. **globals.css (549 lines)** — progressively thin as CSS Modules are removed per phase; do not delete all at once
