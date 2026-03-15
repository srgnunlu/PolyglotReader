'use client';

interface SkeletonProps {
    width?: string | number;
    height?: string | number;
    borderRadius?: number;
    style?: React.CSSProperties;
}

export function Skeleton({ width = '100%', height = 16, borderRadius = 8, style }: SkeletonProps) {
    return (
        <div
            style={{
                width, height, borderRadius,
                background: 'linear-gradient(90deg, var(--bg-tertiary, #f5f5f4) 25%, var(--bg-secondary, #e7e5e4) 50%, var(--bg-tertiary, #f5f5f4) 75%)',
                backgroundSize: '200% 100%',
                animation: 'shimmer 1.5s infinite',
                ...style,
            }}
        />
    );
}

export function SkeletonCard() {
    return (
        <div style={{
            borderRadius: 16, overflow: 'hidden',
            border: '1px solid var(--border-color, #e5e7eb)',
            background: 'var(--bg-secondary, white)',
        }}>
            <Skeleton height={180} borderRadius={0} />
            <div style={{ padding: 16 }}>
                <Skeleton height={18} width="80%" style={{ marginBottom: 8 }} />
                <Skeleton height={14} width="50%" />
            </div>
        </div>
    );
}

export function SkeletonList() {
    return (
        <div style={{
            display: 'flex', alignItems: 'center', gap: 16, padding: 16,
            borderRadius: 12, border: '1px solid var(--border-color, #e5e7eb)',
            background: 'var(--bg-secondary, white)',
        }}>
            <Skeleton width={48} height={64} borderRadius={8} />
            <div style={{ flex: 1 }}>
                <Skeleton height={16} width="60%" style={{ marginBottom: 8 }} />
                <Skeleton height={12} width="30%" />
            </div>
        </div>
    );
}

export function SkeletonNoteCard() {
    return (
        <div style={{
            padding: 16, borderRadius: 12,
            border: '1px solid var(--border-color, #e5e7eb)',
            borderLeft: '4px solid var(--bg-tertiary)',
            background: 'var(--bg-secondary, white)',
        }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 10 }}>
                <Skeleton height={12} width={80} />
                <Skeleton height={12} width={60} />
            </div>
            <Skeleton height={14} width="90%" style={{ marginBottom: 8 }} />
            <Skeleton height={14} width="70%" />
        </div>
    );
}

// Global animation style (injected once)
export function SkeletonStyles() {
    return (
        <style>{`
            @keyframes shimmer {
                0% { background-position: 200% 0; }
                100% { background-position: -200% 0; }
            }
        `}</style>
    );
}
