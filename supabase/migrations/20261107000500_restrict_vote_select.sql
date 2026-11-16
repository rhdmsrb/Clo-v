-- ============================================================================
-- APPLIED to the live project on 2026-11-16 with the user's explicit sign-off
-- (run with `supabase db query --linked -f`, then recorded with
-- `supabase migration repair --status applied 20261107000500`). Moved here from
-- supabase/pending/ afterwards.
-- ============================================================================
--
-- BREAKING for shipped app builds: they read fit_check_votes directly (feed
-- select embeds fit_check_votes(photo_id, voter_id); fetchFitCheckDetail and
-- vote-state queries filter fit_check_votes). After this, a viewer sees only
-- their own vote row; the creator sees all rows on their own posts. Old builds
-- will show wrong counts/percentages. Ship the app that uses get_live_vote_tally
-- / the vote-count embeds replacement first, and gate on a minimum app version.
--
-- Prerequisite: 20261107000400_get_live_vote_tally.sql applied.
-- Rollback: supabase/rollback/20261107000500_PHASE6_restrict_vote_select.sql

drop policy if exists "fit_check_votes: read (parent visible)" on public.fit_check_votes;
drop policy if exists "fit_check_votes: read own or creator" on public.fit_check_votes;

create policy "fit_check_votes: read own or creator" on public.fit_check_votes
  for select to authenticated
  using (
    voter_id = (select auth.uid())
    or exists (
      select 1 from public.fit_checks f
      where f.id = fit_check_votes.fit_check_id and f.creator_id = (select auth.uid())
    )
  );
