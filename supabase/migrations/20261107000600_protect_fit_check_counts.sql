-- Stop signed-in clients from writing fit_checks.like_count / vote_count directly.
--
-- Why: the policy "fit_checks: update own" (creator_id = auth.uid(), no column limit)
-- plus any UPDATE privilege on fit_checks lets a creator PATCH their own counters.
-- The baseline grants show no UPDATE for authenticated, but live grants may differ,
-- so the policy and grants are not relied on.
--
-- Mechanism: BEFORE UPDATE trigger that restores the old like_count/vote_count when
-- the statement runs AS a client role (current_user = anon or authenticated). The
-- legitimate writers are bump_vote_count() and bump_like_count(): AFTER triggers on
-- fit_check_votes / fit_check_likes that are SECURITY DEFINER (owner postgres), so
-- current_user is not a client role inside them and they pass through untouched.
-- Admin/service_role updates and other DEFINER RPCs (publish etc.) also pass through.
-- SECURITY INVOKER is deliberate: current_user must be the caller, not the owner.
-- Unlike an error, an ignored write keeps the rest of an UPDATE (e.g. caption) working.
--
-- Additive: no table, column, policy or grant is changed. comment_count is NOT covered
-- (out of scope; add it to the trigger if wanted). Other columns (status, expires_at)
-- remain writable by the creator if UPDATE is granted: review separately.
--
-- Rollback: supabase/rollback/20261107000600_protect_fit_check_counts.sql
-- (drop the trigger before the function; idempotent)

create or replace function public.protect_fit_check_counts()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    new.like_count := old.like_count;
    new.vote_count := old.vote_count;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_fit_check_counts() from public, anon, authenticated;

drop trigger if exists trg_fit_checks_protect_counts on public.fit_checks;
create trigger trg_fit_checks_protect_counts
  before update on public.fit_checks
  for each row execute function public.protect_fit_check_counts();
