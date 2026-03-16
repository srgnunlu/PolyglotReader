# Corio Docs Web UI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Progressively migrate the PolyglotReader web app from custom CSS to Tailwind + shadcn/ui with warm cream/terracotta design system, preserving all existing functionality.

**Architecture:** Progressive migration — Tailwind and shadcn/ui installed alongside existing custom CSS. Pages migrated one at a time. Old CSS Modules deleted per-phase as pages are redesigned. Zustand replaces React Context in final phase.

**Tech Stack:** Next.js 16, React 19, TypeScript, Tailwind CSS, shadcn/ui, Framer Motion, Lucide React, next-themes, Sonner, cmdk, Vaul, Zustand

**Spec:** `docs/superpowers/specs/2026-03-16-web-ui-redesign-design.md`

**Verification commands (run from `web/` directory):**
```bash
npx tsc --noEmit          # Typecheck
npm run build             # Build
npm run lint              # Lint
npm run dev               # Visual verification at localhost:3000
```

---

## Chunk 1: Phase 0 (Cleanup) + Phase 1 (Foundation)

### Task 1: Delete dead files

**Files:**
- Delete: `src/components/reader/PDFViewer.tsx.bak`
- Delete: `src/components/reader/PDFViewer.tsx.bak2`
- Delete: `src/components/reader/PDFViewer.tsx.bak3`
- Delete: `src/components/reader/PDFViewer.tsx.broken`
- Delete: `src/components/library/PDFThumbnail.tsx.bak`

- [ ] **Step 1: Delete all backup/broken files**

```bash
cd web
rm src/components/reader/PDFViewer.tsx.bak
rm src/components/reader/PDFViewer.tsx.bak2
rm src/components/reader/PDFViewer.tsx.bak3
rm src/components/reader/PDFViewer.tsx.broken
rm src/components/library/PDFThumbnail.tsx.bak
```

- [ ] **Step 2: Verify build still passes**

```bash
npx tsc --noEmit
```
Expected: No errors (these files were not imported anywhere)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove dead backup and broken files"
```

---

### Task 2: Install Tailwind CSS v4

**Important:** This project uses Tailwind CSS v4 which configures themes via `@theme` directives in CSS, NOT via `tailwind.config.ts`. Do NOT create a `tailwind.config.ts` file.

**Files:**
- Create: `web/postcss.config.mjs`
- Modify: `web/src/app/globals.css` (add Tailwind directives at top)
- Modify: `web/package.json` (new dependencies)

- [ ] **Step 1: Install Tailwind CSS v4 and PostCSS**

Use context7 MCP tool to look up latest Tailwind CSS v4 installation docs before running.

```bash
cd web
npm install -D tailwindcss @tailwindcss/postcss postcss
```

- [ ] **Step 2: Create PostCSS config**

Create `web/postcss.config.mjs`:
```js
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};
export default config;
```

- [ ] **Step 3: Add Tailwind import to globals.css**

Add at the very top of `web/src/app/globals.css` (before the react-pdf imports):
```css
@import "tailwindcss";
```

The file now starts with:
```css
@import "tailwindcss";
@import "react-pdf/dist/Page/AnnotationLayer.css";
@import "react-pdf/dist/Page/TextLayer.css";
/* ... rest of existing CSS ... */
```

- [ ] **Step 4: Verify Tailwind works**

```bash
npm run dev
```
Open browser → inspect any element → add `class="text-red-500"` in DevTools → verify text turns red.

```bash
npx tsc --noEmit && npm run build
```
Expected: Build passes with no errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: install and configure Tailwind CSS"
```

---

### Task 3: Install shadcn/ui

**Files:**
- Create: `web/components.json`
- Create: `web/src/lib/utils.ts`
- Modify: `web/tailwind.config.ts` (if created by shadcn init)
- Modify: `web/src/app/globals.css` (shadcn CSS variables appended)

- [ ] **Step 1: Initialize shadcn/ui**

Use context7 MCP tool to look up latest shadcn/ui Next.js installation docs before running.

```bash
cd web
npx shadcn@latest init
```

When prompted:
- Style: **New York**
- Base color: **Neutral**
- CSS variables: **Yes**

- [ ] **Step 1b: Verify init did not overwrite Tailwind setup**

After init completes, check that `postcss.config.mjs` and `globals.css` were not overwritten. Re-apply Task 2 changes if needed (Tailwind import at top, react-pdf imports preserved).

- [ ] **Step 2: Install required shadcn components**

```bash
npx shadcn@latest add button card dialog dropdown-menu input label popover scroll-area separator sheet sidebar skeleton tabs tooltip avatar badge command context-menu resizable toggle toggle-group
```

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```
Expected: Build passes. shadcn components available at `@/components/ui/`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: initialize shadcn/ui with required components"
```

---

### Task 4: Install additional dependencies

**Files:**
- Modify: `web/package.json`

- [ ] **Step 1: Install Framer Motion, Lucide, next-themes, Sonner, cmdk, Vaul**

```bash
cd web
npm install framer-motion lucide-react next-themes sonner cmdk vaul
```

- [ ] **Step 2: Verify build**

```bash
npx tsc --noEmit && npm run build
```
Expected: Build passes.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: install framer-motion, lucide, next-themes, sonner, cmdk, vaul"
```

---

### Task 5: Configure Corio Design Tokens

**Files:**
- Modify: `web/src/app/globals.css` (add Corio design tokens)

This task adds the warm cream/terracotta palette, dark mode, and sepia mode CSS variables. These coexist with the old variables during progressive migration.

- [ ] **Step 1: Add Corio design tokens to globals.css**

After the Tailwind import and react-pdf imports, before the existing `:root` block, add a new section:

```css
/* ══════════════════════════════════════════════
   Corio Design Language — Design Tokens
   ══════════════════════════════════════════════ */

/* Light theme (default) */
.light, :root {
  --corio-background: #FDFAF6;
  --corio-foreground: #2A2520;
  --corio-surface-1: #F7F3EE;
  --corio-surface-2: #F0EBE4;
  --corio-surface-3: #E4DDD5;
  --corio-accent: #D4713C;
  --corio-accent-hover: #C0632F;
  --corio-accent-subtle: #FAF0E8;
  --corio-success: hsl(152 60% 42%);
  --corio-warning: hsl(38 92% 55%);
  --corio-destructive: hsl(0 72% 55%);
  --corio-info: hsl(210 60% 52%);
  --corio-reader-bg: #FAF7F3;
  --corio-highlight-yellow: #FEF08A;
  --corio-highlight-green: #BBF7D0;
  --corio-highlight-blue: #BFDBFE;
  --corio-highlight-pink: #FBCFE8;
  --corio-border: #E0D8CF;
  --corio-border-subtle: #EBE5DD;
  --corio-shadow-sm: 0 1px 2px rgba(42, 37, 32, 0.06);
  --corio-shadow-md: 0 4px 12px rgba(42, 37, 32, 0.08);
  --corio-shadow-lg: 0 12px 32px rgba(42, 37, 32, 0.12);
}

/* Dark theme */
.dark {
  --corio-background: #1C1917;
  --corio-foreground: #EBE5DD;
  --corio-surface-1: hsl(30 10% 13%);
  --corio-surface-2: hsl(30 10% 16%);
  --corio-surface-3: hsl(30 10% 20%);
  --corio-accent: hsl(24 80% 60%);
  --corio-accent-hover: hsl(24 80% 52%);
  --corio-accent-subtle: hsl(24 40% 18%);
  --corio-border: hsl(30 10% 22%);
  --corio-border-subtle: hsl(30 10% 18%);
  --corio-reader-bg: hsl(30 8% 12%);
  --corio-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.2);
  --corio-shadow-md: 0 4px 12px rgba(0, 0, 0, 0.3);
  --corio-shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.4);
}

/* Sepia theme */
.sepia {
  --corio-background: #EDE4D3;
  --corio-foreground: hsl(30 15% 18%);
  --corio-surface-1: hsl(38 40% 88%);
  --corio-surface-2: hsl(38 35% 84%);
  --corio-surface-3: hsl(38 30% 78%);
  --corio-accent: #D4713C;
  --corio-accent-hover: #C0632F;
  --corio-accent-subtle: hsl(38 50% 88%);
  --corio-border: hsl(36 25% 75%);
  --corio-border-subtle: hsl(36 20% 80%);
  --corio-reader-bg: hsl(38 50% 90%);
}
```

- [ ] **Step 2: Configure Tailwind v4 theme via @theme directive**

In `web/src/app/globals.css`, after the `@import "tailwindcss"` line and before the Corio CSS variables, add:

```css
@theme {
  /* Colors — mapped from CSS variables for Tailwind utility classes */
  --color-corio-bg: var(--corio-background);
  --color-corio-fg: var(--corio-foreground);
  --color-corio-surface-1: var(--corio-surface-1);
  --color-corio-surface-2: var(--corio-surface-2);
  --color-corio-surface-3: var(--corio-surface-3);
  --color-corio-accent: var(--corio-accent);
  --color-corio-accent-hover: var(--corio-accent-hover);
  --color-corio-accent-subtle: var(--corio-accent-subtle);
  --color-corio-border: var(--corio-border);
  --color-corio-border-subtle: var(--corio-border-subtle);
  --color-corio-reader: var(--corio-reader-bg);
  --color-highlight-yellow: var(--corio-highlight-yellow);
  --color-highlight-green: var(--corio-highlight-green);
  --color-highlight-blue: var(--corio-highlight-blue);
  --color-highlight-pink: var(--corio-highlight-pink);

  /* Typography */
  --font-sans: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
  --font-reading: "Literata", "Georgia", serif;
  --font-mono: "JetBrains Mono", "Fira Code", monospace;

  /* Border radius */
  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 14px;
  --radius-xl: 20px;

  /* Shadows */
  --shadow-sm: var(--corio-shadow-sm);
  --shadow-md: var(--corio-shadow-md);
  --shadow-lg: var(--corio-shadow-lg);
}
```

This generates utility classes like `bg-corio-bg`, `text-corio-fg`, `border-corio-border`, `font-reading`, etc.

**Do NOT create a `tailwind.config.ts`** — Tailwind v4 uses CSS-based configuration. If shadcn init created one, check if it is needed for shadcn component resolution; if not, delete it.

- [ ] **Step 3: Verify tokens work**

```bash
npm run dev
```
In browser DevTools on any element, add `class="bg-corio-bg text-corio-fg"` and verify warm cream background with dark text.

```bash
npx tsc --noEmit && npm run build
```
Expected: Build passes.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Corio Design Language tokens (light/dark/sepia)"
```

---

### Task 6: Set up theme provider (next-themes)

**Files:**
- Create: `web/src/components/shared/ThemeProvider.tsx`
- Modify: `web/src/app/layout.tsx`

- [ ] **Step 1: Create ThemeProvider wrapper**

Create `web/src/components/shared/ThemeProvider.tsx`:
```tsx
// Theme provider wrapper for next-themes with light/dark/sepia support
"use client";

import { ThemeProvider as NextThemesProvider } from "next-themes";
import { type ReactNode } from "react";

interface ThemeProviderProps {
  children: ReactNode;
}

export function ThemeProvider({ children }: ThemeProviderProps) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="light"
      themes={["light", "dark", "sepia"]}
      enableSystem={false}
      disableTransitionOnChange
    >
      {children}
    </NextThemesProvider>
  );
}
```

- [ ] **Step 2: Create Toaster setup**

Create `web/src/components/shared/Toaster.tsx`:
```tsx
// Global toast notification provider
"use client";

import { Toaster as SonnerToaster } from "sonner";

export function Toaster() {
  return (
    <SonnerToaster
      position="bottom-right"
      toastOptions={{
        style: {
          background: "var(--corio-surface-1)",
          color: "var(--corio-foreground)",
          border: "1px solid var(--corio-border)",
        },
      }}
    />
  );
}
```

- [ ] **Step 3: Update root layout**

Modify `web/src/app/layout.tsx` to wrap children with providers:
```tsx
import type { Metadata } from "next";
import { ThemeProvider } from "@/components/shared/ThemeProvider";
import { Toaster } from "@/components/shared/Toaster";
import "./globals.css";

export const metadata: Metadata = {
  title: "Corio Docs",
  description: "Akıllı Doküman Asistanı - AI-powered document analysis",
  keywords: ["PDF reader", "document analysis", "AI", "notes", "annotations", "Corio"],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="tr" suppressHydrationWarning>
      <body className="bg-corio-bg text-corio-fg antialiased">
        <ThemeProvider>
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  );
}
```

**Note:** Adding `bg-corio-bg text-corio-fg` to body may cause minor visual conflicts with pages not yet migrated (e.g., library page still using old CSS variables). This is expected during progressive migration and will resolve as each page is redesigned.

- [ ] **Step 4: Verify theme switching works**

```bash
npm run dev
```
Open browser → inspect `<html>` element → manually add `class="dark"` → verify background turns dark (#1C1917). Change to `class="sepia"` → verify warm parchment tone.

```bash
npx tsc --noEmit && npm run build
```
Expected: Build passes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ThemeProvider with light/dark/sepia support"
```

---

### Task 7: Create ThemeSwitcher component

**Files:**
- Create: `web/src/components/shared/ThemeSwitcher.tsx`

- [ ] **Step 1: Create ThemeSwitcher**

Create `web/src/components/shared/ThemeSwitcher.tsx`:
```tsx
// Theme toggle button — cycles through light/dark/sepia
"use client";

import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import { Sun, Moon, BookOpen } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const themes = [
  { value: "light", label: "Açık", icon: Sun },
  { value: "dark", label: "Koyu", icon: Moon },
  { value: "sepia", label: "Sepya", icon: BookOpen },
] as const;

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <Button variant="ghost" size="icon" className="h-8 w-8" />;
  }

  const current = themes.find((t) => t.value === theme) ?? themes[0];
  const Icon = current.icon;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8">
          <Icon className="h-4 w-4" />
          <span className="sr-only">Tema değiştir</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {themes.map((t) => (
          <DropdownMenuItem
            key={t.value}
            onClick={() => setTheme(t.value)}
            className={theme === t.value ? "bg-corio-accent-subtle" : ""}
          >
            <t.icon className="mr-2 h-4 w-4" />
            {t.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

- [ ] **Step 2: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ThemeSwitcher component (light/dark/sepia)"
```

---

### Task 8: Create AppSidebar (desktop)

**Files:**
- Create: `web/src/components/layout/AppSidebar.tsx`

- [ ] **Step 1: Create AppSidebar using shadcn Sidebar**

Create `web/src/components/layout/AppSidebar.tsx`:
```tsx
// Desktop sidebar — navigation, folders, user menu
"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import { Library, BookOpen, Notebook, Settings, LogOut, ChevronLeft } from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { ThemeSwitcher } from "@/components/shared/ThemeSwitcher";

const navItems = [
  { href: "/library", label: "Kütüphane", icon: Library },
  { href: "/notes", label: "Defterim", icon: Notebook },
  { href: "/settings", label: "Ayarlar", icon: Settings },
] as const;

export function AppSidebar() {
  const pathname = usePathname();

  return (
    <Sidebar className="border-r border-corio-border bg-corio-surface-1">
      <SidebarHeader className="p-4">
        <Link href="/library" className="flex items-center gap-2">
          <BookOpen className="h-6 w-6 text-corio-accent" />
          <span className="text-lg font-semibold text-corio-fg">Corio Docs</span>
        </Link>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>Navigasyon</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {navItems.map((item) => (
                <SidebarMenuItem key={item.href}>
                  <SidebarMenuButton
                    asChild
                    isActive={pathname === item.href}
                    className={
                      pathname === item.href
                        ? "bg-corio-accent-subtle text-corio-accent"
                        : "text-corio-fg/70 hover:bg-corio-surface-2"
                    }
                  >
                    <Link href={item.href}>
                      <item.icon className="h-4 w-4" />
                      <span>{item.label}</span>
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="p-3 flex flex-row items-center justify-between">
        <ThemeSwitcher />
        <SidebarTrigger className="h-8 w-8">
          <ChevronLeft className="h-4 w-4" />
        </SidebarTrigger>
      </SidebarFooter>
    </Sidebar>
  );
}
```

- [ ] **Step 2: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add AppSidebar component with navigation"
```

---

### Task 9: Create MobileNav (bottom tabs)

**Files:**
- Create: `web/src/components/layout/MobileNav.tsx`

- [ ] **Step 1: Create MobileNav**

Create `web/src/components/layout/MobileNav.tsx`:
```tsx
// Mobile bottom navigation — shown on screens < lg breakpoint
"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import { Library, Notebook, Settings } from "lucide-react";
import { motion } from "framer-motion";

const tabs = [
  { href: "/library", label: "Kütüphane", icon: Library },
  { href: "/notes", label: "Defterim", icon: Notebook },
  { href: "/settings", label: "Ayarlar", icon: Settings },
] as const;

export function MobileNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 flex items-center justify-around border-t border-corio-border bg-corio-bg/95 px-2 py-2 backdrop-blur-md lg:hidden">
      {tabs.map((tab) => {
        const isActive = pathname === tab.href;
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className="relative flex flex-col items-center gap-0.5 px-4 py-1"
          >
            {isActive && (
              <motion.div
                layoutId="mobile-nav-indicator"
                className="absolute inset-0 rounded-lg bg-corio-accent-subtle"
                transition={{ type: "spring", stiffness: 500, damping: 35 }}
              />
            )}
            <tab.icon
              className={`relative z-10 h-5 w-5 ${
                isActive ? "text-corio-accent" : "text-corio-fg/50"
              }`}
            />
            <span
              className={`relative z-10 text-[10px] font-medium ${
                isActive ? "text-corio-accent" : "text-corio-fg/50"
              }`}
            >
              {tab.label}
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
```

- [ ] **Step 2: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add MobileNav bottom tab bar"
```

---

### Task 10: Create app shell layout

**Files:**
- Create: `web/src/components/layout/AppShell.tsx`
- Modify: `web/src/app/layout.tsx`

This wraps authenticated pages with sidebar (desktop) + bottom nav (mobile). The landing page and login page are excluded.

- [ ] **Step 1: Create AppShell**

Create `web/src/components/layout/AppShell.tsx`:
```tsx
// App shell — sidebar (desktop) + bottom nav (mobile) for authenticated pages
"use client";

import { SidebarProvider } from "@/components/ui/sidebar";
import { AppSidebar } from "./AppSidebar";
import { MobileNav } from "./MobileNav";

interface AppShellProps {
  children: React.ReactNode;
}

export function AppShell({ children }: AppShellProps) {
  return (
    <SidebarProvider>
      <div className="flex min-h-screen w-full">
        <div className="hidden lg:block">
          <AppSidebar />
        </div>
        <main className="flex-1 pb-16 lg:pb-0">{children}</main>
        <MobileNav />
      </div>
    </SidebarProvider>
  );
}
```

- [ ] **Step 2: Create a group layout for authenticated routes**

Create `web/src/app/(app)/layout.tsx`:
```tsx
// Layout for authenticated app pages — includes sidebar and bottom nav
import { AppShell } from "@/components/layout/AppShell";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>;
}
```

Then move existing authenticated pages into the `(app)` route group:

```bash
cd web/src/app
mkdir -p "(app)"
mv library "(app)/library"
mv reader "(app)/reader"
mv notes "(app)/notes"
# settings doesn't exist yet — will be created in Phase 5a
```

**Important:** This is a Next.js route group `(app)` — the parentheses mean it does NOT affect the URL path. `/library` still works as before. All `router.push('/library')` etc. calls remain valid.

**Note on ProtectedRoute:** The existing `ProtectedRoute` wrapper stays per-page for now. It can be moved to `(app)/layout.tsx` as middleware later, but that is out of scope for this task.

- [ ] **Step 3: Verify routing still works**

```bash
npm run dev
```
- Visit `/library` → should show library page with sidebar on desktop
- Visit `/reader/[any-id]` → should show reader page
- Visit `/` → should show landing page (no sidebar)
- Visit `/login` → should show login page (no sidebar)

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add AppShell with sidebar + mobile nav for authenticated routes"
```

---

### Task 11: Add Google Fonts (Inter, Literata, JetBrains Mono)

**Files:**
- Modify: `web/src/app/layout.tsx`

- [ ] **Step 1: Add font imports to layout**

Update `web/src/app/layout.tsx` to import Google Fonts via `next/font`:
```tsx
import type { Metadata } from "next";
import { Inter, Literata, JetBrains_Mono } from "next/font/google";
import { ThemeProvider } from "@/components/shared/ThemeProvider";
import { Toaster } from "@/components/shared/Toaster";
import "./globals.css";

const inter = Inter({
  subsets: ["latin", "latin-ext"],
  variable: "--font-sans",
  display: "swap",
});

const literata = Literata({
  subsets: ["latin", "latin-ext"],
  variable: "--font-reading",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Corio Docs",
  description: "Akıllı Doküman Asistanı - AI-powered document analysis",
  keywords: ["PDF reader", "document analysis", "AI", "notes", "annotations", "Corio"],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="tr" suppressHydrationWarning>
      <body
        className={`${inter.variable} ${literata.variable} ${jetbrainsMono.variable} font-sans bg-corio-bg text-corio-fg antialiased`}
      >
        <ThemeProvider>
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  );
}
```

- [ ] **Step 2: Verify fonts load**

```bash
npm run dev
```
Open browser → inspect body → verify `font-family` includes Inter.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Inter, Literata, JetBrains Mono fonts"
```

---

### Task 12: Redesign landing page

**Files:**
- Modify: `web/src/app/page.tsx` (rewrite with Tailwind + Framer Motion)
- Delete: `web/src/app/page.module.css`
- Delete: `web/src/app/landing.module.css`

- [ ] **Step 1: Read existing landing page**

Read `web/src/app/page.tsx` to understand the current structure, sections, and functionality that must be preserved (hero, features, how-it-works, CTA, Google/Apple sign-in, navigation).

- [ ] **Step 2: Rewrite landing page with Tailwind + Framer Motion**

Rewrite `web/src/app/page.tsx` using:
- Tailwind classes (no CSS Modules)
- Framer Motion for scroll-triggered animations and hero animation
- Corio design tokens (`bg-corio-bg`, `text-corio-accent`, etc.)
- Lucide icons replacing inline SVGs
- Brand name: "Corio Docs"
- Tagline: "Belgeleriniz için AI destekli okuma asistanı"
- Warm gradient hero background
- Google + Apple sign-in buttons
- Responsive layout (mobile-first)
- All Turkish text preserved

Key sections to preserve:
1. Navigation bar with logo and auth buttons
2. Hero section with tagline and CTA
3. Features grid (PDF reading, AI chat, translation, annotations)
4. How-it-works section
5. Footer with legal links

Target: ≤250 lines. If the rewrite exceeds 250 lines, extract into:
- `web/src/components/landing/HeroSection.tsx`
- `web/src/components/landing/FeaturesGrid.tsx`
- `web/src/components/landing/Footer.tsx`

- [ ] **Step 3: Delete old CSS Modules**

Note: `page.module.css` is already unused dead code (existing page imports `landing.module.css` only).

```bash
rm web/src/app/page.module.css
rm web/src/app/landing.module.css
```

- [ ] **Step 4: Verify**

```bash
npm run dev
```
Visit `/` — verify landing page renders correctly with new design.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: redesign landing page with Corio Design Language"
```

---

### Task 13: Redesign login page

**Files:**
- Modify: `web/src/app/(auth)/login/page.tsx` (rewrite with Tailwind)
- Delete: `web/src/app/(auth)/login/login.module.css`

- [ ] **Step 1: Read existing login page**

Read `web/src/app/(auth)/login/page.tsx` to understand current auth flow (email/password + Google OAuth + signup toggle).

- [ ] **Step 2: Rewrite login page with Tailwind + shadcn**

Rewrite using:
- Centered card (max-width 420px) with shadcn `Card`
- Warm gradient background (`bg-gradient-to-br from-corio-bg to-corio-accent-subtle`)
- shadcn `Input`, `Button`, `Label` components
- Google sign-in button (branded, full width)
- Apple sign-in button (branded, full width)
- Email/password form with signup toggle
- All existing `useAuth` hook calls preserved
- Footer link: "Giriş yaparak Kullanım Şartlarını kabul ediyorsunuz"
- Framer Motion entrance animation for card

- [ ] **Step 3: Delete old CSS Module**

```bash
rm web/src/app/(auth)/login/login.module.css
```

- [ ] **Step 4: Verify**

```bash
npm run dev
```
Visit `/login` — verify login page renders, Google sign-in works.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: redesign login page with Corio Design Language"
```

---

## Chunk 2: Phase 2 (Library)

### Task 14: Create PDFCard component

**Files:**
- Create: `web/src/components/library/PDFCard.tsx`

- [ ] **Step 1: Read existing library page and PDFThumbnail**

Read `web/src/app/library/page.tsx` and `web/src/components/library/PDFThumbnail.tsx` to understand current card rendering, thumbnail generation, and metadata display.

- [ ] **Step 2: Create PDFCard component**

Create `web/src/components/library/PDFCard.tsx` combining PDFThumbnail logic + card design:
- shadcn `Card` base
- Thumbnail area (3:4 aspect ratio, skeleton loading)
- Title (2 lines max, ellipsis)
- Meta info (date, size)
- Tags
- Reading progress bar (thin, accent colored)
- Framer Motion: `whileHover={{ y: -2 }}` + shadow elevation
- Context menu (right-click): open, rename, move to folder, delete
- Uses `@/lib/thumbnailCache` for thumbnail rendering

Target: ≤200 lines.

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PDFCard component with thumbnail and metadata"
```

---

### Task 15: Create PDFGrid and PDFList components

**Files:**
- Create: `web/src/components/library/PDFGrid.tsx`
- Create: `web/src/components/library/PDFList.tsx`

- [ ] **Step 1: Create PDFGrid**

Grid layout for PDF cards using CSS Grid with responsive columns:
- `grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5`
- Renders `PDFCard` for each document
- Framer Motion staggered entrance animation

- [ ] **Step 2: Create PDFList**

List/table layout alternative:
- Each row: thumbnail (small), title, date, size, tags, progress
- Hover highlight
- Compact view for power users

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PDFGrid and PDFList layout components"
```

---

### Task 16: Create UploadArea and EmptyLibrary

**Files:**
- Create: `web/src/components/library/UploadArea.tsx`
- Create: `web/src/components/library/EmptyLibrary.tsx`

- [ ] **Step 1: Create UploadArea**

Drag-and-drop upload zone:
- Dashed border area that accepts PDF files
- Drag hover state (accent border + subtle background)
- Click to open file picker
- Upload progress indicator
- Uses existing Supabase upload logic from library page

- [ ] **Step 2: Create EmptyLibrary**

Empty state when user has no documents:
- Illustration/icon (Lucide `FileUp`)
- "Henüz belge yüklenmemiş" message
- Upload CTA button

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add UploadArea and EmptyLibrary components"
```

---

### Task 17: Redesign library page

**Files:**
- Modify: `web/src/app/(app)/library/page.tsx` (rewrite with Tailwind + new components)
- Delete: `web/src/app/(app)/library/library.module.css`

- [ ] **Step 1: Read existing library page**

Read the current library page to understand all functionality: document fetching, folder filtering, search, upload, navigation to reader.

- [ ] **Step 2: Rewrite library page**

Rewrite using new components:
- Top bar: page title + search input + view toggle (grid/list) + sort dropdown + upload button
- Main area: `PDFGrid` or `PDFList` based on view mode
- Empty state: `EmptyLibrary` when no documents
- Loading state: skeleton grid
- Search: instant filter with 300ms debounce
- Sort options: name, date, size, last read
- All existing `useDocuments` hook integration preserved
- Upload via `UploadArea` (drag onto page or click button)

- [ ] **Step 3: Delete old CSS Module**

```bash
rm web/src/app/(app)/library/library.module.css
```

- [ ] **Step 4: Verify**

```bash
npm run dev
```
Visit `/library` — verify document grid, search, upload all work.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: redesign library page with grid/list views and search"
```

---

## Chunk 3: Phase 3 (PDF Reader Core)

### Task 18: Extract PDF rendering hooks from PDFViewer

**Files:**
- Create: `web/src/hooks/usePDFRenderer.ts`
- Create: `web/src/hooks/usePDFNavigation.ts`

- [ ] **Step 1: Read existing PDFViewer.tsx (973 lines)**

Read `web/src/components/reader/PDFViewer.tsx` thoroughly. Identify:
- PDF loading/caching logic → `usePDFRenderer`
- Page navigation, zoom, keyboard nav → `usePDFNavigation`
- Text selection logic → stays for now (Phase 4)
- Rendering JSX → stays in PDFViewer (slimmed down)

- [ ] **Step 2: Extract usePDFRenderer hook**

Create `web/src/hooks/usePDFRenderer.ts`:
- PDF document loading via pdfCache
- Page rendering state (loading, error, document reference)
- Scale/zoom management
- Preloading logic (current ± 2 pages)
- Returns: `{ pdfDocument, isLoading, error, scale, setScale }`

- [ ] **Step 3: Extract usePDFNavigation hook**

Create `web/src/hooks/usePDFNavigation.ts`:
- Current page state
- Total pages
- goToPage, nextPage, prevPage functions
- Keyboard navigation (←→, Space, Shift+Space)
- Reading progress percentage
- Returns: `{ currentPage, totalPages, goToPage, nextPage, prevPage, progress }`

- [ ] **Step 4: Verify existing functionality preserved**

```bash
npx tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: extract usePDFRenderer and usePDFNavigation hooks"
```

---

### Task 19: Create new PDFViewer component

**Files:**
- Modify: `web/src/components/reader/PDFViewer.tsx` (rewrite, slimmed down)
- Create: `web/src/components/reader/PDFPage.tsx`

- [ ] **Step 1: Create PDFPage component**

Single page rendering component:
- Receives page number, scale, document reference
- Renders via react-pdf `<Page>`
- Handles individual page loading state
- Annotation layer overlay slot

- [ ] **Step 2: Rewrite PDFViewer**

Slim down PDFViewer to be a composition component:
- Uses `usePDFRenderer` and `usePDFNavigation` hooks
- Renders scrollable list of `PDFPage` components
- Virtual scrolling for large documents
- Warm cream reader background (`bg-corio-reader`)
- White PDF page with subtle shadow
- All Tailwind, no CSS Modules

Target: PDFViewer ≤250 lines, PDFPage ≤150 lines.

- [ ] **Step 3: Verify PDF rendering works**

```bash
npm run dev
```
Open a PDF in the reader → verify pages render, scrolling works, zoom works.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rewrite PDFViewer with extracted hooks and PDFPage component"
```

---

### Task 20: Create ThumbnailSidebar

**Files:**
- Create: `web/src/components/reader/ThumbnailSidebar.tsx`

- [ ] **Step 1: Create ThumbnailSidebar**

Left sidebar (72px wide) showing page thumbnails:
- Lazy-loaded miniature page renders
- Active page: accent border + slight scale
- Click to navigate
- Scroll sync with main PDF viewer
- Collapsible via toggle button or ⌘+T
- Uses shadcn `ScrollArea`

- [ ] **Step 2: Verify**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ThumbnailSidebar with scroll sync"
```

---

### Task 21: Create ReadingProgress and PageNavigation

**Files:**
- Create: `web/src/components/reader/ReadingProgress.tsx`
- Create: `web/src/components/reader/PageNavigation.tsx`

- [ ] **Step 1: Create ReadingProgress**

Thin progress bar at top of reader:
- Width = reading progress percentage
- Accent color, 2px height
- Smooth animation on progress change

- [ ] **Step 2: Create PageNavigation**

Bottom bar page controls:
- Previous/next page buttons
- "Sayfa X / Y" display
- Zoom controls (-, %, +)
- Uses `usePDFNavigation` hook data

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add ReadingProgress bar and PageNavigation controls"
```

---

### Task 22: Create useKeyboardShortcuts hook

**Files:**
- Create: `web/src/hooks/useKeyboardShortcuts.ts`

- [ ] **Step 1: Create global keyboard shortcuts hook**

Create `web/src/hooks/useKeyboardShortcuts.ts`:
- Registers global keyboard event listeners
- Supports modifier keys (⌘, Ctrl, Shift)
- Shortcuts map:
  - `⌘+K`: command palette
  - `⌘+\`: sidebar toggle
  - `⌘+J`: chat panel toggle
  - `⌘+T`: thumbnail toggle
  - `⌘+1/2/3`: theme switch
  - `Esc`: close popups
- Accepts a shortcuts config object
- Cleans up listeners on unmount

- [ ] **Step 2: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add useKeyboardShortcuts hook"
```

---

### Task 23: Redesign reader page

**Files:**
- Modify: `web/src/app/(app)/reader/[id]/page.tsx` (rewrite with new components)
- Create: `web/src/components/reader/ReaderToolbar.tsx`
- Delete: `web/src/app/(app)/reader/[id]/reader.module.css`

- [ ] **Step 1: Read existing reader page (583 lines)**

Read to understand all state management, component composition, and data flow.

- [ ] **Step 2: Create ReaderToolbar**

Bottom toolbar combining annotation tools + page nav:
- Highlight tool with color picker
- Underline and strikethrough tools
- Note button
- Page navigation (delegated to `PageNavigation`)
- Zoom controls

- [ ] **Step 3: Rewrite reader page**

3-panel responsive layout:
- Desktop: ThumbnailSidebar (left) + PDFViewer (center) + ChatPanel placeholder (right)
- Tablet: PDFViewer only, drawers for sidebar/chat
- Mobile: full-screen PDF
- Top bar: back link, document title, theme switcher, settings
- Bottom: ReaderToolbar
- ReadingProgress at very top
- All Tailwind, no CSS Modules
- Preserves AnnotationProvider context wrapper
- Preserves existing data loading from Supabase

Target: page.tsx ≤250 lines (state/logic extracted to hooks).

- [ ] **Step 4: Delete old CSS Module**

```bash
rm web/src/app/(app)/reader/[id]/reader.module.css
```

- [ ] **Step 5: Verify**

```bash
npm run dev
```
Open a PDF → verify 3-panel layout, page nav, zoom, keyboard shortcuts.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: redesign reader page with 3-panel responsive layout"
```

---

## Chunk 4: Phase 4 (PDF Reader AI Features)

### Task 24: Create useTextSelection and useMediaQuery hooks

**Files:**
- Create: `web/src/hooks/useTextSelection.ts`
- Create: `web/src/hooks/useMediaQuery.ts`

- [ ] **Step 1: Create text selection detection hook**

Detects when user selects text in the PDF viewer:
- Listens to `mouseup` and `touchend` events
- Gets selected text via `window.getSelection()`
- Computes selection bounding rect for popup positioning
- Determines which page the selection is on
- Returns: `{ selectedText, selectionRect, pageNumber, clearSelection }`
- Handles edge cases: cross-page selection, empty selection, image-only selection

- [ ] **Step 2: Create useMediaQuery hook**

Create `web/src/hooks/useMediaQuery.ts`:
```tsx
// Responsive breakpoint detection hook
"use client";

import { useEffect, useState } from "react";

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(query);
    setMatches(media.matches);

    const listener = (e: MediaQueryListEvent) => setMatches(e.matches);
    media.addEventListener("change", listener);
    return () => media.removeEventListener("change", listener);
  }, [query]);

  return matches;
}

// Convenience hooks for common breakpoints
export function useIsMobile() {
  return !useMediaQuery("(min-width: 768px)");
}

export function useIsDesktop() {
  return useMediaQuery("(min-width: 1024px)");
}
```

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add useTextSelection and useMediaQuery hooks"
```

---

### Task 25: Create FloatingActionBar

**Files:**
- Create: `web/src/components/reader/FloatingActionBar.tsx`

- [ ] **Step 1: Read existing SelectionPopup.tsx and ImageSelectionPopup.tsx**

Read both files to understand all actions offered after text/image selection.

- [ ] **Step 2: Create FloatingActionBar**

Appears above selected text with action buttons:
- `[🌐 Çevir] [🖌️ Vurgula] [📝 Not] [💬 Chat'e Gönder]`
- For image selection: `[🌐 Çeviri] [📋 Kopyala] [💬 Analiz Et]`
- Dark background with light text (high contrast pill)
- Positioned absolutely based on selection rect
- Framer Motion fade+scale entrance
- Viewport overflow handling (flip to below if near top)
- Keyboard shortcuts: T (translate), H (highlight), N (note)

Replaces: `SelectionPopup.tsx` + `ImageSelectionPopup.tsx`

- [ ] **Step 3: Verify build**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add FloatingActionBar for text/image selection"
```

---

### Task 26: Create TranslationPopup (Frosted Light)

**Files:**
- Create: `web/src/components/reader/TranslationPopup.tsx`
- Create: `web/src/hooks/useTranslation.ts`

- [ ] **Step 1: Create useTranslation hook**

Translation API integration:
- Calls existing `translateText` from `@/lib/gemini`
- Manages loading/error/result states
- Caches recent translations (session-based)
- Returns: `{ translate, translation, isTranslating, error }`

- [ ] **Step 2: Create TranslationPopup**

**Frosted Light** minimal tooltip:
- Appears below selected text
- Light semi-transparent background: `bg-white/85 backdrop-blur-md`
- Arrow pointing up to selection
- Shows only target-language translation (original is already selected)
- Bottom row: medical term badge (conditional) + `EN → TR` indicator + copy button
- Framer Motion: `scale(0.95) → scale(1)` + fade, 200ms
- Mobile: rendered as Vaul bottom sheet via `useMediaQuery`
- Loading: skeleton shimmer while translating

**Quick Translation Mode:**
- When translation mode is active in top bar toggle, FloatingActionBar is skipped
- Selection directly triggers TranslationPopup

Replaces: `QuickTranslationPopup.tsx`

- [ ] **Step 3: Delete old popup files**

```bash
rm web/src/components/reader/SelectionPopup.tsx
rm web/src/components/reader/SelectionPopup.module.css
rm web/src/components/reader/QuickTranslationPopup.tsx
rm web/src/components/reader/QuickTranslationPopup.module.css
rm web/src/components/reader/ImageSelectionPopup.tsx
rm web/src/components/reader/ImageSelectionPopup.module.css
```

- [ ] **Step 4: Verify**

```bash
npm run dev
```
Open PDF → select text → verify floating bar appears → click translate → verify Frosted Light popup.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Frosted Light TranslationPopup and useTranslation hook"
```

---

### Task 27: Refactor AnnotationToolbar and AnnotationLayer

**Files:**
- Modify: `web/src/components/reader/AnnotationToolbar.tsx` (rewrite with Tailwind)
- Modify: `web/src/components/reader/AnnotationLayer.tsx` (rewrite with Tailwind)
- Delete: `web/src/components/annotations/AnnotationToolbar.module.css`

- [ ] **Step 1: Rewrite AnnotationToolbar**

Move from `components/annotations/` to `components/reader/`:
- 4 color buttons (yellow, green, blue, pink) as circles
- 3 tool buttons: highlight, underline, strikethrough
- Undo/redo buttons
- All Tailwind, accent color for active tool
- Keyboard shortcuts: 1-4 for colors

- [ ] **Step 2: Rewrite AnnotationLayer**

SVG/CSS overlay for highlights:
- Renders highlight rects on correct page positions
- Percentage-based coordinates
- Hover on highlight → tooltip with note text
- Uses Corio highlight color tokens

- [ ] **Step 3: Delete old CSS Module and move file**

```bash
rm web/src/components/annotations/AnnotationToolbar.module.css
```
If the old `components/annotations/AnnotationToolbar.tsx` still exists, delete it (new one is in `components/reader/`).

- [ ] **Step 4: Verify annotations work**

```bash
npm run dev
```
Open PDF → highlight text → verify highlight persists → reload → verify annotation loaded from Supabase.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: redesign AnnotationToolbar and AnnotationLayer with Tailwind"
```

---

### Task 28: Refactor ChatPanel

**Files:**
- Create: `web/src/components/chat/ChatMessage.tsx`
- Create: `web/src/components/chat/ChatInput.tsx`
- Create: `web/src/components/chat/SuggestedPrompts.tsx`
- Create: `web/src/components/chat/TypingIndicator.tsx`
- Create: `web/src/hooks/useChatSession.ts`
- Modify: `web/src/components/chat/ChatPanel.tsx` (rewrite, slimmed down)
- Delete: `web/src/components/chat/ChatPanel.module.css`
- Delete: `web/src/components/chat/ChatIcons.tsx`

- [ ] **Step 1: Read existing ChatPanel.tsx (498 lines) and ChatIcons.tsx**

Understand all functionality: message rendering, input handling, RAG integration, streaming, history, suggestions, resize.

- [ ] **Step 2: Extract useChatSession hook**

Manages chat state and API calls:
- Message history
- Send message (calls gemini streaming + RAG)
- Loading state
- Suggested prompts generation
- Chat history persistence (Supabase)
- Returns: `{ messages, sendMessage, isLoading, suggestions, clearHistory }`

- [ ] **Step 3: Create ChatMessage**

Individual message bubble:
- AI messages: left-aligned, surface-1 background
- User messages: right-aligned, accent background
- Markdown rendering (react-markdown + remark-gfm)
- Clickable page references (`📄 Sayfa X` → scroll PDF to that page)
- Framer Motion entrance animation

- [ ] **Step 4: Create ChatInput**

Message input area:
- Text input with send button
- Attachment support (existing)
- Enter to send, Shift+Enter for newline

- [ ] **Step 5: Create SuggestedPrompts**

Contextual prompt suggestions:
- Pill-shaped buttons: "Bu bölümü özetle", "Quiz oluştur", "Anahtar terimler"
- Change based on current page context

- [ ] **Step 6: Create TypingIndicator**

Animated dots for "AI is thinking":
- Three dots with staggered pulse animation

- [ ] **Step 7: Rewrite ChatPanel**

Composition component:
- Uses `useChatSession` hook
- Renders: header, `ChatMessage` list, `SuggestedPrompts`, `ChatInput`
- Resizable width (shadcn `Resizable`)
- Desktop: side panel, `⌘+J` toggle
- Tablet: Vaul sheet (right slide-in)
- Mobile: full-screen bottom sheet

Target: ChatPanel ≤200 lines (logic in hook, sub-components extracted).

- [ ] **Step 8: Extract CorioLogo before deleting ChatIcons**

**IMPORTANT:** Before deleting `ChatIcons.tsx`, extract the `CorioLogo` SVG component.

Create `web/src/components/shared/CorioLogo.tsx`:
Read the existing `ChatIcons.tsx`, find the `CorioLogo` component, extract it into a standalone file:
```tsx
// Corio Docs brand logo
interface CorioLogoProps {
  className?: string;
  size?: number;
}

export function CorioLogo({ className, size = 24 }: CorioLogoProps) {
  return (
    <svg width={size} height={size} className={className}>
      {/* ... SVG paths from existing ChatIcons.tsx CorioLogo ... */}
    </svg>
  );
}
```

Update any existing imports of `CorioLogo` from `ChatIcons` to use the new shared component.

- [ ] **Step 9: Delete old files**

```bash
rm web/src/components/chat/ChatPanel.module.css
rm web/src/components/chat/ChatIcons.tsx
```

- [ ] **Step 10: Verify chat works end-to-end**

```bash
npm run dev
```
Open PDF → open chat → send message → verify streaming response → verify page references clickable.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "refactor: split ChatPanel into focused components with useChatSession hook"
```

---

## Chunk 5: Phase 5a + 5b (Notebook, Settings, Polish)

### Task 29: Create Notebook page

**Files:**
- Create: `web/src/components/notebook/AnnotationCard.tsx`
- Create: `web/src/components/notebook/NotebookFilters.tsx`
- Modify: `web/src/app/(app)/notes/page.tsx` (rewrite with Tailwind)
- Delete: `web/src/app/(app)/notes/notes.module.css`

- [ ] **Step 1: Read existing notes page**

Read `web/src/app/(app)/notes/page.tsx` (moved to `(app)` route group in Task 10) to understand current annotation display logic.

- [ ] **Step 2: Create AnnotationCard**

Note/annotation display card:
- Left border color matches highlight color
- Selected text (quoted)
- Source: PDF name + page number (clickable → navigates to reader)
- User note (if any)
- Date
- Uses shadcn `Card`

- [ ] **Step 3: Create NotebookFilters**

Filter bar for annotations:
- Color filter (4 highlight colors)
- Source PDF filter (dropdown)
- Date range
- Search text
- Export button (Markdown)

- [ ] **Step 4: Rewrite notes page**

- Top bar: "Defterim" title + filter controls
- Main area: list of `AnnotationCard` components
- Empty state when no annotations
- Responsive layout

- [ ] **Step 5: Delete old CSS Module**

```bash
rm web/src/app/(app)/notes/notes.module.css
```

- [ ] **Step 6: Verify**

```bash
npm run dev
```
Visit `/notes` — verify annotations display, filters work, clicking navigates to reader.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: redesign notebook page with annotation cards and filters"
```

---

### Task 30: Create Settings page

**Files:**
- Create: `web/src/app/(app)/settings/page.tsx`

- [ ] **Step 1: Create settings page**

iOS Settings style with grouped sections using shadcn `Card` + `Separator`:

1. **Hesap** — avatar, name, email, sign out button
2. **Görünüm** — ThemeSwitcher (expanded), font size slider, font family selector
3. **Okuma** — default zoom, page transition mode, translation target language
4. **AI Asistan** — model preference display, context length info
5. **Depolama** — cache clear button, usage stats
6. **Hakkında** — version, feedback link, terms of service link

All settings that have existing state: connect to appropriate hooks/stores.
Settings without backend: local state with `localStorage` for now.

- [ ] **Step 2: Verify**

```bash
npm run dev
```
Visit `/settings` — verify all sections render, theme switching works.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add settings page with grouped sections"
```

---

### Task 31: Create Command Palette

**Files:**
- Create: `web/src/components/layout/CommandPalette.tsx`
- Modify: `web/src/app/(app)/layout.tsx` (add CommandPalette)

- [ ] **Step 1: Create CommandPalette**

Using cmdk library:
- `⌘+K` to open (registered via useKeyboardShortcuts)
- Rendered in shadcn `Dialog`
- Search sections:
  - Recent documents (from library)
  - Navigation (Library, Notes, Settings)
  - Actions (theme switch, upload document)
- Fuzzy search on document titles
- Keyboard navigation (↑↓ to select, Enter to execute, Esc to close)

- [ ] **Step 2: Add to app layout**

Add `<CommandPalette />` to `web/src/app/(app)/layout.tsx`.

- [ ] **Step 3: Verify**

```bash
npm run dev
```
Press `⌘+K` on any authenticated page → verify palette opens, search works, navigation works.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add command palette with ⌘+K shortcut"
```

---

### Task 32: Migrate AnnotationContext to Zustand

**Files:**
- Create: `web/src/stores/useReaderStore.ts`
- Modify: all components that import from `AnnotationContext`
- Delete: `web/src/contexts/AnnotationContext.tsx`

- [ ] **Step 1: Create useReaderStore**

Zustand store replacing AnnotationContext + reader state:
```ts
interface ReaderStore {
  // Annotations (from AnnotationContext)
  annotations: Annotation[];
  selectedTool: 'highlight' | 'underline' | 'strikethrough' | null;
  selectedColor: string;
  isAnnotationsLoading: boolean;
  loadFileAnnotations: (fileId: string) => Promise<void>;
  addAnnotation: (annotation: Annotation) => Promise<void>;
  removeAnnotation: (id: string) => Promise<void>;
  updateAnnotationNote: (id: string, note: string) => Promise<void>;
  setSelectedTool: (tool: string | null) => void;
  setSelectedColor: (color: string) => void;

  // Reader state
  isChatOpen: boolean;
  isThumbnailOpen: boolean;
  isTranslationMode: boolean;
  toggleChat: () => void;
  toggleThumbnail: () => void;
  toggleTranslationMode: () => void;
}
```

- [ ] **Step 2: Update all consumer components**

Replace `useAnnotations()` context calls with `useReaderStore()`:
- `AnnotationToolbar.tsx` (uses context for selectedColor, selectedTool)
- `FloatingActionBar.tsx` (uses context for addAnnotation)
- `reader/[id]/page.tsx` (uses context for loadFileAnnotations, annotations list)

Note: `AnnotationLayer.tsx` receives annotations via props, not context — no changes needed there.

- [ ] **Step 3: Remove AnnotationProvider wrapper from reader page**

The reader page no longer needs `<AnnotationProvider>` wrapper.

- [ ] **Step 4: Delete AnnotationContext**

```bash
rm web/src/contexts/AnnotationContext.tsx
```

- [ ] **Step 5: Verify annotations still work**

```bash
npm run dev
```
Open PDF → highlight text → verify highlight saved → reload → verify persisted.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: migrate AnnotationContext to Zustand useReaderStore"
```

---

### Task 33: Split rag.ts

**Files:**
- Create: `web/src/lib/rag-search.ts`
- Create: `web/src/lib/rag-chunks.ts`
- Create: `web/src/lib/rag-embeddings.ts`
- Modify: all files that import from `rag.ts`
- Delete: `web/src/lib/rag.ts`

- [ ] **Step 1: Read rag.ts (654 lines) and identify boundaries**

Split into:
- `rag-search.ts` — `searchRelevantChunks`, `searchRelevantChunksVector`, `searchRelevantChunksHybrid`, BM25 scoring, RRF fusion
- `rag-chunks.ts` — `generateChunks`, `storeChunks`, `loadChunksByPage`, chunking logic
- `rag-embeddings.ts` — embedding generation via Gemini API, language detection, stop word removal

- [ ] **Step 2: Create the three files**

Extract functions maintaining all existing behavior. Update internal imports between the split files.

- [ ] **Step 3: Update all import paths**

Find all files importing from `@/lib/rag` and update to specific new paths.

- [ ] **Step 4: Delete old rag.ts**

```bash
rm web/src/lib/rag.ts
```

- [ ] **Step 5: Verify**

```bash
npx tsc --noEmit && npm run build
```

```bash
npm run dev
```
Open PDF → send chat message → verify RAG search still returns relevant context.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split rag.ts into rag-search, rag-chunks, rag-embeddings"
```

---

### Task 34: Create remaining Zustand stores

**Files:**
- Create: `web/src/stores/useThemeStore.ts`
- Create: `web/src/stores/useLibraryStore.ts`
- Create: `web/src/stores/useChatStore.ts`

- [ ] **Step 1: Create useThemeStore**

```ts
interface ThemeStore {
  fontSize: number;       // 14-24, default 16
  fontFamily: 'sans' | 'serif' | 'mono';
  setFontSize: (size: number) => void;
  setFontFamily: (family: string) => void;
}
```
Persists to localStorage.

- [ ] **Step 2: Create useLibraryStore**

```ts
interface LibraryStore {
  viewMode: 'grid' | 'list';
  sortBy: 'name' | 'date' | 'size' | 'lastRead';
  searchQuery: string;
  setViewMode: (mode: string) => void;
  setSortBy: (sort: string) => void;
  setSearchQuery: (query: string) => void;
}
```
Persists viewMode and sortBy to localStorage.

- [ ] **Step 3: Create useChatStore**

```ts
interface ChatStore {
  isOpen: boolean;       // Chat panel visibility
  activeFileId: string | null;
  toggleOpen: () => void;
  setActiveFileId: (id: string | null) => void;
}
```

Note: Message history and send logic stay in `useChatSession` hook (per-session, not global). This store only holds global UI state.

**Note on useReaderState:** The spec listed `useReaderState.ts` as a hook extracted from the reader page. This is intentionally superseded by `useReaderStore` (Task 32), which combines reader UI state with annotation state in a single Zustand store. No separate `useReaderState.ts` hook is needed.

- [ ] **Step 4: Update components to use stores**

Connect settings page, library page, etc. to respective stores.

- [ ] **Step 5: Verify**

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Zustand stores for theme, library, and chat"
```

---

### Task 35: Clean up old globals.css

**Files:**
- Modify: `web/src/app/globals.css`

- [ ] **Step 1: Audit globals.css**

Review remaining contents. At this point, all pages and components should use Tailwind. The only things that should remain:
- `@import "tailwindcss";`
- `@import "react-pdf/dist/Page/AnnotationLayer.css";`
- `@import "react-pdf/dist/Page/TextLayer.css";`
- Corio design tokens (CSS variables for themes)
- Any Tailwind `@layer` overrides needed for shadcn

- [ ] **Step 2: Remove old CSS utilities, component styles, and variables**

Delete the old `:root` variables (indigo palette, gray palette), button styles, input styles, card styles, layout helpers, typography scale, animations — all replaced by Tailwind utilities and shadcn components.

- [ ] **Step 3: Verify nothing is broken**

```bash
npm run dev
```
Check every page: landing, login, library, reader, notes, settings. Verify nothing has visual regressions.

```bash
npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove old custom CSS replaced by Tailwind + shadcn"
```

---

### Task 36: Final responsive testing and polish

**Files:**
- Various component adjustments

- [ ] **Step 1: Test all breakpoints**

Test every page at these widths:
- 375px (iPhone SE)
- 428px (iPhone 14 Pro Max)
- 768px (iPad portrait)
- 1024px (iPad landscape)
- 1280px (laptop)
- 1536px (desktop)

Verify:
- `< lg`: Bottom nav visible, sidebar hidden, chat = bottom sheet
- `≥ lg`: Sidebar visible, chat = side panel
- `< md`: Translation popup = bottom sheet
- `≥ md`: Translation popup = floating popover

- [ ] **Step 2: Lazy-load heavy components**

Add dynamic imports with `next/dynamic` for:
- `PDFViewer` (heavy, pdfjs-dist)
- `ChatPanel` (react-markdown, remark-gfm)
- `ThumbnailSidebar` (renders page images)

```tsx
const PDFViewer = dynamic(() => import("@/components/reader/PDFViewer").then(m => ({ default: m.PDFViewer })), {
  loading: () => <PDFViewerSkeleton />,
  ssr: false,
});
```

Verify bundle sizes:
```bash
npm run build
```
Check `.next/analyze` output or build log for page sizes.

- [ ] **Step 3: Review gemini.ts (365 lines)**

Read `web/src/lib/gemini.ts`. At 365 lines it is under the 400-line hard limit but worth reviewing:
- If responsibilities are clear and cohesive → leave as-is
- If functions cluster into distinct domains (translation, chat, summary, image) → split
- Document the decision in a code comment at the top of the file

- [ ] **Step 4: Add Framer Motion page transitions**

Add `motion` wrappers to page components for smooth navigation transitions:
```tsx
const pageTransition = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -8 },
  transition: { duration: 0.25, ease: [0.22, 1, 0.36, 1] },
};
```

- [ ] **Step 5: Add loading skeletons**

Add skeleton loading states to:
- Library page (grid of skeleton cards)
- Reader page (skeleton PDF area)
- Chat panel (skeleton messages)

- [ ] **Step 6: Verify full build**

```bash
npx tsc --noEmit && npm run build && npm run lint
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add responsive polish, lazy loading, page transitions, and skeletons"
```

---

### Task 37: Final verification and cleanup

- [ ] **Step 1: Full build verification**

```bash
cd web
npx tsc --noEmit && npm run build && npm run lint
```
All must pass with zero errors.

- [ ] **Step 2: Check for orphaned files**

Verify no old CSS Modules, backup files, or unused components remain:
```bash
find src -name "*.module.css" -o -name "*.bak*" -o -name "*.broken"
```
Expected: No results.

- [ ] **Step 3: Verify all pages work**

Manual check:
- `/` — Landing page
- `/login` — Login page
- `/library` — Document library
- `/reader/[id]` — PDF reader with chat, annotations, translation
- `/notes` — Notebook
- `/settings` — Settings
- `⌘+K` — Command palette

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup and verification of UI redesign"
```
