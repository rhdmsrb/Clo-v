-- Restores the baseline read policy (parent visible: creator, or live post).
drop policy if exists "fit_check_votes: read own or creator" on public.fit_check_votes;
create policy "fit_check_votes: read (parent visible)" on public.fit_check_votes
  for select to authenticated
  using (exists (
    select 1 from public.fit_checks f
    where f.id = fit_check_votes.fit_check_id
      and (f.creator_id = auth.uid()
           or (f.status = 'live' and (f.expires_at is null or f.expires_at > now())))
  ));
