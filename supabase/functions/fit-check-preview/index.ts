import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Public, read-only preview of one shared Fit-Check, for people who open a
// share link without being signed in. Deploy with --no-verify-jwt.
//
// The service role bypasses RLS, so every visibility rule is enforced here:
// only public, live, unexpired Fit-Checks are returned, and only a minimal
// set of fields. The JSON carries no user ids or voter/commenter details, but
// the signed photo URLs embed the creator id in their path
// (/<creatorId>/<fitCheckId>/<file>), so viewers can link posts by author.
// Blocks are intentionally not applied to a public link.
//
// Abuse: this endpoint is public and shares the project's function quota, so it
// is rate limited per client IP (reserve_preview_hit, migration 20261116000200).
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
// Short lifetime: an already issued URL outlives a take-down or expiry.
const PHOTO_URL_TTL_SECONDS = 15 * 60;
const MAX_PHOTOS = 4;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PHOTO_BUCKET = "fit-check-photos";
// One constant for every "not shown" case, so missing, private, draft and
// expired posts are indistinguishable to the caller.
const UNAVAILABLE_BODY = { message: "This post isn't available." };

const json = (body: unknown, status = 200, extraHeaders: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extraHeaders },
  });

// Photo paths are "<creatorId>/<fitCheckId>/<file>.jpg". Refuse anything else
// so a bad row can never make the service role sign an unrelated object.
const isFitCheckPhotoPath = (path: unknown, creatorId: string, fitCheckId: string): path is string =>
  typeof path === "string" &&
  path.toLowerCase().startsWith(`${creatorId.toLowerCase()}/${fitCheckId.toLowerCase()}/`) &&
  !path.includes("..") && !path.includes("://") && !path.includes("\\") && !path.includes("?");

// Per-IP budget for this public endpoint. A shared link opens a handful of requests,
// so this is generous for people and still caps a script.
const RATE_LIMIT_MAX = 60;
const RATE_LIMIT_WINDOW_SECONDS = 60;

// cf-connecting-ip is set by the edge and cannot be forged by the caller; the first
// x-forwarded-for entry is the fallback.
function clientAddress(request: Request): string {
  return request.headers.get("cf-connecting-ip")?.trim() ||
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    "unknown";
}

// Only a hash of the address is stored. Fails open: a limiter outage must not take
// share links down, so an RPC error is logged and the request is allowed.
async function withinRateLimit(admin: SupabaseClient, request: Request): Promise<boolean> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(clientAddress(request)));
  const key = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const { data, error } = await admin.rpc("reserve_preview_hit", {
    p_key: key, p_max: RATE_LIMIT_MAX, p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
  });
  if (error) {
    console.error("fit-check-preview rate limit check failed", error.message);
    return true;
  }
  return data === true;
}

async function readFitCheckId(request: Request): Promise<string | null> {
  if (request.method === "GET") return new URL(request.url).searchParams.get("id");
  try {
    const body = await request.json();
    return typeof body?.id === "string" ? body.id : null;
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "GET" && request.method !== "POST") return json({ message: "Method not allowed" }, 405);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceKey) return json({ message: "Preview service is not configured." }, 503);

  const admin = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  // Throttle before any lookup or storage signing, so abusive traffic stays cheap.
  if (!(await withinRateLimit(admin, request))) {
    return json({ message: "Too many requests. Please try again in a minute." }, 429,
      { "Retry-After": String(RATE_LIMIT_WINDOW_SECONDS) });
  }

  const fitCheckId = await readFitCheckId(request);
  if (!fitCheckId || !UUID_PATTERN.test(fitCheckId)) return json({ message: "Invalid link." }, 400);

  const { data: row, error } = await admin.from("fit_checks")
    .select("id, creator_id, caption, occasion, expires_at, is_public, status, " +
      "vote_count, comment_count, fit_check_photos(image_url, position), profiles(nickname)")
    .eq("id", fitCheckId.toLowerCase())
    .maybeSingle();
  if (error) {
    console.error("fit-check-preview lookup failed", error.message);
    return json({ message: "Couldn't load this post. Please try again." }, 500);
  }

  // One response for missing, private, draft and expired posts, so the link
  // does not reveal which of them exists.
  const expired = row?.expires_at ? new Date(row.expires_at).getTime() <= Date.now() : false;
  if (!row || row.is_public !== true || row.status !== "live" || expired) {
    return json(UNAVAILABLE_BODY, 404);
  }

  const photoRows = (row.fit_check_photos ?? [])
    .filter((photo: { image_url: unknown }) => isFitCheckPhotoPath(photo.image_url, row.creator_id, row.id))
    .sort((a: { position: number }, b: { position: number }) => a.position - b.position)
    .slice(0, MAX_PHOTOS);

  const photos: { position: number; url: string }[] = [];
  for (const photo of photoRows) {
    const { data: signed, error: signError } = await admin.storage.from(PHOTO_BUCKET)
      .createSignedUrl(photo.image_url, PHOTO_URL_TTL_SECONDS);
    if (signError) console.error("fit-check-preview sign failed", row.id, signError.message);
    if (signed?.signedUrl) photos.push({ position: photo.position, url: signed.signedUrl });
  }
  if (photos.length === 0) return json(UNAVAILABLE_BODY, 404);

  return json({
    id: row.id,
    caption: row.caption ?? null,
    occasion: row.occasion ?? null,
    expiresAt: row.expires_at ?? null,
    authorNickname: row.profiles?.nickname ?? null,
    voteCount: row.vote_count ?? 0,
    commentCount: row.comment_count ?? 0,
    photos,
  }, 200, { "Cache-Control": "public, max-age=60" });
});
