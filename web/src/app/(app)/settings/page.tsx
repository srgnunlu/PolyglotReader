// Settings page — user account, appearance, reading, AI, storage, and about sections
'use client';

import { useState, useEffect } from 'react';
import { useTheme } from 'next-themes';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useAuth } from '@/hooks/useAuth';
import { pdfCache } from '@/lib/pdfCache';
import { thumbnailCache } from '@/lib/thumbnailCache';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import {
  User,
  Palette,
  BookOpen,
  Bot,
  HardDrive,
  Info,
  LogOut,
  Sun,
  Moon,
  BookOpenText,
  ChevronRight,
} from 'lucide-react';

export default function SettingsPage() {
  return (
    <ProtectedRoute>
      <SettingsContent />
    </ProtectedRoute>
  );
}

// Theme options for the appearance section
const themeOptions = [
  { id: 'light', label: 'Açık', icon: Sun },
  { id: 'dark', label: 'Koyu', icon: Moon },
  { id: 'sepia', label: 'Sepya', icon: BookOpenText },
] as const;

function SettingsContent() {
  const { user, signOut } = useAuth();
  const { theme, setTheme } = useTheme();

  // Avoid hydration mismatch — render theme buttons only after mount
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const currentTheme = mounted ? theme : 'light';

  // Extract initials from user name for the avatar circle
  const initials = user?.name
    ? user.name
        .split(' ')
        .map((word) => word[0])
        .join('')
        .toUpperCase()
        .slice(0, 2)
    : '?';

  const [isClearingCache, setIsClearingCache] = useState(false);

  const handleClearCache = async () => {
    setIsClearingCache(true);
    try {
      await Promise.all([pdfCache.clearCache(), thumbnailCache.clearCache()]);
      toast.success('Önbellek başarıyla temizlendi');
    } catch {
      toast.error('Önbellek temizlenirken bir sorun oluştu');
    } finally {
      setIsClearingCache(false);
    }
  };

  return (
    <div className="min-h-screen bg-corio-bg">
      {/* Page header */}
      <div className="sticky top-0 z-10 px-4 sm:px-6 py-4 bg-corio-bg/90 backdrop-blur-xl border-b border-corio-border-subtle">
        <h1 className="text-xl font-semibold text-corio-fg">Ayarlar</h1>
      </div>

      {/* Settings sections */}
      <div className="px-4 sm:px-6 py-6 max-w-2xl mx-auto space-y-5">
        {/* Section 1: Hesap (Account) */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <User className="size-4 text-corio-accent" />
              Hesap
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-4">
              {/* Avatar circle with initials */}
              <div className="flex items-center justify-center size-12 rounded-full bg-corio-accent text-white font-semibold text-lg shrink-0">
                {initials}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-corio-fg truncate">
                  {user?.name || 'Kullanıcı'}
                </p>
                <p className="text-xs text-corio-fg/50 truncate">
                  {user?.email || '—'}
                </p>
              </div>
            </div>
            <Separator className="bg-corio-border-subtle" />
            <Button
              variant="destructive"
              size="sm"
              onClick={signOut}
              className="w-full gap-2"
            >
              <LogOut className="size-4" />
              Çıkış Yap
            </Button>
          </CardContent>
        </Card>

        {/* Section 2: Görünüm (Appearance) */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <Palette className="size-4 text-corio-accent" />
              Görünüm
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <Label className="text-corio-fg/70">Tema</Label>
            <div className="grid grid-cols-3 gap-2">
              {themeOptions.map(({ id, label, icon: Icon }) => {
                const isActive = currentTheme === id;
                return (
                  <button
                    key={id}
                    onClick={() => setTheme(id)}
                    className={`flex flex-col items-center gap-1.5 rounded-xl px-3 py-3 text-xs font-medium transition-all ${
                      isActive
                        ? 'bg-corio-accent-subtle text-corio-accent ring-1 ring-corio-accent/30'
                        : 'bg-corio-surface-2 text-corio-fg/60 hover:bg-corio-surface-3'
                    }`}
                  >
                    <Icon className="size-5" />
                    {label}
                  </button>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* Section 3: Okuma (Reading) */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <BookOpen className="size-4 text-corio-accent" />
              Okuma
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-corio-fg/50">
              Okuma ayarları yakında eklenecek
            </p>
          </CardContent>
        </Card>

        {/* Section 4: AI Asistan */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <Bot className="size-4 text-corio-accent" />
              AI Asistan
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-corio-fg/70">Model</Label>
              <span className="text-sm text-corio-fg">Gemini 3 Flash</span>
            </div>
            <Separator className="bg-corio-border-subtle" />
            <div className="flex items-center justify-between">
              <Label className="text-corio-fg/70">Yanıt Dili</Label>
              <span className="text-sm text-corio-fg">Türkçe</span>
            </div>
            <Separator className="bg-corio-border-subtle" />
            <div className="flex items-center justify-between">
              <Label className="text-corio-fg/70">RAG</Label>
              <span className="text-sm text-corio-fg">Aktif</span>
            </div>
          </CardContent>
        </Card>

        {/* Section 5: Depolama (Storage) */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <HardDrive className="size-4 text-corio-accent" />
              Depolama
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Button
              variant="outline"
              size="sm"
              onClick={handleClearCache}
              disabled={isClearingCache}
              className="w-full gap-2 border-corio-border text-corio-fg hover:bg-corio-surface-2"
            >
              {isClearingCache ? 'Temizleniyor...' : 'Önbelleği Temizle'}
            </Button>
            <p className="mt-2 text-xs text-corio-fg/50">
              Cihazda saklanan PDF ve küçük resim önbelleğini siler. Dosyalarınız buluttan tekrar indirilir.
            </p>
          </CardContent>
        </Card>

        {/* Section 6: Hakkında (About) */}
        <Card className="bg-corio-surface-1 border-corio-border">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-corio-fg">
              <Info className="size-4 text-corio-accent" />
              Hakkında
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-corio-fg/70">Sürüm</Label>
              <span className="text-sm text-corio-fg">1.0.0-beta</span>
            </div>
            <Separator className="bg-corio-border-subtle" />
            <button className="flex w-full items-center justify-between py-1 group">
              <span className="text-sm text-corio-fg/70 group-hover:text-corio-fg transition-colors">
                Kullanım Koşulları
              </span>
              <ChevronRight className="size-4 text-corio-fg/30 group-hover:text-corio-fg/50 transition-colors" />
            </button>
            <Separator className="bg-corio-border-subtle" />
            <button className="flex w-full items-center justify-between py-1 group">
              <span className="text-sm text-corio-fg/70 group-hover:text-corio-fg transition-colors">
                Gizlilik Politikası
              </span>
              <ChevronRight className="size-4 text-corio-fg/30 group-hover:text-corio-fg/50 transition-colors" />
            </button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
