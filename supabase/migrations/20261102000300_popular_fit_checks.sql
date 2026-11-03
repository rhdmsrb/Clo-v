-- Popular public Fit-Checks for new users whose following/friends feed is empty.
-- Returns ids and a score; the app loads the rows with its normal feed query so
-- photo signing, vote prompts and block filtering stay in one place.
--
-- SECURITY INVOKER on purpose: the caller's RLS applies, so this can never
-- surface a post the caller could not already read. Blocked authors are also
-- excluded explicitly (blocked_users only exposes the caller's own rows).
create or replace function public.popular_fit_checks(
    p_limit integer default 20,
    p_offset integer default 0,
    p_window_days integer default 7
) returns table (id uuid, score bigint)
language sql
stable
security invoker
set search_path = ''
as $$
    -- vote_count / comment_count are maintained by live AFTER INSERT/DELETE
    -- triggers (bump_vote_count, bump_comment_count), so no per-row counting.
    select f.id,
           (f.vote_count + 2 * f.comment_count)::bigint as score
      from public.fit_checks f
     where f.is_public = true
       and f.status = 'live'
       and (f.expires_at is null or f.expires_at > now())
       and f.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_window_days, 7), 30)))
       and not exists (
             select 1 from public.blocked_users b where b.blocked_id = f.creator_id
           )
     order by score desc, f.created_at desc, f.id
     limit greatest(1, least(coalesce(p_limit, 20), 50))
     offset greatest(0, coalesce(p_offset, 0));
$$;

revoke all on function public.popular_fit_checks(integer, integer, integer) from public, anon;
grant execute on function public.popular_fit_checks(integer, integer, integer) to authenticated;
