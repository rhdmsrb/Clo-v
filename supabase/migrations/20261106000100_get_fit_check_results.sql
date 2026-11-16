-- Per-photo vote totals for a Fit-Check that has ended, so results stay visible
-- without exposing who voted. fit_check_votes' read policy is deliberately left
-- alone: non-creators still can't read vote rows once a post closes.
--
-- Security definer bypasses RLS, so this repeats the fit_checks read rule. Keep
-- the two in step. Posts the caller can't see return no rows rather than an
-- error, so the response doesn't reveal that a post exists.
--
-- Live posts also return no rows, so this can never spoil an open vote. A post
-- counts as closed from expires_at, because the expire-fit-checks job only flips
-- status every 5 minutes.

create or replace function public.get_fit_check_results(p_fit_check_id uuid)
returns table (photo_id uuid, vote_count integer, is_mine boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select v.photo_id,
         count(*)::integer,
         bool_or(v.voter_id = auth.uid())
    from public.fit_check_votes v
    join public.fit_checks f on f.id = v.fit_check_id
   where v.fit_check_id = p_fit_check_id
     and auth.uid() is not null
     and f.status <> 'draft'
     and (f.status <> 'live' or f.expires_at <= now())
     and (
       f.creator_id = auth.uid()
       or (
         not public.is_blocked_pair(f.creator_id)
         and (f.is_public or (f.group_id is not null and public.is_group_member(f.group_id)))
       )
     )
   group by v.photo_id;
$$;

revoke all on function public.get_fit_check_results(uuid) from public, anon;
grant execute on function public.get_fit_check_results(uuid) to authenticated;
