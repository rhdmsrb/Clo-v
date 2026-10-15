# Virtual try-on setup

The iOS flow and Supabase Edge Function are in the repository, but generated try-on will stay unavailable until the Supabase project is configured with a WEARFITS key.

1. Create a WEARFITS API key in the WEARFITS dashboard. Keep it server-side; do not add it to the iOS app or commit it.
2. Install and authenticate the Supabase CLI, then link this repo to the CLO-V Supabase project.
3. Apply database migrations with `supabase db push`.
4. Add the key as a Supabase Function secret: `supabase secrets set WEARFITS_API_KEY=...`.
5. Deploy the function: `supabase functions deploy wardrobe-try-on`.
6. In the app, select a full-body photo and clothing from the wardrobe, then tap **Try on**. The key is only used by the Edge Function.

The request sends the selected body photo as temporary base64 input and wardrobe photos using short-lived signed storage URLs. The job owner is checked before status is returned. The full-body input photo is not written to CLO-V storage. Provider-generated previews are displayed from the result URL and are not saved by CLO-V.

WEARFITS supports image-based clothing try-on (tops, bottoms, dresses/sets, and shoes) and an optional digital-twin API. This integration uses the image-based route, so it returns a still image and does not provide an interactive 3D avatar or guarantee garment sizing. See the [WEARFITS API docs](https://api.wearfits.com/doc) and [privacy policy](https://wearfits.com/privacy) before enabling it for users.
