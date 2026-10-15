import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
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

    const providerResponse = await fetch("https://api.wearfits.com/api/v1/tryon/clothing", {
      method: "POST",
      headers: { "X-API-Key": wearfitsKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        personImages: [bodyPhoto],
        ...slots,
        options: { quality: "standard", preserveBackground: true },
      }),
    });
    const providerBody = await providerResponse.json().catch(() => ({}));
    if (!providerResponse.ok || providerBody.success === false) {
      const detail = providerBody?.error?.message;
      return json({ message: typeof detail === "string" ? detail : "The try-on provider couldn't process this photo or outfit." }, 502);
    }

    const jobID = providerBody.jobId;
    if (typeof jobID !== "string") return json({ message: "The try-on provider returned an invalid job." }, 502);
    const { error: saveError } = await admin.from("wardrobe_tryon_jobs").insert({ job_id: jobID, owner_id: userID });
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

    const providerResponse = await fetch(`https://api.wearfits.com/api/v1/jobs/${jobID}`, {
      headers: { "X-API-Key": wearfitsKey },
    });
    const providerBody = await providerResponse.json().catch(() => ({}));
    if (!providerResponse.ok) return json({ message: "Couldn't check the try-on yet. Please try again." }, 502);

    const status = providerBody.status ?? "processing";
    const imageURL = Array.isArray(providerBody.results) ? providerBody.results[0]?.url : undefined;
    const failed = status === "failed" || status === "error";
    if (failed) {
      const { error } = providerBody;
      const message = typeof error?.message === "string" ? error.message : "The try-on couldn't be generated.";
      return json({ jobId: jobID, status: "failed", message });
    }
    return json({ jobId: jobID, status, imageUrl: imageURL ?? null });
  }

  return json({ message: "Unknown request." }, 400);
});
