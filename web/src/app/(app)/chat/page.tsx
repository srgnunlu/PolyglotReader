// Library-wide chat page — ask questions across the whole library
'use client';

import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { LibraryChat } from '@/components/chat/LibraryChat';

export default function LibraryChatPage() {
  return (
    <ProtectedRoute>
      <LibraryChat />
    </ProtectedRoute>
  );
}
