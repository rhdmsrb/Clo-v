-- Lets a signed-in user remove one of their own blocks. `authenticated` has no
-- DELETE grant on blocked_users, so this goes through a definer RPC (same
-- style as block_user). Idempotent: unblocking someone not blocked is a no-op.

create or replace function public.unblock_user(p_blocked_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or p_blocked_id is null then
    raise exception 'Invalid user' using errcode = '22023';
  end if;
  delete from public.blocked_users
   where blocker_id = auth.uid() and blocked_id = p_blocked_id;
end;
$$;

revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function public.unblock_user(uuid) to authenticated;
