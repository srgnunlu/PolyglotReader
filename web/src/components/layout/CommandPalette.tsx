// Command palette — ⌘+K to open, search documents, navigate, switch themes
"use client";

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useTheme } from "next-themes";
import { Library, Notebook, Settings, Sun, Moon, BookOpen, FileUp } from "lucide-react";
import {
  CommandDialog,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandShortcut,
} from "@/components/ui/command";
import { useDocuments } from "@/hooks/useDocuments";

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const { setTheme } = useTheme();
  const { documents } = useDocuments();

  // ⌘+K shortcut
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen((prev) => !prev);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const runCommand = useCallback(
    (command: () => void) => {
      setOpen(false);
      command();
    },
    []
  );

  return (
    <CommandDialog open={open} onOpenChange={setOpen} title="Komut Paleti" description="Arama yapın veya bir komut çalıştırın">
      <CommandInput placeholder="Belge ara veya komut çalıştır..." />
      <CommandList>
        <CommandEmpty>Sonuç bulunamadı.</CommandEmpty>

        {/* Recent documents */}
        {documents.length > 0 && (
          <CommandGroup heading="Son Belgeler">
            {documents.slice(0, 5).map((doc) => (
              <CommandItem
                key={doc.id}
                onSelect={() => runCommand(() => router.push(`/reader/${doc.id}`))}
              >
                <BookOpen className="h-4 w-4 text-corio-accent" />
                <span className="truncate">{doc.name}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        )}

        {/* Navigation */}
        <CommandGroup heading="Navigasyon">
          <CommandItem onSelect={() => runCommand(() => router.push("/library"))}>
            <Library className="h-4 w-4" />
            <span>Kütüphane</span>
            <CommandShortcut>⌘1</CommandShortcut>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => router.push("/notes"))}>
            <Notebook className="h-4 w-4" />
            <span>Defterim</span>
            <CommandShortcut>⌘2</CommandShortcut>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => router.push("/settings"))}>
            <Settings className="h-4 w-4" />
            <span>Ayarlar</span>
            <CommandShortcut>⌘3</CommandShortcut>
          </CommandItem>
        </CommandGroup>

        {/* Theme */}
        <CommandGroup heading="Tema">
          <CommandItem onSelect={() => runCommand(() => setTheme("light"))}>
            <Sun className="h-4 w-4" />
            <span>Açık Tema</span>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => setTheme("dark"))}>
            <Moon className="h-4 w-4" />
            <span>Koyu Tema</span>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => setTheme("sepia"))}>
            <BookOpen className="h-4 w-4" />
            <span>Sepya Tema</span>
          </CommandItem>
        </CommandGroup>

        {/* Actions */}
        <CommandGroup heading="İşlemler">
          <CommandItem onSelect={() => runCommand(() => router.push("/library"))}>
            <FileUp className="h-4 w-4" />
            <span>Belge Yükle</span>
          </CommandItem>
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}
