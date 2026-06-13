// Hero section — static, no animation dependencies, always visible
'use client';

import { Sparkles } from 'lucide-react';

function GoogleLogo({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  );
}

function AppleLogo({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}

interface HeroSectionProps {
  onGoogleSignIn: () => void;
  onAppleSignIn: () => void;
  isGoogleLoading: boolean;
  isAppleLoading: boolean;
  isDisabled: boolean;
}

export function HeroSection({
  onGoogleSignIn,
  onAppleSignIn,
  isGoogleLoading,
  isAppleLoading,
  isDisabled,
}: HeroSectionProps) {
  return (
    <section
      className="relative overflow-hidden px-6 pb-20 pt-28 sm:pb-28 sm:pt-36"
      style={{ background: 'linear-gradient(to bottom, #FDF9F3, #FAF0E8, #F5E6D8)' }}
    >
      {/* Decorative warm orbs */}
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <div
          className="absolute right-[15%] top-[10%] h-[500px] w-[500px] rounded-full blur-[120px]"
          style={{ backgroundColor: 'rgba(212, 113, 60, 0.07)' }}
        />
        <div
          className="absolute bottom-[5%] left-[10%] h-[400px] w-[400px] rounded-full blur-[100px]"
          style={{ backgroundColor: 'rgba(212, 113, 60, 0.05)' }}
        />
      </div>

      <div className="relative z-10 mx-auto max-w-3xl text-center">
        {/* Badge */}
        <div
          className="mb-8 inline-flex items-center gap-2.5 rounded-full px-5 py-2 backdrop-blur-sm"
          style={{
            backgroundColor: 'rgba(255, 255, 255, 0.6)',
            border: '1px solid rgba(212, 113, 60, 0.2)',
            boxShadow: '0 1px 8px rgba(212, 113, 60, 0.08)',
          }}
        >
          <Sparkles className="size-4" style={{ color: '#D4713C' }} />
          <span className="text-sm font-semibold tracking-wide" style={{ color: '#D4713C' }}>
            AI Destekli PDF Okuyucu
          </span>
        </div>

        {/* Heading */}
        <h1
          className="mb-6 text-4xl font-bold leading-tight tracking-tight sm:text-5xl lg:text-6xl"
          style={{ color: '#2A2520' }}
        >
          Belgeleriniz için
          <br />
          <span
            style={{
              background: 'linear-gradient(to right, #D4713C, #E8946A)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
            }}
          >
            AI destekli
          </span>{' '}
          okuma asistanı
        </h1>

        {/* Subheading */}
        <p className="mx-auto mb-12 max-w-lg text-base leading-relaxed sm:text-lg" style={{ color: 'rgba(42, 37, 32, 0.55)' }}>
          PDF belgelerinizi yapay zeka ile okuyun, anında çevirin ve notlar alın.
          Google Gemini teknolojisi ile belgelerinize sorular sorun.
        </p>

        {/* CTA buttons */}
        <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
          <button
            onClick={onGoogleSignIn}
            disabled={isDisabled}
            className="inline-flex h-12 w-full items-center justify-center gap-3 rounded-2xl px-7 text-sm font-semibold transition-all duration-200 hover:-translate-y-0.5 disabled:pointer-events-none disabled:opacity-50 sm:h-13 sm:w-auto sm:text-base"
            style={{
              backgroundColor: '#ffffff',
              color: '#2A2520',
              boxShadow: '0 2px 16px rgba(42,37,32,0.08), 0 0 0 1px rgba(42,37,32,0.06)',
            }}
          >
            {isGoogleLoading ? (
              <span className="size-5 animate-spin rounded-full" style={{ border: '2px solid rgba(42,37,32,0.2)', borderTopColor: 'rgba(42,37,32,0.7)' }} />
            ) : (
              <GoogleLogo className="size-5 shrink-0" />
            )}
            Google ile Başlayın
          </button>

          <button
            onClick={onAppleSignIn}
            disabled={isDisabled}
            className="inline-flex h-12 w-full items-center justify-center gap-3 rounded-2xl px-7 text-sm font-semibold transition-all duration-200 hover:-translate-y-0.5 disabled:pointer-events-none disabled:opacity-50 sm:h-13 sm:w-auto sm:text-base"
            style={{
              backgroundColor: '#2A2520',
              color: '#FDFAF6',
              boxShadow: '0 2px 16px rgba(42,37,32,0.2)',
            }}
          >
            {isAppleLoading ? (
              <span className="size-5 animate-spin rounded-full" style={{ border: '2px solid rgba(255,255,255,0.3)', borderTopColor: 'rgba(255,255,255,0.8)' }} />
            ) : (
              <AppleLogo className="size-5 shrink-0" />
            )}
            Apple ile Başlayın
          </button>
        </div>

        {/* Capability highlights — honest feature claims, not fabricated metrics */}
        <div className="mt-14 flex flex-wrap items-center justify-center gap-x-8 gap-y-4">
          {[
            'RAG destekli sohbet',
            'Anında TR↔EN çeviri',
            'Akıllı notlar & işaretleme',
          ].map((label, i) => (
            <div key={label} className="flex items-center gap-3">
              {i > 0 && <div className="hidden h-4 w-px sm:block" style={{ backgroundColor: 'rgba(42, 37, 32, 0.1)' }} />}
              <div className="flex items-center gap-2">
                <span className="size-1.5 rounded-full" style={{ backgroundColor: '#D4713C' }} />
                <span className="text-sm font-medium" style={{ color: 'rgba(42, 37, 32, 0.6)' }}>{label}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
