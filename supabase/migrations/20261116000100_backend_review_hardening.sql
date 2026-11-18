-- Backend review (2026-11-16). Completes part 1 of 20261103000200_harden_rls_grants.sql,
-- which the live database never received (the rest of that file did land), and adds
-- indexes for per-user lookups the app already makes.
--
-- 1. Trigger functions: five SECURITY DEFINER / invoker functions still run with
--    search_path=public and unqualified table names, and anon/authenticated hold EXECUTE.
--    Pin search_path to '', schema-qualify, and drop the grants. Triggers still fire:
--    Postgres checks EXECUTE only at CREATE TRIGGER time. Bodies are otherwise unchanged.
-- 2. Indexes for lookups by creator / voter / commenter (following feed, profile grid,
--    stale-draft sweep, weekly insights, vote RLS). Tables are small today; these keep
--    the queries index-backed as they grow.
--
-- Additive and idempotent. Rollback: supabase/rollback/20261116000100_backend_review_hardening.sql

create or replace function public.bump_vote_count()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.fit_checks set vote_count = vote_count + 1 where id = new.fit_check_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.fit_checks set vote_count = vote_count - 1 where id = old.fit_check_id;
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.bump_comment_count()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.fit_checks set comment_count = comment_count + 1 where id = new.fit_check_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.fit_checks set comment_count = comment_count - 1 where id = old.fit_check_id;
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.notify_on_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, fit_check_id, photo_id)
  select f.creator_id, new.voter_id, 'vote', new.fit_check_id, new.photo_id
  from public.fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.voter_id;
  return new;
end;
$$;

create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, fit_check_id, photo_id, comment_id)
  select f.creator_id, new.commenter_id, 'comment', new.fit_check_id, new.photo_id, new.id
  from public.fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.commenter_id;
  return new;
end;
$$;

create or replace function public.touch_wardrobe_item()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at = now(); return new; end; $$;

revoke all on function public.bump_vote_count() from public, anon, authenticated;
revoke all on function public.bump_comment_count() from public, anon, authenticated;
revoke all on function public.notify_on_vote() from public, anon, authenticated;
revoke all on function public.notify_on_comment() from public, anon, authenticated;
revoke all on function public.touch_wardrobe_item() from public, anon, authenticated;
-- Trigger-only functions whose bodies are already safe; only the grants change.
revoke all on function public.sync_fit_check_audience() from public, anon, authenticated;
revoke all on function public.device_tokens_enforce_cap() from public, anon, authenticated;

create index if not exists fit_checks_creator_created_idx
  on public.fit_checks (creator_id, created_at desc);
create index if not exists fit_check_votes_voter_created_idx
  on public.fit_check_votes (voter_id, created_at desc);
create index if not exists fit_check_comments_commenter_created_idx
  on public.fit_check_comments (commenter_id, created_at desc);
