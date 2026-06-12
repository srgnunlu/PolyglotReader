# SQL Archive

Historical SQL scripts that were applied manually to the live Supabase project
(`tftmypxwgccdgvldhaya`) at various points. They are kept for reference only —
**do not re-run them blindly**; the live schema is the source of truth.

Planned follow-up: pull the live schema with `supabase db pull` and start a
numbered migration history under `supabase/migrations/`.

| File | Purpose |
|---|---|
| `professional_rag_migration.sql` | RAG setup: `document_chunks`, pgvector, hybrid search RPCs |
| `rag_migration.sql` | Earlier RAG migration (previously duplicated under `PolyglotReader/Services/`) |
| `folders_and_tags_migration.sql` | `folders`, `tags`, `file_tags` tables |
| `create_reading_progress.sql` | `reading_progress` table |
| `fix_database_issues.sql` | Misc schema fixes |
| `fix_folder_tag_rls.sql` | RLS fixes for folders/tags |
| `fix_log_issues.sql` | Fixes driven by app log errors |
| `fix_rpc_permissions.sql` | RPC grant/permission fixes |
