// Supabase Edge Function: delete-account
//
// Permanently deletes the calling user's account and all associated data.
// Required by App Store Review Guideline 5.1.1(v) for apps that create accounts.
//
// Flow:
//   1. Authenticate the caller from their JWT (Authorization: Bearer <token>).
//   2. Remove the user's objects from the `user_files` storage bucket.
//   3. Delete the auth user with the service-role key. Foreign keys with
//      ON DELETE CASCADE remove files, chats, annotations, document_chunks, etc.
//
// Env vars are injected automatically by the Edge runtime:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STORAGE_BUCKET = "user_files";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) {
      return json({ error: "Missing authorization token" }, 401);
    }

    // Identify the caller from their own JWT.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(
      token,
    );
    if (userError || !userData?.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }
    const userId = userData.user.id;

    // Service-role client for privileged cleanup.
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) Remove the user's storage objects (files are stored under <userId>/...).
    await deleteUserStorage(admin, userId);

    // 2) Delete the auth user; DB rows cascade via foreign keys.
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      return json({ error: `Failed to delete account: ${deleteError.message}` }, 500);
    }

    return json({ success: true }, 200);
  } catch (err) {
    return json({ error: `Unexpected error: ${String(err)}` }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function deleteUserStorage(admin: any, userId: string): Promise<void> {
  try {
    // Uploads use a lowercased user id as the folder prefix.
    const prefix = userId.toLowerCase();
    const { data: entries, error } = await admin.storage
      .from(STORAGE_BUCKET)
      .list(prefix, { limit: 1000 });
    if (error || !entries || entries.length === 0) return;

    // deno-lint-ignore no-explicit-any
    const paths = entries.map((e: any) => `${prefix}/${e.name}`);
    await admin.storage.from(STORAGE_BUCKET).remove(paths);
  } catch (_) {
    // Storage cleanup is best-effort; account deletion still proceeds.
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
