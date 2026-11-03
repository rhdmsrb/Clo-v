import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

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
// Abuse: this endpoint is public and shares the project's function quota, so
// put a rate limit (WAF/CDN) in front of it before relying on it at scale.
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

  const fitCheckId = await readFitCheckId(request);
  if (!fitCheckId || !UUID_PATTERN.test(fitCheckId)) return json({ message: "Invalid link." }, 400);

  const admin = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  const { data: row, error } = await admin.from("fit_checks")
    .select("id, creator_id, caption, occasion, expires_at, is_public, status, " +
      "fit_check_photos(image_url, position), profiles(nickname)")
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

  // Count with head queries instead of embedding every vote/comment row.
  const [votes, comments] = await Promise.all([
    admin.from("fit_check_votes").select("photo_id", { count: "exact", head: true }).eq("fit_check_id", row.id),
    admin.from("fit_check_comments").select("id", { count: "exact", head: true }).eq("fit_check_id", row.id),
  ]);
  if (votes.error || comments.error) {
    console.error("fit-check-preview count failed", row.id, votes.error?.message ?? comments.error?.message);
  }

  return json({
    id: row.id,
    caption: row.caption ?? null,
    occasion: row.occasion ?? null,
    expiresAt: row.expires_at ?? null,
    authorNickname: row.profiles?.nickname ?? null,
    voteCount: votes.count ?? 0,
    commentCount: comments.count ?? 0,
    photos,
  }, 200, { "Cache-Control": "public, max-age=60" });
});
