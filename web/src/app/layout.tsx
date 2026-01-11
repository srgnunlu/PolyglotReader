import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PolyglotReader",
  description: "AI-powered PDF reader and analysis application",
  keywords: ["PDF reader", "translation", "AI", "notes", "annotations"],
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
