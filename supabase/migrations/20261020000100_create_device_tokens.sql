-- APNs device tokens, written by API.registerDeviceToken / removed by
-- API.unregisterDeviceToken. Idempotent: the live project may already have it.
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null default 'ios',
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_id_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Re-homing a token to a different account goes through the
-- register_device_token RPC (20261020000200); these policies only let a user
-- write rows they own.
drop policy if exists "device_tokens_insert_own" on public.device_tokens;
create policy "device_tokens_insert_own" on public.device_tokens
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "device_tokens_update_own" on public.device_tokens;
create policy "device_tokens_update_own" on public.device_tokens
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own" on public.device_tokens
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "device_tokens_delete_own" on public.device_tokens;
create policy "device_tokens_delete_own" on public.device_tokens
  for delete to authenticated using (user_id = auth.uid());
