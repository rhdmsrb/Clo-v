# CLO-V security review — 2026-10-13

Scope: iOS client, shared Supabase migrations, and the live `main` project. Severity reflects potential user impact before each fix. Live schema and bucket checks were read back after deployment.

| Severity | Finding | Status |
| --- | --- | --- |
| High | Account deletion removed `auth.users` but could leave the profile and dependent content because the profile foreign key had been dropped. It also deleted Storage metadata through SQL, leaving physical files behind. | Fixed for the updated iOS client and live database: Storage API removes files first, then the deletion RPC removes the profile and auth user in one transaction. The RPC rejects deletion if namespaced files remain. Migration `0029_account_deletion_integrity.sql` is live. |
| High | Blocking a user was enforced by client feed filtering, so direct API reads of visible posts and follow writes could bypass it. | Fixed in live RLS and `block_user()`. The fit-check read policy hides posts across a blocked pair, follow inserts check blocks, and blocking removes both follow directions. Migration `0034_enforce_blocks_in_database.sql` is live. |
| Medium | Exact email/phone contact lookup had no per-account rate limit, allowing account enumeration. | Limited to 20 searches per 10 minutes per account. The audit table stores caller and time, not the searched contact. Migration `0033_contact_lookup_rate_limit.sql` is live. |
| Medium | Storage buckets accepted any MIME type and files up to the project-wide 50 MB limit. | All three photo buckets now allow common raster image MIME types and cap each file at 10 MB. Set through the Supabase Storage dashboard and verified from `storage.buckets`. |
| Medium | A broad avatar Storage SELECT policy let signed-in users list all avatar object paths. | Replaced with an owner-folder SELECT policy in live migration `0035_avatar_listing_privacy.sql`. The bucket remains public for existing avatar URLs. |

## Remaining work, ordered by severity

1. **High — legacy retained data.** Three profiles have no matching `auth.users` row. Two own Fit-Checks and one owns a group. The restored foreign key is `NOT VALID` to preserve this data for review; do not validate it until those rows are reconciled. No legacy profile or content was deleted during this review.
2. **High — rollout dependency.** The database now refuses account deletion while namespaced Storage files remain. The updated iOS client handles this, but any older client that calls the RPC directly will get an error if the account has photos. Ship the updated client before relying on self-service deletion for existing installations.
3. **Medium — contact discovery consent.** Rate limiting slows enumeration, but exact email/phone lookup is still available to any signed-in account. Decide whether users should opt in to being discoverable by contact.
4. **Medium — aggregate abuse limits.** Per-file size limits do not cap the number of Storage objects per account. `feed_events` also permits unlimited inserts by the row owner. Add per-user quotas or retention before broad public release.
5. **Low — password protection.** Supabase Security Advisor reports leaked-password protection disabled. Supabase documents this feature as available on Pro and above; the project is currently Free. Most other Advisor warnings are intentionally callable authenticated `SECURITY DEFINER` RPCs or trigger functions and need individual review, not blanket revocation.

Live verification: private fit-check and wardrobe buckets; RLS enabled on key content tables; deletion RPC no longer issues SQL deletes against `storage.objects`; two owner delete policies present; profile FK restored with `ON DELETE CASCADE NOT VALID`; contact audit table has RLS and no client SELECT grant; block checks present in fit-check/follow policies; all three buckets have a 10,485,760-byte limit and the specified image MIME types.

The live Security Advisor showed zero errors and 28 warnings after a refresh. The iOS Debug device build completed with code signing disabled. Account deletion was not exercised on a real user because that would permanently remove their data.
