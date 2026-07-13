import { describe, expect, it } from 'vitest';
import type { ChatMessage } from '@/types/models';
import {
  formatChatTranscript,
  linkifyPageCitations,
  normalizeChatDraft,
} from './chatPresentation';

function message(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 'message-id',
    role: 'model',
    text: 'Tamamlanmış yanıt',
    timestamp: new Date('2026-07-13T09:30:00Z'),
    ...overrides,
  };
}

describe('normalizeChatDraft', () => {
  it('trims a text message before submission', () => {
    expect(normalizeChatDraft('  Belgeyi özetle.\n', false)).toBe('Belgeyi özetle.');
  });

  it('uses an explicit prompt when an image is submitted without text', () => {
    expect(normalizeChatDraft('   ', true)).toBe('Bu görseli analiz et.');
  });

  it('rejects an empty submission without an attachment', () => {
    expect(normalizeChatDraft('\n  ', false)).toBeNull();
  });
});

describe('linkifyPageCitations', () => {
  it('turns plain Turkish page references into in-document links', () => {
    expect(linkifyPageCitations('Ayrıntılar Sayfa 12 üzerinde.')).toBe(
      'Ayrıntılar [Sayfa 12](#corio-page-12) üzerinde.',
    );
  });

  it('does not rewrite a citation that is already a markdown link', () => {
    const linked = '[Sayfa 8](https://example.com/source)';
    expect(linkifyPageCitations(linked)).toBe(linked);
  });
});

describe('formatChatTranscript', () => {
  it('exports completed turns while omitting transient error placeholders', () => {
    const transcript = formatChatTranscript(
      [
        message({ id: '1', role: 'user', text: 'Ana fikir ne?' }),
        message({ id: '2', text: 'Ana fikir öğrenmedir.', status: 'complete' }),
        message({ id: '3', text: 'Bir hata oluştu.', status: 'error' }),
      ],
      'Corio AI Sohbeti',
    );

    expect(transcript).toContain('Ana fikir ne?');
    expect(transcript).toContain('Ana fikir öğrenmedir.');
    expect(transcript).not.toContain('Bir hata oluştu.');
  });
});
