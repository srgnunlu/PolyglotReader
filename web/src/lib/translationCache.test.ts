import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
    normalizeSourceText,
    computeTranslationKey,
    translateTextCached,
    resetTranslationCacheForTests,
} from './translationCache';

interface MockClientOptions {
    row?: { translated_text: string } | null;
    selectError?: { message: string } | null;
    userId?: string | null;
}

// Minimal stand-in for the supabase-js query builder chains the cache uses:
// from().select().eq().maybeSingle(), from().update().eq(), from().upsert().
function createMockClient(options: MockClientOptions = {}) {
    const upsert = vi.fn().mockResolvedValue({ error: null });
    const updateEq = vi.fn().mockResolvedValue({ error: null });
    const update = vi.fn(() => ({ eq: updateEq }));
    const maybeSingle = vi.fn().mockResolvedValue({
        data: options.selectError ? null : options.row ?? null,
        error: options.selectError ?? null,
    });
    const select = vi.fn(() => ({ eq: vi.fn(() => ({ maybeSingle })) }));
    const from = vi.fn(() => ({ select, update, upsert }));
    const getSession = vi.fn().mockResolvedValue({
        data: {
            session: options.userId === null ? null : { user: { id: options.userId ?? 'user-1' } },
        },
    });

    const client = { from, auth: { getSession } } as unknown as SupabaseClient;
    return { client, from, upsert, update, maybeSingle };
}

describe('normalizeSourceText', () => {
    it('trims and collapses internal whitespace to single spaces', () => {
        expect(normalizeSourceText('  hello   world \n\t again ')).toBe('hello world again');
    });

    it('preserves casing (casing can change the translation)', () => {
        expect(normalizeSourceText('Hello World')).toBe('Hello World');
    });
});

describe('computeTranslationKey', () => {
    it('produces a 64-char hex SHA-256 digest', async () => {
        const key = await computeTranslationKey('hello', 'tr');
        expect(key).toMatch(/^[0-9a-f]{64}$/);
    });

    it('is identical for whitespace variants of the same text', async () => {
        const a = await computeTranslationKey('hello   world', 'tr');
        const b = await computeTranslationKey('  hello\nworld ', 'tr');
        expect(a).toBe(b);
    });

    it('differs by target language and by casing', async () => {
        const tr = await computeTranslationKey('hello', 'tr');
        const en = await computeTranslationKey('hello', 'en');
        const upper = await computeTranslationKey('Hello', 'tr');
        expect(tr).not.toBe(en);
        expect(tr).not.toBe(upper);
    });
});

describe('translateTextCached', () => {
    beforeEach(() => {
        resetTranslationCacheForTests();
        vi.spyOn(console, 'warn').mockImplementation(() => {});
    });

    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('returns empty string for whitespace-only input without translating', async () => {
        const translate = vi.fn();
        const result = await translateTextCached('   ', 'tr', { translate, getClient: () => null });
        expect(result).toBe('');
        expect(translate).not.toHaveBeenCalled();
    });

    it('translates on miss and serves repeats from memory', async () => {
        const translate = vi.fn().mockResolvedValue('merhaba');
        const deps = { translate, getClient: () => null };

        expect(await translateTextCached('hello', 'tr', deps)).toBe('merhaba');
        expect(await translateTextCached('  hello ', 'tr', deps)).toBe('merhaba');
        expect(translate).toHaveBeenCalledTimes(1);
        expect(translate).toHaveBeenCalledWith('hello', 'tr');
    });

    it('serves a Supabase hit without translating and fills memory', async () => {
        const { client, maybeSingle, update } = createMockClient({
            row: { translated_text: 'önbellekten' },
        });
        const translate = vi.fn();
        const deps = { translate, getClient: () => client };

        expect(await translateTextCached('cached text', 'tr', deps)).toBe('önbellekten');
        expect(translate).not.toHaveBeenCalled();
        // Recency bump fired against the remote row.
        expect(update).toHaveBeenCalledTimes(1);

        // Second call is a memory hit — no second remote lookup.
        expect(await translateTextCached('cached text', 'tr', deps)).toBe('önbellekten');
        expect(maybeSingle).toHaveBeenCalledTimes(1);
    });

    it('writes through to Supabase after translating (upsert on user_id+source_hash)', async () => {
        const { client, upsert } = createMockClient({ row: null });
        const translate = vi.fn().mockResolvedValue('merhaba dünya');

        await translateTextCached('hello  world', 'tr', { translate, getClient: () => client });

        await vi.waitFor(() => expect(upsert).toHaveBeenCalledTimes(1));
        const expectedKey = await computeTranslationKey('hello world', 'tr');
        const [payload, conflict] = upsert.mock.calls[0];
        expect(payload).toMatchObject({
            user_id: 'user-1',
            source_hash: expectedKey,
            source_text: 'hello world',
            translated_text: 'merhaba dünya',
            target_lang: 'tr',
        });
        expect(conflict).toEqual({ onConflict: 'user_id,source_hash' });
    });

    it('skips the remote write when there is no session', async () => {
        const { client, upsert } = createMockClient({ row: null, userId: null });
        const translate = vi.fn().mockResolvedValue('merhaba');

        await translateTextCached('hello', 'tr', { translate, getClient: () => client });

        // Flush the fire-and-forget path before asserting the negative.
        await new Promise(resolve => setTimeout(resolve, 0));
        expect(upsert).not.toHaveBeenCalled();
    });

    it('degrades to a plain miss when the Supabase lookup errors, warning once', async () => {
        const { client } = createMockClient({ selectError: { message: 'relation does not exist' } });
        const translate = vi.fn().mockResolvedValue('merhaba');
        const deps = { translate, getClient: () => client };

        expect(await translateTextCached('first text', 'tr', deps)).toBe('merhaba');
        expect(await translateTextCached('second text', 'tr', deps)).toBe('merhaba');
        expect(translate).toHaveBeenCalledTimes(2);
        expect(console.warn).toHaveBeenCalledTimes(1);
    });

    it('still translates when obtaining the client throws', async () => {
        const translate = vi.fn().mockResolvedValue('merhaba');
        const deps = {
            translate,
            getClient: () => {
                throw new Error('no client');
            },
        };

        expect(await translateTextCached('hello', 'tr', deps)).toBe('merhaba');
        expect(console.warn).toHaveBeenCalledTimes(1);
    });

    it('evicts the least recently used entry once the memory cap is exceeded', async () => {
        const translate = vi.fn().mockImplementation(async (text: string) => `tr:${text}`);
        const deps = { translate, getClient: () => null };

        // Fill the cache to its cap of 200 entries.
        for (let i = 0; i < 200; i++) {
            await translateTextCached(`entry ${i}`, 'tr', deps);
        }
        expect(translate).toHaveBeenCalledTimes(200);

        // Touch entry 0 so it becomes most-recently-used, then overflow.
        await translateTextCached('entry 0', 'tr', deps);
        expect(translate).toHaveBeenCalledTimes(200);
        await translateTextCached('entry 200', 'tr', deps);
        expect(translate).toHaveBeenCalledTimes(201);

        // entry 0 survived the eviction; entry 1 was the LRU and got dropped.
        await translateTextCached('entry 0', 'tr', deps);
        expect(translate).toHaveBeenCalledTimes(201);
        await translateTextCached('entry 1', 'tr', deps);
        expect(translate).toHaveBeenCalledTimes(202);
    });
});
