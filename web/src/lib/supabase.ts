import { createBrowserClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';

export function createBrowserSupabase() {
    return createBrowserClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );
}

// Singleton for client-side use only.
// On the server, always return a fresh unauthenticated instance
// (API routes should use createSupabaseWithToken instead).
let supabaseClient: ReturnType<typeof createBrowserClient> | null = null;

export function getSupabase() {
    if (typeof window === 'undefined') {
        // SSR context: never share state across requests
        return createBrowserSupabase();
    }
    if (!supabaseClient) {
        supabaseClient = createBrowserSupabase();
    }
    return supabaseClient;
}

/**
 * Creates an authenticated Supabase client for server-side use.
 * Passes the user's JWT so RLS policies apply correctly.
 */
export function createSupabaseWithToken(accessToken: string) {
    return createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            global: { headers: { Authorization: `Bearer ${accessToken}` } },
            auth: { persistSession: false }
        }
    );
}

/**
 * Returns the current user's access token (client-side only).
 */
export async function getAccessToken(): Promise<string | null> {
    const { data: { session } } = await getSupabase().auth.getSession();
    return session?.access_token ?? null;
}
