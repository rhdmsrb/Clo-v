import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://exbozksjwpyvstqhcyqy.supabase.co",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const MAX_TRYONS_PER_HOUR = 10;
const TRYON_WINDOW_SECONDS = 60 * 60;
const STATUS_MIN_INTERVAL_SECONDS = 2;
// Wardrobe photos live at "<ownerId>/<itemId>/<file>.jpg" in a private bucket.
// image_url is owner-writable, so never sign anything outside the caller's folder.
const isOwnedStoragePath = (path: unknown, ownerID: string): path is string =>
  typeof path === "string" &&
  path.toLowerCase().startsWith(`${ownerID.toLowerCase()}/`) &&
  !path.includes("..") && !path.includes("://") && !path.includes("\\") && !path.includes("?");
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ message: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const wearfitsKey = Deno.env.get("WEARFITS_API_KEY");
  if (!authorization || !supabaseURL || !anonKey || !serviceKey) return json({ message: "Try-on service is not configured." }, 503);
  if (!wearfitsKey) return json({ message: "Try-on service is not configured yet. Please try again later." }, 503);

  const authClient = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: userData, error: authError } = await authClient.auth.getUser(authorization.replace(/^Bearer\s+/i, ""));
  if (authError || !userData.user) return json({ message: "Please sign in again before trying this outfit." }, 401);
  const userID = userData.user.id;
  const admin = createClient(supabaseURL, serviceKey, { auth: { persistSession: false } });

  let payload: Record<string, unknown>;
  try { payload = await request.json(); } catch { return json({ message: "Invalid request." }, 400); }
  const action = payload.action;

  if (action === "submit") {
    const bodyPhoto = payload.bodyPhoto;
    const itemIDs = payload.itemIDs;
    if (typeof bodyPhoto !== "string" || !bodyPhoto.startsWith("data:image/jpeg;base64,")) {
      return json({ message: "Choose a full-body photo to create a try-on preview." }, 400);
    }
    if (bodyPhoto.length > 1_850_000) return json({ message: "That photo is too large. Choose a smaller image." }, 413);
    if (!Array.isArray(itemIDs) || itemIDs.length < 1 || itemIDs.length > 4 || itemIDs.some((id) => typeof id !== "string")) {
      return json({ message: "Choose one to four clothing pieces." }, 400);
    }

    const { data: items, error: itemError } = await admin.from("wardrobe_items")
      .select("id,image_url,category,owner_id")
      .eq("owner_id", userID)
      .in("id", itemIDs);
    if (itemError || !items || items.length !== itemIDs.length) return json({ message: "Some selected wardrobe pieces are no longer available." }, 400);

    if (items.some((item) => !isOwnedStoragePath(item.image_url, userID))) {
      return json({ message: "Some selected wardrobe pieces are no longer available." }, 400);
    }

    const accepted = new Set(["top", "outerwear", "bottom", "dress", "set", "shoes"]);
    if (items.some((item) => !accepted.has(item.category))) return json({ message: "Choose clothing pieces, not accessories." }, 400);
    const upper = items.filter((item) => ["top", "outerwear"].includes(item.category));
    const bottoms = items.filter((item) => item.category === "bottom");
    const onePieces = items.filter((item) => ["dress", "set"].includes(item.category));
    const shoes = items.filter((item) => item.category === "shoes");
    if (upper.length > 1 || bottoms.length > 1 || onePieces.length > 1 || shoes.length > 1 || (onePieces.length && (upper.length || bottoms.length))) {
      return json({ message: "Choose one item per clothing area, or a single dress/set." }, 400);
    }

    const slots: Record<string, string> = {};
    for (const item of items) {
      const { data: signed, error } = await admin.storage.from("wardrobe-items").createSignedUrl(item.image_url, 600);
      if (error || !signed?.signedUrl) return json({ message: "Couldn't prepare a selected clothing photo. Please try again." }, 502);
      const url = signed.signedUrl;
      if (item.category === "top" || item.category === "outerwear") slots.topGarment = url;
      else if (item.category === "bottom") slots.bottomGarment = url;
      else if (item.category === "dress" || item.category === "set") slots.fullBodyGarment = url;
      else if (item.category === "shoes") slots.shoes = url;
    }

    // Reserve the slot only once the request is valid, right before the paid provider
    // call: atomic per owner, and failed provider calls still count.
    const { data: reservationID, error: reserveError } = await admin.rpc("reserve_tryon_slot", {
      p_owner: userID, p_max: MAX_TRYONS_PER_HOUR, p_window_seconds: TRYON_WINDOW_SECONDS,
    });
    if (reserveError) return json({ message: "Couldn't start the try-on. Please try again." }, 500);
    if (!reservationID) {
      return json({ message: "You've reached the hourly try-on limit. Please try again later." }, 429);
    }

    const providerResponse = await fetch("https://api.wearfits.com/api/v1/tryon/clothing", {
      method: "POST",
      headers: { "X-API-Key": wearfitsKey, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(45_000),
      body: JSON.stringify({
        personImages: [bodyPhoto],
        ...slots,
        options: { quality: "standard", preserveBackground: true },
      }),
    });
    const providerBody = await providerResponse.json().catch(() => ({}));
    if (!providerResponse.ok || providerBody.success === false) {
      console.error("WEARFITS submit failed", providerResponse.status, providerBody?.error?.message);
      return json({ message: "The try-on couldn't process this photo or outfit. Try a different photo." }, 502);
    }

    const jobID = providerBody.jobId;
    if (typeof jobID !== "string") return json({ message: "The try-on provider returned an invalid job." }, 502);
    const { error: saveError } = await admin.from("wardrobe_tryon_jobs")
      .update({ job_id: jobID }).eq("job_id", reservationID).eq("owner_id", userID);
    if (saveError) return json({ message: "Couldn't save the try-on status. Please start again." }, 500);

    const imageURL = Array.isArray(providerBody.results) ? providerBody.results[0]?.url : undefined;
    return json({ jobId: jobID, status: imageURL ? "completed" : providerBody.status ?? "queued", imageUrl: imageURL ?? null });
  }

  if (action === "status") {
    const jobID = payload.jobID;
    if (typeof jobID !== "string" || !/^[0-9a-f-]{36}$/i.test(jobID)) return json({ message: "Invalid try-on job." }, 400);
    const { data: job } = await admin.from("wardrobe_tryon_jobs")
      .select("job_id").eq("job_id", jobID).eq("owner_id", userID).maybeSingle();
    if (!job) return json({ message: "Try-on job not found." }, 404);
    const { data: allowed, error: throttleError } = await admin.rpc("touch_tryon_poll", {
      p_job_id: jobID, p_owner: userID, p_min_interval_seconds: STATUS_MIN_INTERVAL_SECONDS,
    });
    if (throttleError) return json({ message: "Couldn't check the try-on yet. Please try again." }, 500);
    // Throttled polls answer "still processing" without calling the provider,
    // so the client keeps polling instead of surfacing an error.
    if (!allowed) return json({ jobId: jobID, status: "processing", imageUrl: null });

    const providerResponse = await fetch(`https://api.wearfits.com/api/v1/jobs/${jobID}`, {
      headers: { "X-API-Key": wearfitsKey },
      signal: AbortSignal.timeout(20_000),
    });
    const providerBody = await providerResponse.json().catch(() => ({}));
    if (!providerResponse.ok) return json({ message: "Couldn't check the try-on yet. Please try again." }, 502);

    const status = providerBody.status ?? "processing";
    const imageURL = Array.isArray(providerBody.results) ? providerBody.results[0]?.url : undefined;
    const failed = status === "failed" || status === "error";
    if (failed) {
      console.error("WEARFITS job failed", jobID, providerBody?.error?.message);
      return json({ jobId: jobID, status: "failed", message: "The try-on couldn't be generated. Try a different photo." });
    }
    return json({ jobId: jobID, status, imageUrl: imageURL ?? null });
  }

  return json({ message: "Unknown request." }, 400);
});
