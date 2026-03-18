// Features grid + How It Works — CSS animations (SSR-safe)
'use client';

import { BookOpen, MessageSquare, Languages, Highlighter, Cloud, ShieldCheck, type LucideIcon } from 'lucide-react';

const features: { icon: LucideIcon; title: string; description: string }[] = [
  {
    icon: BookOpen,
    title: 'PDF Yönetimi',
    description: 'Tüm belgelerinizi tek bir yerde yükleyin, düzenleyin ve yönetin. Bulut depolama ile her yerden erişin.',
  },
  {
    icon: MessageSquare,
    title: 'AI Sohbet',
    description: 'Belgeleriniz hakkında doğal dilde sorular sorun. Google Gemini teknolojisi ile anında cevaplar alın.',
  },
  {
    icon: Languages,
    title: 'Hızlı Çeviri',
    description: 'Metni seçin, anında çevirisi görünsün. Tıbbi terimler otomatik algılansın ve açıklansın.',
  },
  {
    icon: Highlighter,
    title: 'Akıllı Notlar',
    description: 'Vurgulama, altı çizme ve not ekleme. 4 renk seçeneği ile önemli kısımları işaretleyin.',
  },
  {
    icon: Cloud,
    title: 'Senkronizasyon',
    description: 'iOS ve web arasında otomatik senkronizasyon. Kaldığınız yerden devam edin.',
  },
  {
    icon: ShieldCheck,
    title: 'Güvenli Depolama',
    description: 'Row Level Security ile verileriniz korunur. Sadece siz erişebilirsiniz.',
  },
];

const steps = [
  { num: '01', title: 'Hesap Oluşturun', desc: 'Google veya Apple hesabınızla saniyeler içinde giriş yapın.' },
  { num: '02', title: 'PDF Yükleyin', desc: 'Belgelerinizi sürükleyip bırakın. Otomatik kategorize edilsin.' },
  { num: '03', title: 'AI ile Keşfedin', desc: 'Yapay zeka asistanınız ile belgelerinizi analiz edin ve öğrenin.' },
];

export function FeaturesGrid() {
  return (
    <>
      {/* Features */}
      <section id="features" className="bg-[#FDFAF6] px-6 py-24 sm:py-28">
        <div className="mx-auto max-w-5xl">
          {/* Section header */}
          <div className="mb-14 text-center">
            <span className="mb-4 inline-block rounded-full border border-[#D4713C]/15 bg-[#D4713C]/[0.06] px-4 py-1.5 text-[12px] font-semibold uppercase tracking-[0.12em] text-[#D4713C]">
              Özellikler
            </span>
            <h2 className="mb-4 text-3xl font-bold leading-tight tracking-tight text-[#2A2520] sm:text-4xl">
              Belgeleriniz için her şey,
              <br className="hidden sm:block" />
              <span className="text-[#2A2520]/35">tek bir yerde</span>
            </h2>
          </div>

          {/* Feature cards grid */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature, i) => {
              const Icon = feature.icon;
              return (
                <div
                  key={feature.title}
                  className="group rounded-2xl border border-[#2A2520]/[0.06] bg-white/70 p-6 backdrop-blur-sm transition-all duration-300 hover:border-[#D4713C]/20 hover:bg-white hover:shadow-[0_8px_30px_rgba(212,113,60,0.06)]"
                  style={{ animationDelay: `${i * 80}ms` }}
                >
                  <div className="mb-4 inline-flex size-11 items-center justify-center rounded-xl bg-gradient-to-br from-[#D4713C]/10 to-[#D4713C]/[0.04] ring-1 ring-[#D4713C]/10">
                    <Icon className="size-5 text-[#D4713C]" strokeWidth={1.8} />
                  </div>
                  <h3 className="mb-2 text-[15px] font-semibold tracking-tight text-[#2A2520]">{feature.title}</h3>
                  <p className="text-[14px] leading-relaxed text-[#2A2520]/50">{feature.description}</p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section id="how-it-works" className="bg-gradient-to-b from-[#FAF0E8] to-[#FDFAF6] px-6 py-24 sm:py-28">
        <div className="mx-auto max-w-4xl">
          {/* Section header */}
          <div className="mb-14 text-center">
            <span className="mb-4 inline-block rounded-full border border-[#D4713C]/15 bg-[#D4713C]/[0.06] px-4 py-1.5 text-[12px] font-semibold uppercase tracking-[0.12em] text-[#D4713C]">
              Nasıl Çalışır
            </span>
            <h2 className="text-3xl font-bold leading-tight tracking-tight text-[#2A2520] sm:text-4xl">
              3 adımda başlayın
            </h2>
          </div>

          {/* Steps */}
          <div className="grid gap-10 sm:grid-cols-3 sm:gap-8">
            {steps.map((step, i) => (
              <div key={step.num} className="relative text-center">
                {/* Numbered circle */}
                <div className="mx-auto mb-6 flex size-16 items-center justify-center rounded-2xl bg-gradient-to-br from-[#D4713C] to-[#C0632F] shadow-[0_4px_20px_rgba(212,113,60,0.25)]">
                  <span className="text-lg font-bold text-white">{step.num}</span>
                </div>
                {/* Connector line */}
                {i < steps.length - 1 && (
                  <div className="absolute left-[calc(50%+2.5rem)] top-8 hidden h-px w-[calc(100%-5rem)] bg-gradient-to-r from-[#D4713C]/20 to-transparent sm:block" aria-hidden="true" />
                )}
                <h3 className="mb-2 text-base font-semibold text-[#2A2520]">{step.title}</h3>
                <p className="mx-auto max-w-[240px] text-[14px] leading-relaxed text-[#2A2520]/50">{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
