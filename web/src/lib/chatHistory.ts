import type { ChatMessage } from '@/types/models';
import type { ChatHistoryMessage } from '@/lib/gemini';

/**
 * Converts every completed UI message into the context sent with the next
 * question. The newly queued user/model placeholders are not part of the
 * captured React state yet, so trimming the last pair drops valid history.
 */
export function toChatHistory(messages: ChatMessage[]): ChatHistoryMessage[] {
    return messages.map(message => ({
        role: message.role,
        text: message.text,
    }));
}
