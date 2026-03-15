'use client';

import { useToast, ToastType } from '@/contexts/ToastContext';

const iconMap: Record<ToastType, string> = {
    success: '\u2713',
    error: '\u2717',
    warning: '!',
    info: 'i',
};

const colorMap: Record<ToastType, { bg: string; border: string; icon: string }> = {
    success: { bg: 'rgba(34,197,94,0.1)', border: 'rgba(34,197,94,0.4)', icon: '#16a34a' },
    error: { bg: 'rgba(239,68,68,0.1)', border: 'rgba(239,68,68,0.4)', icon: '#dc2626' },
    warning: { bg: 'rgba(245,158,11,0.1)', border: 'rgba(245,158,11,0.4)', icon: '#d97706' },
    info: { bg: 'rgba(99,102,241,0.1)', border: 'rgba(99,102,241,0.4)', icon: '#6366f1' },
};

export function ToastContainer() {
    const { toasts, dismissToast } = useToast();

    if (toasts.length === 0) return null;

    return (
        <div style={{
            position: 'fixed',
            top: 20,
            right: 20,
            zIndex: 9999,
            display: 'flex',
            flexDirection: 'column',
            gap: 8,
            pointerEvents: 'none',
        }}>
            {toasts.map(toast => {
                const colors = colorMap[toast.type];
                return (
                    <div
                        key={toast.id}
                        style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: 10,
                            padding: '12px 16px',
                            background: colors.bg,
                            backdropFilter: 'blur(12px)',
                            border: `1px solid ${colors.border}`,
                            borderRadius: 12,
                            boxShadow: '0 4px 24px rgba(0,0,0,0.12)',
                            fontSize: '0.875rem',
                            color: 'var(--text-primary, #1c1917)',
                            pointerEvents: 'auto',
                            animation: 'toastSlideIn 0.3s ease',
                            maxWidth: 360,
                        }}
                    >
                        <span style={{
                            width: 24,
                            height: 24,
                            borderRadius: '50%',
                            background: colors.icon,
                            color: 'white',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            fontSize: '0.75rem',
                            fontWeight: 700,
                            flexShrink: 0,
                        }}>
                            {iconMap[toast.type]}
                        </span>
                        <span style={{ flex: 1 }}>{toast.message}</span>
                        <button
                            onClick={() => dismissToast(toast.id)}
                            style={{
                                background: 'none',
                                border: 'none',
                                cursor: 'pointer',
                                color: 'var(--text-tertiary, #a8a29e)',
                                fontSize: '1.1rem',
                                padding: '0 4px',
                                lineHeight: 1,
                            }}
                        >
                            &times;
                        </button>
                    </div>
                );
            })}
            <style>{`
                @keyframes toastSlideIn {
                    from { opacity: 0; transform: translateX(24px); }
                    to { opacity: 1; transform: translateX(0); }
                }
            `}</style>
        </div>
    );
}
