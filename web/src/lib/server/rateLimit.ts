// Per-user rate limiting for the Gemini API routes. An authenticated user
// hammering /api/gemini/* can burn the shared Gemini quota and run up cost, so
// each route enforces a fixed-window request cap keyed by userId.
//
// This is an in-memory limiter: counters live in the module scope of a single
// server instance. On a multi-instance / serverless deployment the effective
// limit is per-instance, not strictly global — good enough as an abuse/cost
// guardrail. Swap in a shared store (e.g. Upstash Redis) if hard global limits
// are ever required.
import { NextResponse } from 'next/server';

interface Window {
  count: number;
  resetAt: number; // epoch ms when this window expires
}

export interface RateLimitConfig {
  limit: number; // max requests allowed within the window
  windowMs: number; // window length in milliseconds
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  limit: number;
  resetAt: number;
  retryAfterSeconds: number;
}

// key = `${routeKey}:${userId}` → its current window.
const windows = new Map<string, Window>();

// Drop expired windows opportunistically so the Map can't grow without bound
// from churn of one-off users. Cheap O(n) sweep, only when the Map gets large.
const CLEANUP_THRESHOLD = 5000;
function maybeCleanup(now: number): void {
  if (windows.size < CLEANUP_THRESHOLD) return;
  for (const [key, window] of windows) {
    if (window.resetAt <= now) windows.delete(key);
  }
}

/**
 * Records a request against `key` and reports whether it is allowed under
 * `config`. A new window starts on the first request and once the previous one
 * expires. `now` is injectable for deterministic tests.
 */
export function checkRateLimit(
  key: string,
  config: RateLimitConfig,
  now: number = Date.now()
): RateLimitResult {
  maybeCleanup(now);

  const existing = windows.get(key);
  if (!existing || existing.resetAt <= now) {
    const resetAt = now + config.windowMs;
    windows.set(key, { count: 1, resetAt });
    return {
      allowed: true,
      remaining: config.limit - 1,
      limit: config.limit,
      resetAt,
      retryAfterSeconds: 0,
    };
  }

  if (existing.count >= config.limit) {
    return {
      allowed: false,
      remaining: 0,
      limit: config.limit,
      resetAt: existing.resetAt,
      retryAfterSeconds: Math.max(1, Math.ceil((existing.resetAt - now) / 1000)),
    };
  }

  existing.count += 1;
  return {
    allowed: true,
    remaining: config.limit - existing.count,
    limit: config.limit,
    resetAt: existing.resetAt,
    retryAfterSeconds: 0,
  };
}

// Test-only hook to clear accumulated state between cases.
export function resetRateLimitStore(): void {
  windows.clear();
}

/**
 * Convenience wrapper for route handlers: enforces the limit for
 * (routeKey, userId) and returns a ready-to-send 429 NextResponse when the
 * caller is over the limit, or null when the request may proceed.
 */
export function enforceRateLimit(
  routeKey: string,
  userId: string,
  config: RateLimitConfig
): NextResponse | null {
  const result = checkRateLimit(`${routeKey}:${userId}`, config);
  if (result.allowed) return null;

  return NextResponse.json(
    { error: 'Çok fazla istek gönderildi. Lütfen biraz bekleyin.' },
    {
      status: 429,
      headers: {
        'Retry-After': String(result.retryAfterSeconds),
        'X-RateLimit-Limit': String(result.limit),
        'X-RateLimit-Remaining': String(result.remaining),
      },
    }
  );
}

// Sensible defaults per route. Embedding allows more headroom because a single
// chat turn can fan out into several embed calls (query expansion + search).
export const AI_GENERATE_LIMIT: RateLimitConfig = { limit: 30, windowMs: 60_000 };
export const AI_STREAM_LIMIT: RateLimitConfig = { limit: 30, windowMs: 60_000 };
export const AI_EMBED_LIMIT: RateLimitConfig = { limit: 60, windowMs: 60_000 };
// OCR sends full-page images to Gemini — far heavier per request than text
// prompts, and results are cached client-side, so keep this conservative.
export const AI_OCR_LIMIT: RateLimitConfig = { limit: 10, windowMs: 60_000 };
