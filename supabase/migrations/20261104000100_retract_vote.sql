-- Let a voter retract (cancel) their own vote while voting is still open.
--
-- Before: the DELETE policy allowed removing a vote at any time, so a vote could be
-- withdrawn after the result was final. Now it requires a live, unexpired post.
-- Counts are already maintained by trg_bump_vote_count_delete.
--
-- Also removes the creator's "someone voted" notification when the vote is retracted;
-- otherwise vote -> cancel -> re-vote would leave stale or duplicate notifications.

drop policy if exists "fit_check_votes: delete own" on public.fit_check_votes;

create policy "fit_check_votes: delete own (live post)"
  on public.fit_check_votes
  for delete to authenticated
  using (
    voter_id = (select auth.uid())
    and exists (
      select 1 from public.fit_checks f
      where f.id = fit_check_votes.fit_check_id
        and f.status = 'live'
        and (f.expires_at is null or f.expires_at > now())
    )
  );

create or replace function public.remove_vote_notification()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.notifications
  where type = 'vote'
    and actor_id = old.voter_id
    and fit_check_id = old.fit_check_id;
  return old;
end;
$$;

revoke all on function public.remove_vote_notification() from public, anon, authenticated;

drop trigger if exists trg_remove_vote_notification on public.fit_check_votes;
create trigger trg_remove_vote_notification
  after delete on public.fit_check_votes
  for each row execute function public.remove_vote_notification();
