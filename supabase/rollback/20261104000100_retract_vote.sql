drop trigger if exists trg_remove_vote_notification on public.fit_check_votes;
drop function if exists public.remove_vote_notification();
drop policy if exists "fit_check_votes: delete own (live post)" on public.fit_check_votes;
create policy "fit_check_votes: delete own"
  on public.fit_check_votes for delete to authenticated
  using (voter_id = auth.uid());
