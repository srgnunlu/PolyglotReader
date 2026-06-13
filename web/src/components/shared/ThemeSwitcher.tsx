// ThemeSwitcher — dropdown to switch between light, dark, and sepia themes
"use client";
import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";
import { Sun, Moon, BookOpen } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const themes = [
  { id: "light", label: "Açık", icon: Sun },
  { id: "dark", label: "Koyu", icon: Moon },
  { id: "sepia", label: "Sepia", icon: BookOpen },
] as const;

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme();
  // Avoid hydration mismatch — false on the server, true once the client
  // mounts. useSyncExternalStore gives us this without a setState-in-effect.
  const mounted = useSyncExternalStore(
    () => () => {},
    () => true,
    () => false,
  );

  const currentTheme = mounted ? theme : "light";
  const current = themes.find((t) => t.id === currentTheme) ?? themes[0];
  const CurrentIcon = current.icon;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        aria-label="Tema seç"
        className={cn(buttonVariants({ variant: "ghost", size: "icon" }), "size-9")}
      >
        <CurrentIcon className="h-4 w-4" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {themes.map(({ id, label, icon: Icon }) => (
          <DropdownMenuItem
            key={id}
            onClick={() => setTheme(id)}
            className={cn(
              "flex items-center gap-2 cursor-pointer",
              currentTheme === id && "bg-corio-accent-subtle font-medium"
            )}
          >
            <Icon className="h-4 w-4" />
            {label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
