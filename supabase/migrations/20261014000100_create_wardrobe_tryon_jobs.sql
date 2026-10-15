create table if not exists public.wardrobe_tryon_jobs (
    job_id text primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

alter table public.wardrobe_tryon_jobs enable row level security;

-- Only the Edge Function's service role can read/write job ownership. The
-- function verifies the caller's Supabase JWT before looking up a job.
revoke all on public.wardrobe_tryon_jobs from anon, authenticated;
grant all on public.wardrobe_tryon_jobs to service_role;

create index if not exists wardrobe_tryon_jobs_owner_created_idx
    on public.wardrobe_tryon_jobs (owner_id, created_at desc);
