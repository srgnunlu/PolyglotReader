import type { Metadata } from "next";
import "./globals.css";
import { Inter, Literata, JetBrains_Mono } from "next/font/google";
import { cn } from "@/lib/utils";
import { ThemeProvider } from "@/components/shared/ThemeProvider";
import { Toaster } from "@/components/shared/Toaster";

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
    <html
      lang="tr"
      suppressHydrationWarning
      className={cn("font-sans", inter.variable, literata.variable, jetbrainsMono.variable)}
    >
      <body className={`${inter.variable} ${literata.variable} ${jetbrainsMono.variable} font-sans bg-corio-bg text-corio-fg antialiased`}>
        <ThemeProvider>
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  );
}
