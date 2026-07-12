import { describe, expect, it } from 'vitest';
import { toChatHistory } from './chatHistory';

describe('toChatHistory', () => {
    it('keeps the most recent completed question and answer in model context', () => {
        const messages = [
            { id: '1', role: 'user' as const, text: 'İlk soru', timestamp: new Date() },
            { id: '2', role: 'model' as const, text: 'İlk cevap', timestamp: new Date() },
            { id: '3', role: 'user' as const, text: 'Son soru', timestamp: new Date() },
            { id: '4', role: 'model' as const, text: 'Son cevap', timestamp: new Date() },
        ];

        expect(toChatHistory(messages)).toEqual([
            { role: 'user', text: 'İlk soru' },
            { role: 'model', text: 'İlk cevap' },
            { role: 'user', text: 'Son soru' },
            { role: 'model', text: 'Son cevap' },
        ]);
    });

    it('returns an empty context for a new conversation', () => {
        expect(toChatHistory([])).toEqual([]);
    });
});
