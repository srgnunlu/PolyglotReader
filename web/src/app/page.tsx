'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import styles from './page.module.css';

export default function HomePage() {
  const router = useRouter();
  const { isAuthenticated, isLoading } = useAuth();

  useEffect(() => {
    if (!isLoading) {
      if (isAuthenticated) {
        router.push('/library');
      } else {
        router.push('/login');
      }
    }
  }, [isAuthenticated, isLoading, router]);

  return (
    <div className={styles.container}>
      <div className={styles.content}>
        <div className={styles.logo}>📚</div>
        <h1 className={styles.title}>PolyglotReader</h1>
        <p className={styles.subtitle}>AI-powered PDF reading & analysis</p>
        <div className="spinner" style={{ width: 32, height: 32 }} />
      </div>
    </div>
  );
}
