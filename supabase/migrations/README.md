# Migrations

This folder is **incomplete**. It only holds `20261014000100_create_wardrobe_tryon_jobs.sql`.

`SECURITY_REVIEW.md` (2026-10-13) records migrations applied to the live `main`
project that are not in the repo, so RLS, storage policies and the account
deletion / block / contact-lookup RPCs cannot be audited from source:

| Migration | Purpose |
| --- | --- |
| `0009_enable_rls.sql` | RLS and storage policies (referenced from `API.swift`) |
| `0029_account_deletion_integrity.sql` | Account deletion RPC, profile FK |
| `0033_contact_lookup_rate_limit.sql` | Contact lookup rate limit and audit table |
| `0034_enforce_blocks_in_database.sql` | Block enforcement in RLS and `block_user()` |
| `0035_avatar_listing_privacy.sql` | Owner-folder avatar SELECT policy |

Migrations `0001`-`0028` and any others applied from the dashboard are also not here.

## Recovering the live schema

Needs the Supabase CLI and the project's database password.

```bash
supabase link --project-ref exbozksjwpyvstqhcyqy
supabase migration list          # compare local vs remote history
supabase db pull                 # writes the remote schema as a new migration
```

Review the pulled SQL before committing it. Going forward, create every schema
change with `supabase migration new <name>` so the repo stays the source of truth.
