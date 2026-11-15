-- Phase 6 (part 1, safe to apply early): live per-photo tally for open posts,
-- returned only to someone entitled to see it.
--
-- Rows are returned only when the caller is the creator OR has already voted on
-- this post, and the post is visible to them (same rule as get_fit_check_results).
-- Anyone else gets zero rows, so an open vote cannot be spoiled before voting.
-- KEEP IN SYNC: the visibility rule (creator, or not blocked and public/group member)
-- copies the "fit_checks: read (published audience or owner)" policy; change both together.
-- Does not itself change who can read fit_check_votes; see
-- supabase/pending/20261107000500_PHASE6_restrict_vote_select.sql for that.
--
-- Rollback: supabase/rollback/20261107000400_get_live_vote_tally.sql

create or replace function public.get_live_vote_tally(p_fit_check_id uuid)
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
     and (
       f.creator_id = auth.uid()
       or (
         not public.is_blocked_pair(f.creator_id)
         and (f.is_public or (f.group_id is not null and public.is_group_member(f.group_id)))
         and exists (
           select 1 from public.fit_check_votes mine
            where mine.fit_check_id = p_fit_check_id and mine.voter_id = auth.uid()
         )
       )
     )
   group by v.photo_id;
$$;

revoke all on function public.get_live_vote_tally(uuid) from public, anon;
grant execute on function public.get_live_vote_tally(uuid) to authenticated;
