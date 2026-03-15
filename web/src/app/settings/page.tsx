'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/contexts/ToastContext';
import { ThemeMode } from '@/types/models';

export default function SettingsPage() {
    return (
        <ProtectedRoute>
            <SettingsContent />
        </ProtectedRoute>
    );
}

function SettingsContent() {
    const router = useRouter();
    const { user, signOut } = useAuth();
    const { showToast } = useToast();

    const [theme, setTheme] = useState<ThemeMode>('system');
    const [defaultLang, setDefaultLang] = useState('tr');
    const [autoSummary, setAutoSummary] = useState(false);

    // Load preferences from localStorage
    useEffect(() => {
        const saved = localStorage.getItem('corio_preferences');
        if (saved) {
            try {
                const prefs = JSON.parse(saved);
                if (prefs.theme) setTheme(prefs.theme);
                if (prefs.defaultLang) setDefaultLang(prefs.defaultLang);
                if (prefs.autoSummary !== undefined) setAutoSummary(prefs.autoSummary);
            } catch {
                // ignore
            }
        }
    }, []);

    const savePreferences = () => {
        const prefs = { theme, defaultLang, autoSummary };
        localStorage.setItem('corio_preferences', JSON.stringify(prefs));
        showToast('Ayarlar kaydedildi', 'success');
    };

    const handleLogout = async () => {
        await signOut();
        router.push('/login');
    };

    const sectionStyle: React.CSSProperties = {
        background: 'var(--bg-secondary, white)',
        borderRadius: 16,
        padding: 24,
        border: '1px solid var(--border-color, #e5e7eb)',
        marginBottom: 16,
    };

    const labelStyle: React.CSSProperties = {
        fontSize: '0.85rem',
        fontWeight: 600,
        color: 'var(--text-primary)',
        display: 'block',
        marginBottom: 6,
    };

    const descStyle: React.CSSProperties = {
        fontSize: '0.8rem',
        color: 'var(--text-tertiary)',
        marginBottom: 10,
    };

    return (
        <div style={{
            minHeight: '100vh',
            background: 'var(--bg-primary, #fafaf9)',
            padding: '0 20px',
        }}>
            {/* Background orbs */}
            <div style={{ position: 'fixed', inset: 0, zIndex: 0, overflow: 'hidden', pointerEvents: 'none' }}>
                <div style={{
                    position: 'absolute', width: 400, height: 400, borderRadius: '50%',
                    background: 'radial-gradient(circle, rgba(99,102,241,0.08), transparent 70%)',
                    top: -100, right: -100,
                }} />
            </div>

            <div style={{ maxWidth: 640, margin: '0 auto', paddingTop: 32, paddingBottom: 48, position: 'relative', zIndex: 1 }}>
                {/* Header */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 32 }}>
                    <button
                        onClick={() => router.push('/library')}
                        style={{
                            background: 'none', border: 'none', cursor: 'pointer',
                            color: 'var(--color-primary-500)', fontSize: '0.9rem', fontWeight: 600,
                        }}
                    >
                        ← Kütüphane
                    </button>
                    <h1 style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-primary)', margin: 0 }}>
                        Ayarlar
                    </h1>
                </div>

                {/* Profile Section */}
                <div style={sectionStyle}>
                    <h2 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: 16, color: 'var(--text-primary)' }}>
                        Hesap
                    </h2>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                        <div style={{
                            width: 56, height: 56, borderRadius: '50%',
                            background: 'linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600))',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            color: 'white', fontSize: '1.3rem', fontWeight: 700,
                        }}>
                            {user?.name?.charAt(0).toUpperCase() || '?'}
                        </div>
                        <div>
                            <div style={{ fontWeight: 600, color: 'var(--text-primary)', fontSize: '1rem' }}>
                                {user?.name || 'Kullanıcı'}
                            </div>
                            <div style={{ color: 'var(--text-tertiary)', fontSize: '0.85rem' }}>
                                {user?.email}
                            </div>
                        </div>
                    </div>
                </div>

                {/* Theme Section */}
                <div style={sectionStyle}>
                    <h2 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: 16, color: 'var(--text-primary)' }}>
                        Görünüm
                    </h2>
                    <label style={labelStyle}>Tema</label>
                    <p style={descStyle}>Uygulamanın renk temasını seçin</p>
                    <div style={{ display: 'flex', gap: 8 }}>
                        {([
                            { value: 'light' as ThemeMode, label: 'Açık', icon: '☀️' },
                            { value: 'dark' as ThemeMode, label: 'Koyu', icon: '🌙' },
                            { value: 'system' as ThemeMode, label: 'Sistem', icon: '💻' },
                        ]).map(opt => (
                            <button
                                key={opt.value}
                                onClick={() => setTheme(opt.value)}
                                style={{
                                    flex: 1, padding: '12px 8px', borderRadius: 12,
                                    border: theme === opt.value
                                        ? '2px solid var(--color-primary-500)'
                                        : '1px solid var(--border-color, #e5e7eb)',
                                    background: theme === opt.value ? 'rgba(99,102,241,0.08)' : 'var(--bg-primary)',
                                    cursor: 'pointer', textAlign: 'center',
                                    transition: 'all 0.15s',
                                }}
                            >
                                <div style={{ fontSize: '1.2rem', marginBottom: 4 }}>{opt.icon}</div>
                                <div style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-primary)' }}>{opt.label}</div>
                            </button>
                        ))}
                    </div>
                </div>

                {/* Language Section */}
                <div style={sectionStyle}>
                    <h2 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: 16, color: 'var(--text-primary)' }}>
                        Dil & Çeviri
                    </h2>
                    <label style={labelStyle}>Varsayılan Çeviri Dili</label>
                    <p style={descStyle}>Hızlı çeviri için varsayılan hedef dil</p>
                    <select
                        value={defaultLang}
                        onChange={(e) => setDefaultLang(e.target.value)}
                        style={{
                            width: '100%', padding: '10px 14px', borderRadius: 10,
                            border: '1px solid var(--border-color)', fontSize: '0.9rem',
                            background: 'var(--bg-primary)', color: 'var(--text-primary)',
                            outline: 'none', cursor: 'pointer',
                        }}
                    >
                        <option value="tr">Türkçe</option>
                        <option value="en">English</option>
                        <option value="de">Deutsch</option>
                        <option value="fr">Français</option>
                        <option value="es">Español</option>
                        <option value="ar">العربية</option>
                    </select>
                </div>

                {/* AI Section */}
                <div style={sectionStyle}>
                    <h2 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: 16, color: 'var(--text-primary)' }}>
                        Yapay Zeka
                    </h2>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                            <label style={labelStyle}>Otomatik Özet</label>
                            <p style={{ ...descStyle, marginBottom: 0 }}>Yeni yüklenen dosyalar için otomatik özet oluştur</p>
                        </div>
                        <button
                            onClick={() => setAutoSummary(!autoSummary)}
                            style={{
                                width: 48, height: 28, borderRadius: 14,
                                background: autoSummary ? 'var(--color-primary-500)' : 'var(--bg-tertiary)',
                                border: 'none', cursor: 'pointer',
                                position: 'relative', transition: 'background 0.2s',
                                flexShrink: 0,
                            }}
                        >
                            <span style={{
                                position: 'absolute', top: 2, left: autoSummary ? 22 : 2,
                                width: 24, height: 24, borderRadius: '50%',
                                background: 'white', boxShadow: '0 1px 4px rgba(0,0,0,0.15)',
                                transition: 'left 0.2s',
                            }} />
                        </button>
                    </div>
                </div>

                {/* Save & Logout */}
                <div style={{ display: 'flex', gap: 12, justifyContent: 'space-between' }}>
                    <button
                        onClick={handleLogout}
                        style={{
                            padding: '12px 24px', borderRadius: 12,
                            background: 'rgba(239,68,68,0.1)', color: '#dc2626',
                            border: 'none', cursor: 'pointer', fontWeight: 600, fontSize: '0.9rem',
                        }}
                    >
                        Çıkış Yap
                    </button>
                    <button
                        onClick={savePreferences}
                        style={{
                            padding: '12px 32px', borderRadius: 12,
                            background: 'linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600))',
                            color: 'white', border: 'none', cursor: 'pointer',
                            fontWeight: 600, fontSize: '0.9rem',
                            boxShadow: '0 2px 8px rgba(99,102,241,0.3)',
                        }}
                    >
                        Kaydet
                    </button>
                </div>
            </div>
        </div>
    );
}
