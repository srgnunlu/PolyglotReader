import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ToastProvider } from "@/contexts/ToastContext";
import { ToastContainer } from "@/components/ui/Toast";

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  viewportFit: "cover",
  themeColor: "#0f172a",
};

export const metadata: Metadata = {
  title: "Corio Docs",
  description: "Akıllı Doküman Asistanı - AI-powered document analysis",
  keywords: ["PDF reader", "document analysis", "AI", "notes", "annotations", "Corio"],
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Corio Docs",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="tr" suppressHydrationWarning>
      <body>
        <ToastProvider>
          {children}
          <ToastContainer />
        </ToastProvider>
      </body>
    </html>
  );
}
