# CLO-V App Store readiness checklist

The first release hardening work is tracked through steps 1–9:

1. **Done.** Account deletion is available in Account and removes the Supabase account, profile data, and namespaced photos.
2. **Done.** Privacy & Data is visible in Account, with `PRIVACY.md` and `PrivacyInfo.xcprivacy` included in the app target.
3. **Done.** Users can report a Fit-Check and block its creator. Reports are stored in `content_reports` for moderation review.
4. **Done.** Blocked creators are removed from public and group feeds after refresh.
5. **Done.** Sign-in includes a password-reset flow using Supabase email recovery.
6. **Done.** Feed requests are sorted by `created_at` on the server and the client clamps each page to at most 50 rows.
7. **Done.** The synthetic `1 / 1` check is compiled only in Debug; Release has no debug login path.
8. **Ready in project.** The app target declares photo-library usage, a privacy manifest, and a 1024px App Store icon. Set the real Apple Developer Team ID before archiving.
9. Before submitting, complete App Store Connect metadata: privacy-policy URL, support URL, age rating, UGC moderation contact, App Privacy answers, screenshots, and a review account.

The remaining release tasks are external App Store Connect operations: publish the policy URL, provide a moderation contact and response process, configure Sign in with Apple if it is offered, set the Apple Developer Team ID, answer App Privacy questions, upload screenshots, and run the final device/archive review. The concrete handoff fields are listed in `APP_STORE_SUBMISSION.md`.
