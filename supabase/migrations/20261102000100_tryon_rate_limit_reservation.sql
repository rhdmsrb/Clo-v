-- Try-on rate limiting that cannot be raced or bypassed.
-- reserve_tryon_slot: atomically (per owner) counts jobs in the window and, if
--   under the cap, inserts a placeholder row ('pending-<uuid>') that the Edge
--   Function later renames to the provider's job id. Rows are kept when the
--   provider call fails, so failed attempts count against the cap.
-- touch_tryon_poll: throttles status polls per job.
-- Both are callable by the service role only (the Edge Function).
alter table public.wardrobe_tryon_jobs
    add column if not exists last_polled_at timestamptz;

create or replace function public.reserve_tryon_slot(
    p_owner uuid, p_max integer, p_window_seconds integer
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_recent integer;
    v_id text;
begin
    perform pg_advisory_xact_lock(hashtextextended(p_owner::text, 0));
    -- Placeholders older than the window never reached a provider job id and
    -- no longer count; drop them so they do not accumulate.
    delete from public.wardrobe_tryon_jobs
     where owner_id = p_owner
       and job_id like 'pending-%'
       and created_at < now() - make_interval(secs => p_window_seconds);
    select count(*) into v_recent
      from public.wardrobe_tryon_jobs
     where owner_id = p_owner
       and created_at >= now() - make_interval(secs => p_window_seconds);
    if v_recent >= p_max then
        return null;
    end if;
    v_id := 'pending-' || gen_random_uuid()::text;
    insert into public.wardrobe_tryon_jobs (job_id, owner_id) values (v_id, p_owner);
    return v_id;
end;
$$;

create or replace function public.touch_tryon_poll(
    p_job_id text, p_owner uuid, p_min_interval_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated integer;
begin
    update public.wardrobe_tryon_jobs
       set last_polled_at = now()
     where job_id = p_job_id
       and owner_id = p_owner
       and (last_polled_at is null
            or last_polled_at <= now() - make_interval(secs => p_min_interval_seconds));
    get diagnostics v_updated = row_count;
    return v_updated = 1;
end;
$$;

revoke all on function public.reserve_tryon_slot(uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.touch_tryon_poll(text, uuid, integer) from public, anon, authenticated;
grant execute on function public.reserve_tryon_slot(uuid, integer, integer) to service_role;
grant execute on function public.touch_tryon_poll(text, uuid, integer) to service_role;
