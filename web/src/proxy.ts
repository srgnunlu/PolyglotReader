// Server-side auth boundary (Next.js 16 proxy — successor of middleware.ts).
// Refreshes the Supabase session cookie on every matched request and blocks
// unauthenticated access to app pages before any page code runs. This is
// defense-in-depth on top of client-side ProtectedRoute and database RLS.
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

const PROTECTED_PREFIXES = ['/library', '/reader', '/notes', '/settings'];

export async function proxy(request: NextRequest) {
    let response = NextResponse.next({ request });

    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
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
        }
    );

    // getUser() validates the token against Supabase and refreshes expired
    // sessions — required so API routes and server components stay logged in.
    const {
        data: { user },
    } = await supabase.auth.getUser();

    const { pathname } = request.nextUrl;
    const isProtected = PROTECTED_PREFIXES.some(prefix => pathname.startsWith(prefix));

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
