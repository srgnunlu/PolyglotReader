// AppShell - wraps authenticated pages with desktop sidebar and mobile bottom nav
"use client";

import { SidebarProvider } from "@/components/ui/sidebar";
import { AppSidebar } from "./AppSidebar";
import { MobileNav } from "./MobileNav";

export function AppShell({ children }: { children: React.ReactNode }) {
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
