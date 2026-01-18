'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import styles from './landing.module.css';

export default function LandingPage() {
  const router = useRouter();
  const { signInWithGoogle, isLoading, isAuthenticated } = useAuth();
  const [isScrolled, setIsScrolled] = useState(false);
  const [authLoading, setAuthLoading] = useState<'google' | 'apple' | null>(null);

  // Redirect if already authenticated
  useEffect(() => {
    if (isAuthenticated) {
      router.push('/library');
    }
  }, [isAuthenticated, router]);

  // Handle scroll for header styling
  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 50);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const handleGoogleSignIn = async () => {
    setAuthLoading('google');
    await signInWithGoogle();
  };

  const handleAppleSignIn = async () => {
    setAuthLoading('apple');
    // Apple Sign-In will be implemented
    // For now, show a message or redirect to Google
    alert('Apple ile giriş yakında aktif olacak. Lütfen Google ile giriş yapın.');
    setAuthLoading(null);
  };

  const scrollToSection = (id: string) => {
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const features = [
    {
      icon: '📄',
      title: 'PDF Yönetimi',
      description: 'Tüm PDF belgelerinizi tek bir yerde yükleyin, düzenleyin ve yönetin. Bulut depolama ile her yerden erişin.'
    },
    {
      icon: '🤖',
      title: 'AI Destekli Analiz',
      description: 'Google Gemini teknolojisi ile belgelerinizi analiz edin, sorular sorun ve akıllı özetler alın.'
    },
    {
      icon: '✏️',
      title: 'Akıllı Notlar',
      description: 'Vurgulama, altı çizme ve not ekleme araçları ile önemli kısımları işaretleyin.'
    },
    {
      icon: '🔄',
      title: 'Senkronizasyon',
      description: 'Tüm cihazlarınız arasında otomatik senkronizasyon. Kaldığınız yerden devam edin.'
    },
    {
      icon: '💬',
      title: 'AI Sohbet',
      description: 'Belgeleriniz hakkında doğal dilde sorular sorun ve anında cevaplar alın.'
    },
    {
      icon: '🔒',
      title: 'Güvenli Depolama',
      description: 'Verileriniz AES-256 şifreleme ile korunur. Gizliliğiniz bizim önceliğimiz.'
    }
  ];

  const steps = [
    {
      number: '1',
      title: 'Hesap Oluşturun',
      description: 'Google veya Apple hesabınızla saniyeler içinde giriş yapın.'
    },
    {
      number: '2',
      title: 'PDF Yükleyin',
      description: 'Belgelerinizi yükleyin, otomatik olarak kategorize edilsin.'
    },
    {
      number: '3',
      title: 'AI ile Keşfedin',
      description: 'Yapay zeka asistanınız ile belgelerinizi analiz edin ve öğrenin.'
    }
  ];

  return (
    <div className={styles.page}>
      {/* Animated Background */}
      <div className={styles.background}>
        <div className={`${styles.orb} ${styles.orb1}`} />
        <div className={`${styles.orb} ${styles.orb2}`} />
        <div className={`${styles.orb} ${styles.orb3}`} />
      </div>

      {/* Header */}
      <header className={`${styles.header} ${isScrolled ? styles.headerScrolled : ''}`}>
        <nav className={styles.nav}>
          <div className={styles.logo}>
            <span className={styles.logoIcon}>📄</span>
            <span className={styles.logoText}>Corio Docs</span>
          </div>

          <div className={styles.navLinks}>
            <a href="#features" className={styles.navLink} onClick={(e) => { e.preventDefault(); scrollToSection('features'); }}>
              Özellikler
            </a>
            <a href="#how-it-works" className={styles.navLink} onClick={(e) => { e.preventDefault(); scrollToSection('how-it-works'); }}>
              Nasıl Çalışır
            </a>
            <a href="#footer" className={styles.navLink} onClick={(e) => { e.preventDefault(); scrollToSection('footer'); }}>
              İletişim
            </a>
          </div>

          <div className={styles.navButtons}>
            <button
              className={`${styles.authButton} ${styles.googleButton}`}
              onClick={handleGoogleSignIn}
              disabled={isLoading}
              style={{ padding: '10px 20px' }}
            >
              {authLoading === 'google' ? (
                <span className={styles.loadingSpinner} />
              ) : (
                <>
                  <svg className={styles.authIcon} viewBox="0 0 24 24">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                  </svg>
                  <span>Giriş Yap</span>
                </>
              )}
            </button>
          </div>
        </nav>
      </header>

      {/* Hero Section */}
      <section className={styles.hero}>
        <div className={styles.heroContent}>
          <span className={styles.heroSubtitle}>
            ✨ AI Destekli PDF Okuyucu
          </span>

          <h1 className={styles.heroTitle}>
            <span className={styles.heroTitleWhite}>Belgelerinizi </span>
            <span className={styles.heroTitleGradient}>Akıllı Asistanınızla</span>
            <span className={styles.heroTitleWhite}> Keşfedin</span>
          </h1>

          <p className={styles.heroDescription}>
            Corio Docs ile PDF belgelerinizi yapay zeka destekli olarak okuyun, notlar alın ve her yerden erişin.
            Google Gemini teknolojisi ile belgeleriniz hakkında sorular sorun.
          </p>

          <div className={styles.heroButtons}>
            <button
              className={`${styles.authButton} ${styles.googleButton}`}
              onClick={handleGoogleSignIn}
              disabled={isLoading}
            >
              {authLoading === 'google' ? (
                <span className={styles.loadingSpinner} />
              ) : (
                <>
                  <svg className={styles.authIcon} viewBox="0 0 24 24">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                  </svg>
                  <span>Google ile Başlayın</span>
                </>
              )}
            </button>

            <button
              className={`${styles.authButton} ${styles.appleButton}`}
              onClick={handleAppleSignIn}
              disabled={isLoading}
            >
              {authLoading === 'apple' ? (
                <span className={styles.loadingSpinner} />
              ) : (
                <>
                  <svg className={styles.authIcon} viewBox="0 0 24 24" fill="white">
                    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                  </svg>
                  <span>Apple ile Başlayın</span>
                </>
              )}
            </button>
          </div>

          <div className={styles.statsBar}>
            <div className={styles.stat}>
              <div className={styles.statNumber}>10K+</div>
              <div className={styles.statLabel}>Aktif Kullanıcı</div>
            </div>
            <div className={styles.stat}>
              <div className={styles.statNumber}>50K+</div>
              <div className={styles.statLabel}>Analiz Edilen Belge</div>
            </div>
            <div className={styles.stat}>
              <div className={styles.statNumber}>4.8★</div>
              <div className={styles.statLabel}>App Store</div>
            </div>
          </div>
        </div>

        <div className={styles.scrollIndicator}>
          <div className={styles.scrollMouse} />
          <span>Keşfet</span>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className={styles.features}>
        <div className={styles.sectionHeader}>
          <span className={styles.sectionSubtitle}>Özellikler</span>
          <h2 className={styles.sectionTitle}>Belgeleriniz İçin Her Şey</h2>
          <p className={styles.sectionDescription}>
            Corio Docs, PDF belgelerinizi yönetmek ve analiz etmek için ihtiyacınız olan tüm araçları sunar.
          </p>
        </div>

        <div className={styles.featuresGrid}>
          {features.map((feature, index) => (
            <div
              key={index}
              className={styles.featureCard}
              style={{ animationDelay: `${index * 0.1}s` }}
            >
              <div className={styles.featureIcon}>{feature.icon}</div>
              <h3 className={styles.featureTitle}>{feature.title}</h3>
              <p className={styles.featureDescription}>{feature.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How It Works Section */}
      <section id="how-it-works" className={styles.howItWorks}>
        <div className={styles.sectionHeader}>
          <span className={styles.sectionSubtitle}>Nasıl Çalışır</span>
          <h2 className={styles.sectionTitle}>3 Basit Adımda Başlayın</h2>
          <p className={styles.sectionDescription}>
            Corio Docs ile belgelerinizi yönetmek çok kolay.
          </p>
        </div>

        <div className={styles.stepsContainer}>
          {steps.map((step, index) => (
            <div key={index} className={styles.step}>
              <div className={styles.stepNumber}>{step.number}</div>
              <h3 className={styles.stepTitle}>{step.title}</h3>
              <p className={styles.stepDescription}>{step.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* CTA Section */}
      <section className={styles.cta}>
        <div className={styles.ctaCard}>
          <h2 className={styles.ctaTitle}>Hemen Ücretsiz Başlayın</h2>
          <p className={styles.ctaDescription}>
            Belgelerinizi yapay zeka ile keşfetmeye bugün başlayın. Kredi kartı gerektirmez.
          </p>
          <div className={styles.ctaButtons}>
            <button
              className={`${styles.authButton} ${styles.googleButton}`}
              onClick={handleGoogleSignIn}
              disabled={isLoading}
            >
              <svg className={styles.authIcon} viewBox="0 0 24 24">
                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
              </svg>
              <span>Google ile Ücretsiz Başlayın</span>
            </button>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer id="footer" className={styles.footer}>
        <div className={styles.footerContent}>
          <div className={styles.footerGrid}>
            <div className={styles.footerSection}>
              <div className={styles.logo} style={{ marginBottom: '16px' }}>
                <span className={styles.logoIcon}>📄</span>
                <span className={styles.logoText}>Corio Docs</span>
              </div>
              <p style={{ color: '#64748b', fontSize: '0.875rem', lineHeight: '1.6' }}>
                AI destekli akıllı PDF okuyucu ve belge yönetimi uygulaması.
              </p>
            </div>

            <div className={styles.footerSection}>
              <h4>Yasal</h4>
              <ul className={styles.footerLinks}>
                <li><a href="/legal/privacy-policy.html">🇹🇷 Gizlilik Politikası</a></li>
                <li><a href="/legal/privacy-policy-en.html">🇬🇧 Privacy Policy</a></li>
                <li><a href="/legal/terms-of-service.html">🇹🇷 Kullanım Koşulları</a></li>
                <li><a href="/legal/terms-of-service-en.html">🇬🇧 Terms of Service</a></li>
              </ul>
            </div>

            <div className={styles.footerSection}>
              <h4>Sözleşmeler</h4>
              <ul className={styles.footerLinks}>
                <li><a href="/legal/eula.html">🇹🇷 EULA (Lisans Sözleşmesi)</a></li>
                <li><a href="/legal/eula-en.html">🇬🇧 EULA (License Agreement)</a></li>
                <li><a href="/legal/data-deletion.html">🇹🇷 Veri Silme Talebi</a></li>
                <li><a href="/legal/data-deletion-en.html">🇬🇧 Data Deletion Request</a></li>
              </ul>
            </div>

            <div className={styles.footerSection}>
              <h4>İletişim</h4>
              <ul className={styles.footerLinks}>
                <li><a href="mailto:docs@corioscan.com">📧 docs@corioscan.com</a></li>
                <li><a href="https://docs.corioscan.com">🌐 docs.corioscan.com</a></li>
              </ul>
            </div>
          </div>

          <div className={styles.footerBottom}>
            <p className={styles.copyright}>
              © 2026 Corio Docs. Tüm hakları saklıdır.
            </p>
            <div className={styles.languageSwitch}>
              <a href="#">🇹🇷 Türkçe</a>
              <a href="#">🇬🇧 English</a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
