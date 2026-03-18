// Corio Docs landing page — entry point, orchestrates landing sections
'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/hooks/useAuth';
import { HeroSection } from '@/components/landing/HeroSection';
import { FeaturesGrid } from '@/components/landing/FeaturesGrid';
import { Footer } from '@/components/landing/Footer';
import { BookOpen } from 'lucide-react';

function GoogleLogoSmall() {
  return (
    <svg className="size-4 shrink-0" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  );
}

export default function LandingPage() {
  const router = useRouter();
  const { signInWithGoogle, isLoading, isAuthenticated } = useAuth();
  const [isScrolled, setIsScrolled] = useState(false);
  const [authLoading, setAuthLoading] = useState<'google' | 'apple' | null>(null);

  // Redirect authenticated users directly to library
  useEffect(() => {
    if (isAuthenticated) {
      router.push('/library');
    }
  }, [isAuthenticated, router]);

  // Sticky header shadow on scroll
  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 50);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const handleGoogleSignIn = async () => {
    setAuthLoading('google');
    await signInWithGoogle();
    setAuthLoading(null);
  };

  const handleAppleSignIn = () => {
    setAuthLoading('apple');
    // Apple Sign-In will be implemented — redirect to Google for now
    alert('Apple ile giriş yakında aktif olacak. Lütfen Google ile giriş yapın.');
    setAuthLoading(null);
  };

  const scrollTo = (id: string) => (e: React.MouseEvent) => {
    e.preventDefault();
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <div className="min-h-screen bg-[#FDFAF6] text-[#2A2520]">
      {/* Sticky navigation */}
      <header
        className={`fixed inset-x-0 top-0 z-50 transition-all duration-300 ${
          isScrolled
            ? 'bg-[#FDFAF6]/85 shadow-[0_1px_0_rgba(42,37,32,0.06)] backdrop-blur-xl'
            : 'bg-transparent'
        }`}
      >
        <nav className="mx-auto flex h-[60px] max-w-5xl items-center justify-between px-6">
          <div className="flex items-center gap-2.5">
            <div className="flex size-8 items-center justify-center rounded-[10px] bg-gradient-to-br from-[#D4713C] to-[#C0632F] shadow-sm">
              <BookOpen className="size-4 text-white" strokeWidth={2} />
            </div>
            <span className="text-[15px] font-bold tracking-[-0.01em]">Corio Docs</span>
          </div>

          <div className="hidden items-center gap-8 sm:flex">
            <a href="#features" onClick={scrollTo('features')} className="text-[13px] font-medium text-[#2A2520]/45 transition-colors hover:text-[#2A2520]">
              Özellikler
            </a>
            <a href="#how-it-works" onClick={scrollTo('how-it-works')} className="text-[13px] font-medium text-[#2A2520]/45 transition-colors hover:text-[#2A2520]">
              Nasıl Çalışır
            </a>
            <a href="#footer" onClick={scrollTo('footer')} className="text-[13px] font-medium text-[#2A2520]/45 transition-colors hover:text-[#2A2520]">
              İletişim
            </a>
          </div>

          <button
            onClick={handleGoogleSignIn}
            disabled={isLoading}
            className="inline-flex h-9 items-center gap-2 rounded-xl bg-white px-4 text-[13px] font-semibold text-[#2A2520] shadow-[0_1px_4px_rgba(42,37,32,0.06),0_0_0_1px_rgba(42,37,32,0.06)] transition-all duration-200 hover:shadow-[0_2px_8px_rgba(42,37,32,0.1)] disabled:opacity-50"
          >
            {authLoading === 'google' ? (
              <span className="size-3.5 animate-spin rounded-full border-2 border-[#2A2520]/15 border-t-[#2A2520]/60" />
            ) : (
              <GoogleLogoSmall />
            )}
            <span className="hidden sm:inline">Giriş Yap</span>
          </button>
        </nav>
      </header>

      <main>
        <HeroSection
          onGoogleSignIn={handleGoogleSignIn}
          onAppleSignIn={handleAppleSignIn}
          isGoogleLoading={authLoading === 'google'}
          isAppleLoading={authLoading === 'apple'}
          isDisabled={isLoading}
        />

        <FeaturesGrid />

        {/* CTA section */}
        <section className="relative overflow-hidden bg-gradient-to-b from-[#FDFAF6] to-[#FAF0E8] px-6 py-28">
          <div className="pointer-events-none absolute inset-0" aria-hidden="true">
            <div className="absolute bottom-0 left-1/2 h-[300px] w-[600px] -translate-x-1/2 rounded-full bg-[#D4713C]/[0.06] blur-[100px]" />
          </div>
          <div className="relative mx-auto max-w-lg text-center">
            <h2 className="mb-4 text-[clamp(1.5rem,3.5vw,2.25rem)] font-bold leading-[1.15] tracking-[-0.025em] text-[#2A2520]">
              Hemen ücretsiz başlayın
            </h2>
            <p className="mb-10 text-[15px] leading-[1.7] text-[#2A2520]/50">
              Belgelerinizi yapay zeka ile keşfetmeye bugün başlayın. Kredi kartı gerektirmez.
            </p>
            <button
              onClick={handleGoogleSignIn}
              disabled={isLoading}
              className="inline-flex h-[52px] items-center gap-3 rounded-2xl bg-white px-8 text-[15px] font-semibold text-[#2A2520] shadow-[0_2px_16px_rgba(42,37,32,0.08),0_0_0_1px_rgba(42,37,32,0.06)] transition-all duration-200 hover:shadow-[0_4px_24px_rgba(42,37,32,0.12)] hover:-translate-y-0.5 disabled:opacity-50"
            >
              {authLoading === 'google' ? (
                <span className="size-5 animate-spin rounded-full border-2 border-[#2A2520]/15 border-t-[#2A2520]/60" />
              ) : (
                <GoogleLogoSmall />
              )}
              Google ile Ücretsiz Başlayın
            </button>
            <p className="mt-5 text-[12px] text-[#2A2520]/30">
              Giriş yaparak{' '}
              <Link href="/legal/terms-of-service" className="underline decoration-[#2A2520]/20 underline-offset-2 transition-colors hover:text-[#D4713C]">
                Kullanım Şartlarını
              </Link>{' '}
              kabul ediyorsunuz
            </p>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
