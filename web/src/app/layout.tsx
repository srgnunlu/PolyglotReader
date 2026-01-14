import type { Metadata } from "next";
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
      <body>
        {children}
      </body>
    </html>
  );
}
