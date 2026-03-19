// OAuth callback handler — exchanges code for session and redirects
'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getSupabase } from '@/lib/supabase';
import { Button } from '@/components/ui/button';

export default function AuthCallbackPage() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const handleCallback = async () => {
      const supabase = getSupabase();
      try {
        const { data, error } = await supabase.auth.getSession();
        if (error) throw error;
        router.push(data.session ? '/library' : '/login');
      } catch (err) {
        console.error('Auth callback error:', err);
        setError(err instanceof Error ? err.message : 'Authentication failed');
      }
    };
    handleCallback();
  }, [router]);

  if (error) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4 bg-corio-bg text-corio-fg/60">
        <span className="text-5xl">⚠️</span>
        <p>{error}</p>
        <Button onClick={() => router.push('/login')} className="bg-corio-accent text-white hover:bg-corio-accent-hover">
          Giriş Sayfasına Dön
        </Button>
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col items-center justify-center gap-4 bg-corio-bg text-corio-fg/60">
      <div className="h-10 w-10 animate-spin rounded-full border-2 border-corio-border border-t-corio-accent" />
      <p>Giriş yapılıyor...</p>
    </div>
  );
}
