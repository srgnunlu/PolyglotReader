import type { ChatMessage } from '@/types/models';
import type { ChatHistoryMessage } from '@/lib/gemini';

/**
 * Converts completed user/model pairs into context for the next question.
 * A stopped or failed answer also removes its pending user turn so the model
 * never receives malformed history with two consecutive user roles.
 */
export function toChatHistory(messages: ChatMessage[]): ChatHistoryMessage[] {
    const history: ChatHistoryMessage[] = [];
    let pendingUser: ChatHistoryMessage | null = null;

    for (const message of messages) {
        const isDurable = message.text.trim().length > 0
            && message.status !== 'streaming'
            && message.status !== 'stopped'
            && message.status !== 'error';

        if (!isDurable) {
            // A transient assistant message belongs to the pending user turn.
            // Drop that user turn too, otherwise the next request would send
            // two consecutive user roles to Gemini history.
            if (message.role === 'model') pendingUser = null;
            continue;
        }

        if (message.role === 'user') {
            pendingUser = { role: 'user', text: message.text };
            continue;
        }

        if (pendingUser) {
            history.push(pendingUser, { role: 'model', text: message.text });
            pendingUser = null;
        }
    }

    return history;
}
