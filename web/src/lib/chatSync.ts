import { getSupabase } from './supabase';

export interface ChatMessage {
    id: string;
    file_id: string;
    user_id: string;
    role: 'user' | 'model';
    content: string;
    created_at?: string;
}

/**
 * Chat history'yi Supabase'den yükler
 */
export async function loadChatHistory(fileId: string): Promise<ChatMessage[]> {
    const supabase = getSupabase();

    const { data, error } = await supabase
        .from('chats')
        .select('*')
        .eq('file_id', fileId)
        .order('created_at', { ascending: true });

    if (error) {
        console.error('❌ Error loading chat history:', error);
        return [];
    }

    return data || [];
}

/**
 * Chat mesajını Supabase'e kaydeder
 */
export async function saveChatMessage(
    fileId: string,
    role: 'user' | 'model',
    content: string
): Promise<void> {
    const supabase = getSupabase();

    const { error } = await supabase
        .from('chats')
        .insert({
            file_id: fileId,
            role,
            content
            // user_id otomatik olarak RLS policy tarafından set ediliyor
        });

    if (error) {
        console.error('❌ Error saving chat message:', error);
        throw error;
    }
}

/**
 * Belirli bir dökümanın tüm chat geçmişini siler
 */
export async function clearChatHistory(fileId: string): Promise<void> {
    const supabase = getSupabase();

    const { error } = await supabase
        .from('chats')
        .delete()
        .eq('file_id', fileId);

    if (error) {
        console.error('❌ Error clearing chat history:', error);
        throw error;
    }
}
