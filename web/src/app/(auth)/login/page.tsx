'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import styles from './login.module.css';

export default function LoginPage() {
    const router = useRouter();
    const { signIn, signUp, signInWithGoogle, isLoading, error } = useAuth();
    const [isSignUp, setIsSignUp] = useState(false);
    const [formData, setFormData] = useState({
        email: '',
        password: '',
        name: '',
    });

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

    const handleGoogleSignIn = async () => {
        await signInWithGoogle();
    };

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setFormData(prev => ({
            ...prev,
            [e.target.name]: e.target.value,
        }));
    };

    return (
        <div className={styles.container}>
            <div className={styles.background}>
                <div className={styles.gradientOrb1} />
                <div className={styles.gradientOrb2} />
            </div>

            <div className={styles.card}>
                <div className={styles.logo}>
                    <div className={styles.logoIcon}>📚</div>
                    <h1 className={styles.logoText}>PolyglotReader</h1>
                </div>

                <p className={styles.subtitle}>
                    {isSignUp
                        ? 'Hesap oluşturun ve okumaya başlayın'
                        : 'Hesabınıza giriş yapın'
                    }
                </p>

                {/* Google Sign In Button */}
                <button
                    type="button"
                    className={styles.googleBtn}
                    onClick={handleGoogleSignIn}
                    disabled={isLoading}
                >
                    <svg className={styles.googleIcon} viewBox="0 0 24 24">
                        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                    </svg>
                    <span>Google ile Giriş Yap</span>
                </button>

                <div className={styles.divider}>
                    <span>veya e-posta ile</span>
                </div>

                <form onSubmit={handleSubmit} className={styles.form}>
                    {isSignUp && (
                        <div className="input-group">
                            <label className="input-label" htmlFor="name">Ad</label>
                            <input
                                id="name"
                                type="text"
                                name="name"
                                className="input"
                                placeholder="Adınız"
                                value={formData.name}
                                onChange={handleChange}
                            />
                        </div>
                    )}

                    <div className="input-group">
                        <label className="input-label" htmlFor="email">E-posta</label>
                        <input
                            id="email"
                            type="email"
                            name="email"
                            className="input"
                            placeholder="ornek@email.com"
                            value={formData.email}
                            onChange={handleChange}
                            required
                        />
                    </div>

                    <div className="input-group">
                        <label className="input-label" htmlFor="password">Şifre</label>
                        <input
                            id="password"
                            type="password"
                            name="password"
                            className="input"
                            placeholder="••••••••"
                            value={formData.password}
                            onChange={handleChange}
                            required
                            minLength={6}
                        />
                    </div>

                    {error && (
                        <div className={styles.error}>
                            {error}
                        </div>
                    )}

                    <button
                        type="submit"
                        className="btn btn-primary btn-lg"
                        disabled={isLoading}
                        style={{ width: '100%' }}
                    >
                        {isLoading ? (
                            <span className="spinner" />
                        ) : isSignUp ? (
                            'Hesap Oluştur'
                        ) : (
                            'Giriş Yap'
                        )}
                    </button>
                </form>

                <button
                    type="button"
                    className={styles.switchBtn}
                    onClick={() => setIsSignUp(!isSignUp)}
                >
                    {isSignUp
                        ? 'Zaten hesabınız var mı? Giriş yapın'
                        : 'Hesabınız yok mu? Kayıt olun'
                    }
                </button>
            </div>
        </div>
    );
}

