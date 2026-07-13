import type { ChatMessage } from '@/types/models';

export const PAGE_LINK_PREFIX = '#corio-page-';

/** Normalizes a composer draft and supplies a useful prompt for image-only sends. */
export function normalizeChatDraft(text: string, hasAttachment: boolean): string | null {
  const trimmed = text.trim();
  if (trimmed) return trimmed;
  return hasAttachment ? 'Bu görseli analiz et.' : null;
}

/** Turns plain page mentions into the internal links handled by the PDF reader. */
export function linkifyPageCitations(text: string): string {
  return text
    .replace(/\[Sayfa (\d{1,4})\](?!\()/gi, `[Sayfa $1](${PAGE_LINK_PREFIX}$1)`)
    .replace(/(?<![[\w])(Sayfa) (\d{1,4})/gi, `[$1 $2](${PAGE_LINK_PREFIX}$2)`);
}

/** Creates a portable Markdown transcript from durable conversation turns. */
export function formatChatTranscript(messages: ChatMessage[], title: string): string {
  const turns = messages
    .filter(message => message.text.trim() && message.status !== 'error' && message.status !== 'streaming')
    .map(message => `**${message.role === 'user' ? 'Sen' : 'Corio AI'}**\n\n${message.text.trim()}`)
    .join('\n\n---\n\n');

  return `# ${title}\n\n${turns}${turns ? '\n' : ''}`;
}
