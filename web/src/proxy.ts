// Server-side auth boundary (Next.js 16 proxy — successor of middleware.ts).
// Refreshes the Supabase session cookie on every matched request and blocks
// unauthenticated access to app pages before any page code runs. This is
// defense-in-depth on top of client-side ProtectedRoute and database RLS.
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

const PROTECTED_PREFIXES = ['/library', '/reader', '/notes', '/settings'];

export async function proxy(request: NextRequest) {
    let response = NextResponse.next({ request });
    const { pathname } = request.nextUrl;
    const isProtected = PROTECTED_PREFIXES.some(prefix => pathname.startsWith(prefix));

    // Resolve the current user. This must never throw an unhandled error: a
    // missing env var (Supabase URL/key not set on the host) or an unreachable
    // Supabase project (e.g. a paused free-tier instance) would otherwise crash
    // the proxy and surface as a raw "Internal Server Error" 500 on every
    // matched route — including /login — locking users out entirely. Instead we
    // fail closed: treat the request as unauthenticated and let the rules below
    // redirect protected routes to /login while still serving /login itself.
    let user = null;
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (supabaseUrl && supabaseAnonKey) {
        try {
            const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
                cookies: {
                    getAll() {
                        return request.cookies.getAll();
                    },
                    setAll(cookiesToSet) {
                        cookiesToSet.forEach(({ name, value }) =>
                            request.cookies.set(name, value)
                        );
                        response = NextResponse.next({ request });
                        cookiesToSet.forEach(({ name, value, options }) =>
                            response.cookies.set(name, value, options)
                        );
                    },
                },
            });

            // getUser() validates the token against Supabase and refreshes
            // expired sessions — required so API routes and server components
            // stay logged in.
            ({
                data: { user },
            } = await supabase.auth.getUser());
        } catch (error) {
            console.error('[proxy] Supabase auth check failed:', error);
        }
    } else {
        console.error('[proxy] Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY');
    }

    if (!user && isProtected) {
        const url = request.nextUrl.clone();
        url.pathname = '/login';
        url.searchParams.set('next', pathname);
        return NextResponse.redirect(url);
    }

    if (user && pathname === '/login') {
        const url = request.nextUrl.clone();
        url.pathname = '/library';
        url.search = '';
        return NextResponse.redirect(url);
    }

    return response;
}

export const config = {
    // API routes verify auth themselves (getAuthenticatedUserId); pages are
    // gated here. The root landing page stays public.
    matcher: [
        '/library/:path*',
        '/reader/:path*',
        '/notes/:path*',
        '/settings/:path*',
        '/login',
    ],
};
