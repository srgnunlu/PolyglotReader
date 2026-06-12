// Toaster — app-wide toast notifications styled with Corio design tokens
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
