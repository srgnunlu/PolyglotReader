-- Ensure chats RLS is complete in every environment.
--
-- The repo only tracks a DELETE policy for chats (20260612192125); SELECT and
-- INSERT policies were created ad hoc outside migrations. Both clients rely
-- entirely on RLS for per-user isolation (queries filter by file_id only), so
-- a missing policy would either expose rows or break the feature. Guarded so
-- environments that already have dashboard-created policies are untouched.
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'chats' AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY chats_select_own ON public.chats
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'chats' AND cmd = 'INSERT'
    ) THEN
        CREATE POLICY chats_insert_own ON public.chats
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;
