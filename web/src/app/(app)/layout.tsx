// Layout for authenticated app routes — wraps pages with AppShell (sidebar + mobile nav)
import { AppShell } from "@/components/layout/AppShell";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>;
}
