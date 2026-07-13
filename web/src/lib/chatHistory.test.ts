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

    it('omits streaming, stopped, empty, and error messages from model context', () => {
        const messages = [
            { id: '1', role: 'user' as const, text: 'Geçerli soru', timestamp: new Date() },
            {
                id: '2', role: 'model' as const, text: 'Geçerli cevap', timestamp: new Date(),
                status: 'complete' as const,
            },
            {
                id: '3', role: 'model' as const, text: 'Yarım cevap', timestamp: new Date(),
                status: 'stopped' as const,
            },
            {
                id: '4', role: 'model' as const, text: '', timestamp: new Date(),
                status: 'streaming' as const,
            },
            {
                id: '5', role: 'model' as const, text: 'Hata', timestamp: new Date(),
                status: 'error' as const,
            },
        ];

        expect(toChatHistory(messages)).toEqual([
            { role: 'user', text: 'Geçerli soru' },
            { role: 'model', text: 'Geçerli cevap' },
        ]);
    });

    it('drops the unanswered user turn when its response was stopped', () => {
        const messages = [
            { id: '1', role: 'user' as const, text: 'Tamamlanan soru', timestamp: new Date() },
            { id: '2', role: 'model' as const, text: 'Tamamlanan cevap', timestamp: new Date() },
            { id: '3', role: 'user' as const, text: 'Yarım kalan soru', timestamp: new Date() },
            {
                id: '4', role: 'model' as const, text: 'Yarım cevap', timestamp: new Date(),
                status: 'stopped' as const,
            },
        ];

        expect(toChatHistory(messages)).toEqual([
            { role: 'user', text: 'Tamamlanan soru' },
            { role: 'model', text: 'Tamamlanan cevap' },
        ]);
    });
});
