import { beforeEach, describe, expect, it } from 'vitest';
import { checkRateLimit, resetRateLimitStore, RateLimitConfig } from './rateLimit';

const CONFIG: RateLimitConfig = { limit: 3, windowMs: 60_000 };

describe('checkRateLimit', () => {
  beforeEach(() => {
    resetRateLimitStore();
  });

  it('allows requests up to the limit then blocks', () => {
    const t0 = 1_000_000;
    expect(checkRateLimit('k', CONFIG, t0).allowed).toBe(true);
    expect(checkRateLimit('k', CONFIG, t0).allowed).toBe(true);
    expect(checkRateLimit('k', CONFIG, t0).allowed).toBe(true);
    const fourth = checkRateLimit('k', CONFIG, t0);
    expect(fourth.allowed).toBe(false);
    expect(fourth.remaining).toBe(0);
  });

  it('decrements remaining on each allowed request', () => {
    const t0 = 2_000_000;
    expect(checkRateLimit('k', CONFIG, t0).remaining).toBe(2);
    expect(checkRateLimit('k', CONFIG, t0).remaining).toBe(1);
    expect(checkRateLimit('k', CONFIG, t0).remaining).toBe(0);
  });

  it('resets after the window expires', () => {
    const t0 = 3_000_000;
    checkRateLimit('k', CONFIG, t0);
    checkRateLimit('k', CONFIG, t0);
    checkRateLimit('k', CONFIG, t0);
    expect(checkRateLimit('k', CONFIG, t0).allowed).toBe(false);

    // Just past the window — counter starts fresh.
    const after = checkRateLimit('k', CONFIG, t0 + CONFIG.windowMs + 1);
    expect(after.allowed).toBe(true);
    expect(after.remaining).toBe(CONFIG.limit - 1);
  });

  it('tracks separate keys independently', () => {
    const t0 = 4_000_000;
    checkRateLimit('user-a', CONFIG, t0);
    checkRateLimit('user-a', CONFIG, t0);
    checkRateLimit('user-a', CONFIG, t0);
    expect(checkRateLimit('user-a', CONFIG, t0).allowed).toBe(false);
    // A different key is unaffected.
    expect(checkRateLimit('user-b', CONFIG, t0).allowed).toBe(true);
  });

  it('reports a positive retry-after when blocked', () => {
    const t0 = 5_000_000;
    for (let i = 0; i < CONFIG.limit; i++) checkRateLimit('k', CONFIG, t0);
    const blocked = checkRateLimit('k', CONFIG, t0 + 10_000);
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfterSeconds).toBe(50); // (60000 - 10000) / 1000
  });
});
