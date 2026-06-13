// AppSidebar - desktop sidebar navigation with logo, nav items, and footer controls
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { BookOpen, Library, MessagesSquare, Notebook, Settings } from "lucide-react";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { ThemeSwitcher } from "@/components/shared/ThemeSwitcher";

const navItems = [
  { href: "/library", label: "Kütüphane", icon: Library },
  { href: "/chat", label: "Sohbet", icon: MessagesSquare },
  { href: "/notes", label: "Defterim", icon: Notebook },
  { href: "/settings", label: "Ayarlar", icon: Settings },
];

export function AppSidebar() {
  const pathname = usePathname();

  return (
    <Sidebar collapsible="icon" className="bg-corio-surface-1 border-corio-border">
      <SidebarHeader className="px-4 py-3">
        <div className="flex items-center gap-2 group-data-[collapsible=icon]:justify-center">
          <BookOpen className="size-5 text-corio-accent shrink-0" />
          <span className="font-semibold text-corio-fg text-sm group-data-[collapsible=icon]:hidden">
            Corio Docs
          </span>
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {navItems.map(({ href, label, icon: Icon }) => {
                const isActive = pathname === href || pathname.startsWith(href + "/");
                return (
                  <SidebarMenuItem key={href}>
                    <SidebarMenuButton
                      isActive={isActive}
                      render={
                        <Link
                          href={href}
                          className={
                            isActive
                              ? "bg-corio-accent-subtle text-corio-accent"
                              : "text-corio-fg/70 hover:bg-corio-surface-2"
                          }
                        />
                      }
                      tooltip={label}
                    >
                      <Icon />
                      <span>{label}</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="flex-row items-center justify-between px-3 py-2">
        <ThemeSwitcher />
        <SidebarTrigger />
      </SidebarFooter>
    </Sidebar>
  );
}
