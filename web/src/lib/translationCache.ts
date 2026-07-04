// Two-layer translation cache for the select-to-translate flow.
//
// Layer 1: in-memory LRU map — instant hits for selections repeated in this
//          session, capped so a long reading session can't grow it unbounded.
// Layer 2: Supabase `translation_cache` table — persists across sessions and
//          devices, keyed per user by a SHA-256 of the normalized selection.
//
// The Supabase layer is strictly best-effort: the migration may not be applied
// to the live database yet, the user may be offline, or RLS may reject the
// call. Any failure there degrades to a plain cache miss (or skipped write) so
// translation itself never breaks; we warn once instead of spamming the
// console.

import type { SupabaseClient } from '@supabase/supabase-js';
import { getSupabase } from './supabase';
import { translateText } from './gemini';

const MEMORY_CACHE_CAP = 200;

// Map iteration order is insertion order, so re-inserting on read makes the
// first key the least-recently-used one — a minimal LRU without extra state.
const memoryCache = new Map<string, string>();

let warnedRemoteCacheUnavailable = false;

function warnRemoteCacheOnce(error: unknown): void {
    if (warnedRemoteCacheUnavailable) return;
    warnedRemoteCacheUnavailable = true;
    console.warn(
        'Translation cache: Supabase layer unavailable, falling back to memory-only caching.',
        error
    );
}

/**
 * Collapses internal whitespace and trims so visually identical selections
 * (e.g. across line breaks in the PDF text layer) share one cache entry.
 * Casing is preserved on purpose — it can change the translation.
 */
export function normalizeSourceText(text: string): string {
    return text.trim().replace(/\s+/g, ' ');
}

/** SHA-256 hex digest of `${targetLang}::${normalized text}` via WebCrypto. */
export async function computeTranslationKey(text: string, targetLang: string): Promise<string> {
    const normalized = normalizeSourceText(text);
    const bytes = new TextEncoder().encode(`${targetLang}::${normalized}`);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(digest))
        .map(byte => byte.toString(16).padStart(2, '0'))
        .join('');
}

function memoryGet(key: string): string | undefined {
    const value = memoryCache.get(key);
    if (value === undefined) return undefined;
    // Refresh recency: move the entry to the end of the insertion order.
    memoryCache.delete(key);
    memoryCache.set(key, value);
    return value;
}

function memorySet(key: string, value: string): void {
    if (memoryCache.has(key)) memoryCache.delete(key);
    memoryCache.set(key, value);
    if (memoryCache.size > MEMORY_CACHE_CAP) {
        const oldestKey = memoryCache.keys().next().value;
        if (oldestKey !== undefined) memoryCache.delete(oldestKey);
    }
}

async function lookupRemote(client: SupabaseClient, sourceHash: string): Promise<string | null> {
    const { data, error } = await client
        .from('translation_cache')
        .select('translated_text')
        .eq('source_hash', sourceHash)
        .maybeSingle();

    if (error) {
        warnRemoteCacheOnce(error);
        return null;
    }
    if (!data) return null;

    // Recency bump is fire-and-forget: losing it never affects correctness.
    void client
        .from('translation_cache')
        .update({ last_used_at: new Date().toISOString() })
        .eq('source_hash', sourceHash)
        .then(
            () => undefined,
            () => undefined
        );

    return (data as { translated_text: string }).translated_text;
}

async function storeRemote(
    client: SupabaseClient,
    sourceHash: string,
    sourceText: string,
    translatedText: string,
    targetLang: string
): Promise<void> {
    // getSession reads locally (no network) — needed because the insert must
    // carry the user_id column that RLS checks against.
    const { data } = await client.auth.getSession();
    const userId = data.session?.user?.id;
    if (!userId) return;

    const { error } = await client.from('translation_cache').upsert(
        {
            user_id: userId,
            source_hash: sourceHash,
            source_text: sourceText,
            translated_text: translatedText,
            target_lang: targetLang,
            last_used_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,source_hash' }
    );
    if (error) warnRemoteCacheOnce(error);
}

// Injectable for tests — production callers use the defaults.
export interface TranslationCacheDeps {
    translate: (text: string, targetLang: string) => Promise<string>;
    getClient: () => SupabaseClient | null;
}

/**
 * Cached drop-in replacement for `translateText`:
 * memory hit → instant; else Supabase hit → fills memory; else translate via
 * Gemini and write through to both layers (Supabase write fire-and-forget).
 */
export async function translateTextCached(
    text: string,
    targetLang: string = 'tr',
    deps?: Partial<TranslationCacheDeps>
): Promise<string> {
    const translate = deps?.translate ?? translateText;
    const normalized = normalizeSourceText(text);
    if (!normalized) return '';

    const key = await computeTranslationKey(normalized, targetLang);

    const memoryHit = memoryGet(key);
    if (memoryHit !== undefined) return memoryHit;

    let client: SupabaseClient | null = null;
    try {
        client = deps?.getClient ? deps.getClient() : getSupabase();
    } catch (error) {
        warnRemoteCacheOnce(error);
    }

    if (client) {
        try {
            const remoteHit = await lookupRemote(client, key);
            if (remoteHit !== null) {
                memorySet(key, remoteHit);
                return remoteHit;
            }
        } catch (error) {
            warnRemoteCacheOnce(error);
        }
    }

    const translated = await translate(normalized, targetLang);
    memorySet(key, translated);

    if (client) {
        // Fire-and-forget write-through: the user already has their result.
        void storeRemote(client, key, normalized, translated, targetLang).catch(warnRemoteCacheOnce);
    }

    return translated;
}

/** Test-only: clears memory cache and the one-shot warning flag. */
export function resetTranslationCacheForTests(): void {
    memoryCache.clear();
    warnedRemoteCacheUnavailable = false;
}
