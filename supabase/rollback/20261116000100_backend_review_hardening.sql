-- Rollback for 20261116000100_backend_review_hardening.sql.
-- Restores the pre-review definitions (search_path=public, unqualified names) and the
-- default EXECUTE grants, then drops the indexes.

drop index if exists public.fit_checks_creator_created_idx;
drop index if exists public.fit_check_votes_voter_created_idx;
drop index if exists public.fit_check_comments_commenter_created_idx;

create or replace function public.bump_vote_count()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update fit_checks set vote_count = vote_count + 1 where id = new.fit_check_id;
    return new;
  elsif tg_op = 'DELETE' then
    update fit_checks set vote_count = vote_count - 1 where id = old.fit_check_id;
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.bump_comment_count()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update fit_checks set comment_count = comment_count + 1 where id = new.fit_check_id;
    return new;
  elsif tg_op = 'DELETE' then
    update fit_checks set comment_count = comment_count - 1 where id = old.fit_check_id;
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.notify_on_vote()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id)
  select f.creator_id, new.voter_id, 'vote', new.fit_check_id, new.photo_id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.voter_id;
  return new;
end;
$$;

create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id, comment_id)
  select f.creator_id, new.commenter_id, 'comment', new.fit_check_id, new.photo_id, new.id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.commenter_id;
  return new;
end;
$$;

create or replace function public.touch_wardrobe_item()
returns trigger language plpgsql set search_path = public
as $$ begin new.updated_at=now(); return new; end; $$;

grant execute on function public.bump_vote_count() to public, anon, authenticated;
grant execute on function public.bump_comment_count() to public, anon, authenticated;
grant execute on function public.notify_on_vote() to public, anon, authenticated;
grant execute on function public.notify_on_comment() to public, anon, authenticated;
grant execute on function public.touch_wardrobe_item() to public, anon, authenticated;
grant execute on function public.sync_fit_check_audience() to public, anon, authenticated;
grant execute on function public.device_tokens_enforce_cap() to public, anon, authenticated;
