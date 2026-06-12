// Layout for authenticated app routes — wraps pages with AppShell (sidebar + mobile nav)
import { AppShell } from "@/components/layout/AppShell";
import { CommandPalette } from "@/components/layout/CommandPalette";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <AppShell>
      {children}
      <CommandPalette />
    </AppShell>
  );
}
