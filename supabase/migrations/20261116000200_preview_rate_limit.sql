-- Rate limit for the public fit-check-preview Edge Function (no JWT, service role).
-- Fixed-window counter per caller key (a hash of the client IP, never the raw address):
-- one atomic upsert per request, no lock. Callable by the service role only.
-- Additive. Rollback: supabase/rollback/20261116000200_preview_rate_limit.sql

create table if not exists public.preview_rate_limits (
    client_key   text        not null,
    window_start timestamptz not null,
    hits         integer     not null default 0,
    primary key (client_key, window_start)
);

alter table public.preview_rate_limits enable row level security;
revoke all on public.preview_rate_limits from public, anon, authenticated;
grant all on public.preview_rate_limits to service_role;

-- Returns true while the caller is within p_max requests for the current window.
create or replace function public.reserve_preview_hit(
    p_key text, p_max integer, p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_window timestamptz;
    v_hits integer;
begin
    if p_key is null or char_length(p_key) not between 1 and 128
       or p_max is null or p_max < 1
       or p_window_seconds is null or p_window_seconds not between 1 and 3600 then
        raise exception 'Invalid rate limit arguments' using errcode = '22023';
    end if;
    v_window := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

    insert into public.preview_rate_limits as r (client_key, window_start, hits)
    values (p_key, v_window, 1)
    on conflict (client_key, window_start) do update set hits = r.hits + 1
    returning r.hits into v_hits;

    -- Occasional cleanup keeps the table small without a scheduled job.
    if random() < 0.02 then
        delete from public.preview_rate_limits where window_start < now() - interval '2 hours';
    end if;

    return v_hits <= p_max;
end;
$$;

revoke all on function public.reserve_preview_hit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.reserve_preview_hit(text, integer, integer) to service_role;
