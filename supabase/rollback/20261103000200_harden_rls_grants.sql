-- ROLLBACK for 20261103000200_harden_rls_grants.sql.
-- Live definitions captured 2026-11-03 before applying (state AFTER migration 20261103000100).
-- Run with: supabase db query --linked -f supabase/rollback/20261103000200_harden_rls_grants.sql

CREATE OR REPLACE FUNCTION public.bump_vote_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
grant execute on function public.bump_vote_count() to public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bump_comment_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
grant execute on function public.bump_comment_count() to public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_on_vote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id)
  select f.creator_id, new.voter_id, 'vote', new.fit_check_id, new.photo_id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.voter_id;
  return new;
end;
$function$;
grant execute on function public.notify_on_vote() to public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_on_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id, comment_id)
  select f.creator_id, new.commenter_id, 'comment', new.fit_check_id, new.photo_id, new.id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.commenter_id;
  return new;
end;
$function$;
grant execute on function public.notify_on_comment() to public, anon, authenticated;

create policy "fr_insert" on public.friend_requests for insert to authenticated with check ((requester_id = auth.uid()) AND (requester_id <> addressee_id));
grant insert, update, delete on public.friend_requests to anon, authenticated;
grant update on public.profiles to anon, authenticated;
alter table public.profiles drop constraint if exists profiles_nickname_format;
alter table public.profiles drop constraint if exists profiles_avatar_url_own_folder;
-- anon table privileges that existed before:
grant all on public.blocked_users to anon;
grant all on public.device_tokens to anon;
grant all on public.fit_check_comments to anon;
grant all on public.fit_check_photos to anon;
grant all on public.fit_check_votes to anon;
grant all on public.fit_checks to anon;
grant all on public.friend_requests to anon;
grant all on public.friendships to anon;
grant all on public.group_members to anon;
grant all on public.groups to anon;
grant all on public.notifications to anon;
