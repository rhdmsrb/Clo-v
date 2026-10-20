import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const BUCKETS = ["avatars", "fit-check-photos", "wardrobe-items"];
const MAX_BATCHES = 1_000;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

// Collects every object path under `prefix`, descending into sub-folders.
// Folder entries come back from list() with a null id.
async function listAll(admin: SupabaseClient, bucket: string, prefix: string): Promise<string[]> {
  const paths: string[] = [];
  const pending = [prefix];
  let batches = 0;
  while (pending.length) {
    const folder = pending.pop()!;
    for (let offset = 0; ; offset += 1000) {
      if (++batches > MAX_BATCHES) throw new Error("too many storage entries");
      const { data, error } = await admin.storage.from(bucket).list(folder, { limit: 1000, offset });
      if (error) throw error;
      if (!data?.length) break;
      for (const entry of data) {
        if (entry.id === null) pending.push(`${folder}/${entry.name}`);
        else paths.push(`${folder}/${entry.name}`);
      }
      if (data.length < 1000) break;
    }
  }
  return paths;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ message: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization || !supabaseURL || !anonKey || !serviceKey) return json({ message: "Account deletion is not configured." }, 503);

  const userClient = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: userData, error: authError } = await userClient.auth.getUser(authorization.replace(/^Bearer\s+/i, ""));
  if (authError || !userData.user) return json({ message: "Please sign in again before deleting your account." }, 401);
  const userID = userData.user.id.toLowerCase();

  // delete_my_account refuses to run while the user still has files in
  // storage ("Account photos must be removed first"), so the files go first.
  // Doing it here with the service role is more reliable than from the app:
  // it no longer depends on the phone's connection staying up. If any bucket
  // fails to clear, stop before touching the account so the user can retry.
  const admin = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });
  for (const bucket of BUCKETS) {
    try {
      const paths = await listAll(admin, bucket, userID);
      for (let i = 0; i < paths.length; i += 100) {
        const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
        if (error) throw error;
      }
    } catch (error) {
      console.error("storage cleanup failed", bucket, userID, (error as Error).message);
      return json({ message: "Couldn't remove your photos. Please try again." }, 500);
    }
  }

  const { error: rpcError } = await userClient.rpc("delete_my_account");
  if (rpcError) {
    console.error("delete_my_account failed", rpcError.message);
    return json({ message: "Couldn't delete your account. Please try again." }, 500);
  }

  return json({ deleted: true });
});
