// OAuth PKCE callback — exchanges the auth `code` for a session cookie on the
// SERVER, then redirects into the app. This is the canonical @supabase/ssr flow.
//
// The previous implementation was a client `page.tsx` that only called
// getSession(); in the cookie-based SSR model that does not reliably complete
// the PKCE exchange, so the server proxy never saw a session and Google login
// broke. Doing the exchange here writes the auth cookies the proxy reads.
import { NextResponse } from 'next/server';
import { createServerSupabase } from '@/lib/supabase-server';

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get('code');
  const oauthError = searchParams.get('error');

  // Where to send the user after a successful login (defaults to the library).
  let next = searchParams.get('next') ?? '/library';
  if (!next.startsWith('/')) next = '/library';

  // Provider returned an error (e.g. the user cancelled the consent screen).
  if (oauthError) {
    return NextResponse.redirect(`${origin}/login?error=oauth`);
  }

  if (code) {
    try {
      const supabase = await createServerSupabase();
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (!error) {
        // Honour the original host when behind Render's load balancer.
        const forwardedHost = request.headers.get('x-forwarded-host');
        const isLocalEnv = process.env.NODE_ENV === 'development';
        if (!isLocalEnv && forwardedHost) {
          return NextResponse.redirect(`https://${forwardedHost}${next}`);
        }
        return NextResponse.redirect(`${origin}${next}`);
      }
    } catch {
      // Fall through to the error redirect below.
    }
  }

  // No code, or the exchange failed — return the user to the login screen.
  return NextResponse.redirect(`${origin}/login?error=auth`);
}
