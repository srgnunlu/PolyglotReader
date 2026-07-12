import Foundation
import PostgREST
import Supabase

// MARK: - Library Chat (file_id IS NULL)
// Kütüphane geneli sohbet dosyaya değil kullanıcıya aittir; aynı chats
// tablosunda file_id NULL satırlar olarak yaşar (migration 20260712100000).
// Ayrı dosya: ana sınıf type_body_length bütçesinde kalsın.

extension SupabaseDatabaseService {
    func saveLibraryChat(userId: String, role: String, content: String) async throws {
        struct LibraryChatInsert: Encodable {
            let user_id: String
            let role: String
            let content: String
        }

        try await client
            .from("chats")
            .insert(LibraryChatInsert(user_id: userId, role: role, content: content))
            .execute()
    }

    func getLibraryChats(userId: String) async throws -> [ChatMessage] {
        struct LibraryChatRecord: Decodable {
            let id: String
            let role: String
            let content: String
            let created_at: String
        }

        let records: [LibraryChatRecord] = try await client
            .from("chats")
            .select()
            .is("file_id", value: nil)
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .order("seq", ascending: true)
            .execute()
            .value

        return records.map { record in
            ChatMessage(
                id: record.id,
                role: mapRole(record.role),
                text: record.content,
                timestamp: DateFormatting.date(from: record.created_at)
            )
        }
    }

    func deleteLibraryChats(userId: String) async throws {
        try await client
            .from("chats")
            .delete()
            .is("file_id", value: nil)
            .eq("user_id", value: userId)
            .execute()
    }
}
