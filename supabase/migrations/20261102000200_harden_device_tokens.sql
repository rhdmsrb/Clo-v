-- Hardening for device tokens: platform allow-list and a per-user cap.
-- Existing rows are not re-checked (NOT VALID); new writes are.
alter table public.device_tokens
    drop constraint if exists device_tokens_platform_check;
alter table public.device_tokens
    add constraint device_tokens_platform_check check (platform = 'ios') not valid;

-- Keep at most 20 tokens per user by dropping the stalest ones on insert, so a
-- user with stale devices is never locked out. Covers direct inserts and the RPC.
create or replace function public.device_tokens_enforce_cap()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    delete from public.device_tokens
     where token in (
        select token from public.device_tokens
         where user_id = new.user_id and token <> new.token
         order by updated_at desc
         offset 19
     );
    return new;
end;
$$;

drop trigger if exists device_tokens_cap on public.device_tokens;
create trigger device_tokens_cap
    before insert on public.device_tokens
    for each row execute function public.device_tokens_enforce_cap();

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
  if coalesce(p_platform, 'ios') <> 'ios' then
    raise exception 'invalid platform' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), 'ios', now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
