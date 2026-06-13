// MobileNav - bottom tab bar for mobile screens (hidden on lg+)
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Library, MessagesSquare, Notebook, Settings } from "lucide-react";
import { motion } from "framer-motion";

const tabs = [
  { href: "/library", label: "Kütüphane", icon: Library },
  { href: "/chat", label: "Sohbet", icon: MessagesSquare },
  { href: "/notes", label: "Defterim", icon: Notebook },
  { href: "/settings", label: "Ayarlar", icon: Settings },
];

export function MobileNav() {
  const pathname = usePathname();

  return (
    <nav className="lg:hidden fixed bottom-0 inset-x-0 z-50 bg-corio-bg/95 backdrop-blur-md border-t border-corio-border">
      <div className="flex items-stretch h-16">
        {tabs.map(({ href, label, icon: Icon }) => {
          const isActive = pathname === href || pathname.startsWith(href + "/");
          return (
            <Link
              key={href}
              href={href}
              className="relative flex-1 flex flex-col items-center justify-center gap-0.5"
            >
              {isActive && (
                <motion.span
                  layoutId="mobile-nav-indicator"
                  className="absolute inset-0 bg-corio-accent-subtle"
                  style={{ borderRadius: 0 }}
                  transition={{ type: "spring", stiffness: 400, damping: 35 }}
                />
              )}
              <Icon
                className={`relative size-5 z-10 ${
                  isActive ? "text-corio-accent" : "text-corio-fg/60"
                }`}
              />
              <span
                className={`relative z-10 text-[10px] font-medium leading-none ${
                  isActive ? "text-corio-accent" : "text-corio-fg/60"
                }`}
              >
                {label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
