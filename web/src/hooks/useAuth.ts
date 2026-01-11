'use client';

import { useEffect, useState, useCallback } from 'react';
import type { User, Session, AuthChangeEvent } from '@supabase/supabase-js';
import { getSupabase } from '@/lib/supabase';
import { User as AppUser } from '@/types/models';

interface AuthState {
    user: AppUser | null;
    session: Session | null;
    isLoading: boolean;
    error: string | null;
}

export function useAuth() {
    const [authState, setAuthState] = useState<AuthState>({
        user: null,
        session: null,
        isLoading: true,
        error: null,
    });

    const supabase = getSupabase();

    // Map Supabase user to app user
    const mapToAppUser = (user: User): AppUser => ({
        id: user.id,
        email: user.email || '',
        name: user.user_metadata?.name || user.email?.split('@')[0] || 'User',
        avatarURL: user.user_metadata?.avatar_url,
    });

    // Check session on mount
    useEffect(() => {
        const checkSession = async () => {
            try {
                const { data: { session }, error } = await supabase.auth.getSession();

                if (error) throw error;

                setAuthState({
                    user: session?.user ? mapToAppUser(session.user) : null,
                    session,
                    isLoading: false,
                    error: null,
                });
            } catch (err) {
                setAuthState({
                    user: null,
                    session: null,
                    isLoading: false,
                    error: err instanceof Error ? err.message : 'Session check failed',
                });
            }
        };

        checkSession();

        // Listen for auth changes
        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            (event: AuthChangeEvent, session: Session | null) => {
                setAuthState(prev => ({
                    ...prev,
                    user: session?.user ? mapToAppUser(session.user) : null,
                    session,
                    isLoading: false,
                }));
            }
        );

        return () => subscription.unsubscribe();
    }, [supabase.auth]);

    // Sign in with email
    const signIn = useCallback(async (email: string, password: string) => {
        setAuthState(prev => ({ ...prev, isLoading: true, error: null }));

        try {
            const { data, error } = await supabase.auth.signInWithPassword({
                email,
                password,
            });

            if (error) throw error;

            setAuthState({
                user: data.user ? mapToAppUser(data.user) : null,
                session: data.session,
                isLoading: false,
                error: null,
            });

            return { success: true };
        } catch (err) {
            const message = err instanceof Error ? err.message : 'Sign in failed';
            setAuthState(prev => ({
                ...prev,
                isLoading: false,
                error: message,
            }));
            return { success: false, error: message };
        }
    }, [supabase.auth]);

    // Sign up with email
    const signUp = useCallback(async (email: string, password: string, name?: string) => {
        setAuthState(prev => ({ ...prev, isLoading: true, error: null }));

        try {
            const { data, error } = await supabase.auth.signUp({
                email,
                password,
                options: {
                    data: { name: name || email.split('@')[0] },
                },
            });

            if (error) throw error;

            setAuthState({
                user: data.user ? mapToAppUser(data.user) : null,
                session: data.session,
                isLoading: false,
                error: null,
            });

            return { success: true };
        } catch (err) {
            const message = err instanceof Error ? err.message : 'Sign up failed';
            setAuthState(prev => ({
                ...prev,
                isLoading: false,
                error: message,
            }));
            return { success: false, error: message };
        }
    }, [supabase.auth]);

    // Sign out
    const signOut = useCallback(async () => {
        setAuthState(prev => ({ ...prev, isLoading: true }));

        try {
            await supabase.auth.signOut();
            setAuthState({
                user: null,
                session: null,
                isLoading: false,
                error: null,
            });
        } catch (err) {
            setAuthState(prev => ({
                ...prev,
                isLoading: false,
                error: err instanceof Error ? err.message : 'Sign out failed',
            }));
        }
    }, [supabase.auth]);

    // Sign in with Google OAuth
    const signInWithGoogle = useCallback(async () => {
        setAuthState(prev => ({ ...prev, isLoading: true, error: null }));

        try {
            const { error } = await supabase.auth.signInWithOAuth({
                provider: 'google',
                options: {
                    redirectTo: `${window.location.origin}/auth/callback`,
                },
            });

            if (error) throw error;
            // User will be redirected to Google, then back to /auth/callback
        } catch (err) {
            const message = err instanceof Error ? err.message : 'Google sign in failed';
            setAuthState(prev => ({
                ...prev,
                isLoading: false,
                error: message,
            }));
            return { success: false, error: message };
        }
    }, [supabase.auth]);

    return {
        ...authState,
        signIn,
        signUp,
        signOut,
        signInWithGoogle,
        isAuthenticated: !!authState.session,
    };
}
