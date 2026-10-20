-- A device token can move between accounts on the same phone. A plain upsert
-- from the client cannot do that: ON CONFLICT DO UPDATE needs the UPDATE policy
-- to pass for the *existing* row, which still belongs to the previous account
-- (e.g. when its sign-out cleanup failed offline). This RPC reassigns the token
-- to the caller, so the old account stops receiving this device's pushes.
create or replace function public.register_device_token(p_token text, p_platform text default 'ios')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_token is null or char_length(p_token) not between 1 and 512 then
    raise exception 'invalid device token' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'ios'), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
