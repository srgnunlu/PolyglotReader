// Login page — email/password + Google OAuth, with sign-up toggle
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { motion, type Variants } from 'framer-motion';
import { BookOpen } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';

// Google branded SVG logo
function GoogleLogo() {
  return (
    <svg className="size-5 shrink-0" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  );
}

const cardVariants: Variants = {
  hidden: { opacity: 0, y: 32, scale: 0.97 },
  visible: { opacity: 1, y: 0, scale: 1, transition: { duration: 0.45, ease: 'easeOut' as const } },
};

export default function LoginPage() {
  const router = useRouter();
  const { signIn, signUp, signInWithGoogle, isLoading, error } = useAuth();
  const [isSignUp, setIsSignUp] = useState(false);
  const [formData, setFormData] = useState({ email: '', password: '', name: '' });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    let result;
    if (isSignUp) {
      result = await signUp(formData.email, formData.password, formData.name);
    } else {
      result = await signIn(formData.email, formData.password);
    }

    if (result.success) {
      router.push('/library');
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData((prev) => ({ ...prev, [e.target.name]: e.target.value }));
  };

  const handleGoogleSignIn = async () => {
    await signInWithGoogle();
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-corio-bg to-corio-accent-subtle px-4 py-12">
      {/* Decorative background orbs */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden" aria-hidden="true">
        <div className="absolute -top-32 -right-32 h-80 w-80 rounded-full bg-corio-accent/10 blur-3xl" />
        <div className="absolute -bottom-32 -left-32 h-80 w-80 rounded-full bg-corio-accent/8 blur-3xl" />
      </div>

      <motion.div
        variants={cardVariants}
        initial="hidden"
        animate="visible"
        className="relative w-full max-w-[420px]"
      >
        <Card className="border-corio-border bg-corio-bg shadow-lg">
          <CardHeader className="pb-2 text-center">
            {/* Brand logo */}
            <div className="mb-4 flex justify-center">
              <div className="flex size-12 items-center justify-center rounded-2xl bg-corio-accent shadow-md">
                <BookOpen className="size-6 text-white" />
              </div>
            </div>
            <CardTitle className="text-xl font-bold text-corio-fg">Corio Docs</CardTitle>
            <CardDescription className="text-corio-fg/60">
              {isSignUp ? 'Hesap oluşturun ve okumaya başlayın' : 'Hesabınıza giriş yapın'}
            </CardDescription>
          </CardHeader>

          <CardContent className="space-y-4 pt-4">
            {/* Google Sign-In — primary CTA */}
            <button
              type="button"
              onClick={handleGoogleSignIn}
              disabled={isLoading}
              className="inline-flex h-11 w-full items-center justify-center gap-3 rounded-lg border border-gray-200 bg-white px-4 text-sm font-medium text-gray-700 shadow-sm transition-all hover:shadow-md hover:bg-gray-50 disabled:pointer-events-none disabled:opacity-50"
            >
              {isLoading ? (
                <span className="size-5 animate-spin rounded-full border-2 border-gray-300 border-t-gray-700" />
              ) : (
                <GoogleLogo />
              )}
              <span>Google ile Giriş Yap</span>
            </button>

            {/* Divider */}
            <div className="relative flex items-center gap-3">
              <div className="h-px flex-1 bg-corio-border" />
              <span className="text-xs text-corio-fg/40">veya e-posta ile</span>
              <div className="h-px flex-1 bg-corio-border" />
            </div>

            {/* Email / Password form */}
            <form onSubmit={handleSubmit} className="space-y-3" noValidate>
              {isSignUp && (
                <div className="space-y-1.5">
                  <Label htmlFor="name" className="text-corio-fg/70">Ad</Label>
                  <Input
                    id="name"
                    type="text"
                    name="name"
                    placeholder="Adınız"
                    value={formData.name}
                    onChange={handleChange}
                    className="h-10 border-corio-border bg-corio-surface-1 focus-visible:ring-corio-accent/30"
                  />
                </div>
              )}

              <div className="space-y-1.5">
                <Label htmlFor="email" className="text-corio-fg/70">E-posta</Label>
                <Input
                  id="email"
                  type="email"
                  name="email"
                  placeholder="ornek@email.com"
                  value={formData.email}
                  onChange={handleChange}
                  required
                  className="h-10 border-corio-border bg-corio-surface-1 focus-visible:ring-corio-accent/30"
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="password" className="text-corio-fg/70">Şifre</Label>
                <Input
                  id="password"
                  type="password"
                  name="password"
                  placeholder="••••••••"
                  value={formData.password}
                  onChange={handleChange}
                  required
                  minLength={6}
                  className="h-10 border-corio-border bg-corio-surface-1 focus-visible:ring-corio-accent/30"
                />
              </div>

              {/* Error message */}
              {error && (
                <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600 border border-red-200">
                  {error}
                </p>
              )}

              <Button
                type="submit"
                disabled={isLoading}
                className="h-11 w-full bg-corio-accent text-white hover:bg-corio-accent-hover rounded-lg text-sm font-semibold"
              >
                {isLoading ? (
                  <span className="size-5 animate-spin rounded-full border-2 border-white/30 border-t-white" />
                ) : isSignUp ? (
                  'Hesap Oluştur'
                ) : (
                  'Giriş Yap'
                )}
              </Button>
            </form>

            {/* Toggle sign-up / sign-in */}
            <button
              type="button"
              onClick={() => setIsSignUp(!isSignUp)}
              className="w-full text-center text-sm text-corio-fg/50 transition-colors hover:text-corio-accent"
            >
              {isSignUp
                ? 'Zaten hesabınız var mı? Giriş yapın'
                : 'Hesabınız yok mu? Kayıt olun'}
            </button>
          </CardContent>

          <CardFooter className="justify-center pt-0">
            <p className="text-center text-xs text-corio-fg/40 leading-relaxed">
              Giriş yaparak{' '}
              <Link href="/legal/terms-of-service" className="underline underline-offset-2 hover:text-corio-accent">
                Kullanım Şartlarını
              </Link>{' '}
              kabul ediyorsunuz
            </p>
          </CardFooter>
        </Card>
      </motion.div>
    </div>
  );
}
