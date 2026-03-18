// Hero section — warm luxury editorial, CSS animations (SSR-safe, no Framer Motion dependency)
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
    <section className="relative flex min-h-[92vh] items-center justify-center overflow-hidden">
      {/* Layered gradient background */}
      <div className="absolute inset-0 bg-gradient-to-b from-[#FDF9F3] via-[#FAF0E8] to-[#F5E6D8]" />

      {/* Decorative warm orbs */}
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <div className="absolute right-[15%] top-[10%] h-[500px] w-[500px] rounded-full bg-[#D4713C]/[0.07] blur-[120px]" />
        <div className="absolute bottom-[5%] left-[10%] h-[400px] w-[400px] rounded-full bg-[#D4713C]/[0.05] blur-[100px]" />
        <div className="absolute left-1/2 top-[40%] h-[300px] w-[300px] -translate-x-1/2 rounded-full bg-[#E8A87C]/[0.08] blur-[80px]" />
      </div>

      <div className="relative z-10 mx-auto max-w-4xl px-6 py-32 text-center">
        {/* Badge — CSS animation */}
        <div className="mb-8 inline-flex animate-[fadeUp_0.6s_ease-out_0.1s_both] items-center gap-2.5 rounded-full border border-[#D4713C]/20 bg-white/60 px-5 py-2 shadow-[0_1px_8px_rgba(212,113,60,0.08)] backdrop-blur-sm">
          <Sparkles className="size-4 text-[#D4713C]" />
          <span className="text-[13px] font-semibold tracking-wide text-[#D4713C]">AI Destekli PDF Okuyucu</span>
        </div>

        {/* Main heading */}
        <h1 className="mb-6 animate-[fadeUp_0.7s_ease-out_0.2s_both] text-[clamp(2.5rem,6vw,4.5rem)] font-bold leading-[1.08] tracking-[-0.03em] text-[#2A2520]">
          Belgeleriniz için
          <br />
          <span className="bg-gradient-to-r from-[#D4713C] to-[#E8946A] bg-clip-text text-transparent">
            AI destekli
          </span>{' '}
          okuma asistanı
        </h1>

        {/* Subheading */}
        <p className="mx-auto mb-12 max-w-[540px] animate-[fadeUp_0.6s_ease-out_0.35s_both] text-[17px] leading-[1.7] text-[#2A2520]/55">
          PDF belgelerinizi yapay zeka ile okuyun, anında çevirin ve notlar alın.
          Google Gemini teknolojisi ile belgelerinize sorular sorun.
        </p>

        {/* CTA buttons */}
        <div className="flex animate-[fadeUp_0.6s_ease-out_0.5s_both] flex-col items-center gap-3.5 sm:flex-row sm:justify-center">
          <button
            onClick={onGoogleSignIn}
            disabled={isDisabled}
            className="group inline-flex h-[52px] w-full max-w-[260px] items-center justify-center gap-3 rounded-2xl bg-white px-7 text-[15px] font-semibold text-[#2A2520] shadow-[0_2px_16px_rgba(42,37,32,0.08),0_0_0_1px_rgba(42,37,32,0.06)] transition-all duration-200 hover:-translate-y-0.5 hover:shadow-[0_4px_24px_rgba(42,37,32,0.12),0_0_0_1px_rgba(42,37,32,0.08)] active:translate-y-0 disabled:pointer-events-none disabled:opacity-50 sm:w-auto"
          >
            {isGoogleLoading ? (
              <span className="size-5 animate-spin rounded-full border-2 border-[#2A2520]/20 border-t-[#2A2520]/70" />
            ) : (
              <GoogleLogo className="size-5 shrink-0" />
            )}
            Google ile Başlayın
          </button>

          <button
            onClick={onAppleSignIn}
            disabled={isDisabled}
            className="group inline-flex h-[52px] w-full max-w-[260px] items-center justify-center gap-3 rounded-2xl bg-[#2A2520] px-7 text-[15px] font-semibold text-[#FDFAF6] shadow-[0_2px_16px_rgba(42,37,32,0.2)] transition-all duration-200 hover:-translate-y-0.5 hover:bg-[#3D3530] hover:shadow-[0_4px_24px_rgba(42,37,32,0.25)] active:translate-y-0 disabled:pointer-events-none disabled:opacity-50 sm:w-auto"
          >
            {isAppleLoading ? (
              <span className="size-5 animate-spin rounded-full border-2 border-white/30 border-t-white/80" />
            ) : (
              <AppleLogo className="size-5 shrink-0" />
            )}
            Apple ile Başlayın
          </button>
        </div>

        {/* Stats */}
        <div className="mt-16 flex animate-[fadeUp_0.8s_ease-out_0.7s_both] flex-wrap items-center justify-center gap-x-12 gap-y-4">
          {[
            { value: '10K+', label: 'Aktif Kullanıcı' },
            { value: '50K+', label: 'Analiz Edilen Belge' },
            { value: '4.8★', label: 'App Store' },
          ].map((stat, i) => (
            <div key={stat.label} className="flex items-center gap-3">
              {i > 0 && <div className="hidden h-4 w-px bg-[#2A2520]/10 sm:block" />}
              <div className="text-center sm:text-left">
                <span className="text-lg font-bold tracking-tight text-[#2A2520]">{stat.value}</span>
                <span className="ml-1.5 text-[13px] text-[#2A2520]/40">{stat.label}</span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Bottom fade */}
      <div className="absolute bottom-0 left-0 right-0 h-24 bg-gradient-to-t from-[#FDFAF6] to-transparent" />
    </section>
  );
}
