// Features grid + How It Works — inline styles for reliability, no Tailwind arbitrary values
'use client';

import { BookOpen, MessageSquare, Languages, Highlighter, Cloud, ShieldCheck, type LucideIcon } from 'lucide-react';

const features: { icon: LucideIcon; title: string; description: string }[] = [
  { icon: BookOpen, title: 'PDF Yönetimi', description: 'Tüm belgelerinizi tek bir yerde yükleyin, düzenleyin ve yönetin. Bulut depolama ile her yerden erişin.' },
  { icon: MessageSquare, title: 'AI Sohbet', description: 'Belgeleriniz hakkında doğal dilde sorular sorun. Google Gemini teknolojisi ile anında cevaplar alın.' },
  { icon: Languages, title: 'Hızlı Çeviri', description: 'Metni seçin, anında çevirisi görünsün. Tıbbi terimler otomatik algılansın ve açıklansın.' },
  { icon: Highlighter, title: 'Akıllı Notlar', description: 'Vurgulama, altı çizme ve not ekleme. 4 renk seçeneği ile önemli kısımları işaretleyin.' },
  { icon: Cloud, title: 'Senkronizasyon', description: 'iOS ve web arasında otomatik senkronizasyon. Kaldığınız yerden devam edin.' },
  { icon: ShieldCheck, title: 'Güvenli Depolama', description: 'Row Level Security ile verileriniz korunur. Sadece siz erişebilirsiniz.' },
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
      <section id="features" className="px-6 py-20 sm:py-24" style={{ backgroundColor: '#FDFAF6' }}>
        <div className="mx-auto max-w-5xl">
          {/* Header */}
          <div className="mb-12 text-center">
            <span
              className="mb-4 inline-block rounded-full px-4 py-1.5 text-xs font-semibold uppercase tracking-widest"
              style={{ color: '#D4713C', backgroundColor: 'rgba(212,113,60,0.06)', border: '1px solid rgba(212,113,60,0.15)' }}
            >
              Özellikler
            </span>
            <h2 className="mb-3 text-3xl font-bold leading-tight tracking-tight sm:text-4xl" style={{ color: '#2A2520' }}>
              Belgeleriniz için her şey,
              <br className="hidden sm:block" />
              <span style={{ color: 'rgba(42,37,32,0.35)' }}>tek bir yerde</span>
            </h2>
          </div>

          {/* Cards */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => {
              const Icon = feature.icon;
              return (
                <div
                  key={feature.title}
                  className="rounded-2xl p-6 transition-all duration-300 hover:-translate-y-0.5"
                  style={{
                    backgroundColor: 'rgba(255,255,255,0.7)',
                    border: '1px solid rgba(42,37,32,0.06)',
                    backdropFilter: 'blur(8px)',
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = '#ffffff';
                    e.currentTarget.style.borderColor = 'rgba(212,113,60,0.2)';
                    e.currentTarget.style.boxShadow = '0 8px 30px rgba(212,113,60,0.06)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'rgba(255,255,255,0.7)';
                    e.currentTarget.style.borderColor = 'rgba(42,37,32,0.06)';
                    e.currentTarget.style.boxShadow = 'none';
                  }}
                >
                  <div
                    className="mb-4 inline-flex size-11 items-center justify-center rounded-xl"
                    style={{
                      background: 'linear-gradient(to bottom right, rgba(212,113,60,0.1), rgba(212,113,60,0.04))',
                      boxShadow: 'inset 0 0 0 1px rgba(212,113,60,0.1)',
                    }}
                  >
                    <Icon className="size-5" style={{ color: '#D4713C' }} strokeWidth={1.8} />
                  </div>
                  <h3 className="mb-2 text-sm font-semibold tracking-tight sm:text-base" style={{ color: '#2A2520' }}>
                    {feature.title}
                  </h3>
                  <p className="text-sm leading-relaxed" style={{ color: 'rgba(42,37,32,0.5)' }}>
                    {feature.description}
                  </p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section
        id="how-it-works"
        className="px-6 py-20 sm:py-24"
        style={{ background: 'linear-gradient(to bottom, #FAF0E8, #FDFAF6)' }}
      >
        <div className="mx-auto max-w-4xl">
          {/* Header */}
          <div className="mb-12 text-center">
            <span
              className="mb-4 inline-block rounded-full px-4 py-1.5 text-xs font-semibold uppercase tracking-widest"
              style={{ color: '#D4713C', backgroundColor: 'rgba(212,113,60,0.06)', border: '1px solid rgba(212,113,60,0.15)' }}
            >
              Nasıl Çalışır
            </span>
            <h2 className="text-3xl font-bold leading-tight tracking-tight sm:text-4xl" style={{ color: '#2A2520' }}>
              3 adımda başlayın
            </h2>
          </div>

          {/* Steps */}
          <div className="grid gap-10 sm:grid-cols-3 sm:gap-8">
            {steps.map((step, i) => (
              <div key={step.num} className="relative text-center">
                <div
                  className="mx-auto mb-5 flex size-14 items-center justify-center rounded-2xl sm:size-16"
                  style={{
                    background: 'linear-gradient(to bottom right, #D4713C, #C0632F)',
                    boxShadow: '0 4px 20px rgba(212,113,60,0.25)',
                  }}
                >
                  <span className="text-base font-bold text-white sm:text-lg">{step.num}</span>
                </div>
                {i < steps.length - 1 && (
                  <div
                    className="absolute left-[calc(50%+2.5rem)] top-7 hidden h-px w-[calc(100%-5rem)] sm:block"
                    style={{ background: 'linear-gradient(to right, rgba(212,113,60,0.2), transparent)' }}
                    aria-hidden="true"
                  />
                )}
                <h3 className="mb-2 text-sm font-semibold sm:text-base" style={{ color: '#2A2520' }}>
                  {step.title}
                </h3>
                <p className="mx-auto max-w-[240px] text-sm leading-relaxed" style={{ color: 'rgba(42,37,32,0.5)' }}>
                  {step.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
