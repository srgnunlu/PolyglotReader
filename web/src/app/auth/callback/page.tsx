'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getSupabase } from '@/lib/supabase';

export default function AuthCallbackPage() {
    const router = useRouter();
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const handleCallback = async () => {
            const supabase = getSupabase();

            try {
                // Handle the OAuth callback
                const { data, error } = await supabase.auth.getSession();

                if (error) throw error;

                if (data.session) {
                    // Successfully logged in, redirect to library
                    router.push('/library');
                } else {
                    // No session, redirect to login
                    router.push('/login');
                }
            } catch (err) {
                console.error('Auth callback error:', err);
                setError(err instanceof Error ? err.message : 'Authentication failed');
            }
        };

        handleCallback();
    }, [router]);

    if (error) {
        return (
            <div style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                height: '100vh',
                gap: '16px',
                color: 'var(--text-secondary)',
            }}>
                <span style={{ fontSize: '3rem' }}>⚠️</span>
                <p>{error}</p>
                <button
                    className="btn btn-primary"
                    onClick={() => router.push('/login')}
                >
                    Giriş Sayfasına Dön
                </button>
            </div>
        );
    }

    return (
        <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100vh',
            gap: '16px',
        }}>
            <div className="spinner" style={{ width: 40, height: 40 }} />
            <p style={{ color: 'var(--text-secondary)' }}>Giriş yapılıyor...</p>
        </div>
    );
}
