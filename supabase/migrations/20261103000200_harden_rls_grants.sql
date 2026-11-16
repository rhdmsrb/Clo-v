-- Follow-up hardening from the live-catalog audit (2026-11-03). Written against the
-- live policies/grants/trigger bodies read from the Clo_V project.

-- 1. Trigger functions: pin search_path, schema-qualify every object, and remove the
-- default PUBLIC/anon/authenticated EXECUTE. Triggers still fire: Postgres checks EXECUTE
-- only when CREATE TRIGGER runs, not when the trigger fires.
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

revoke all on function public.bump_vote_count() from public, anon, authenticated;
revoke all on function public.bump_comment_count() from public, anon, authenticated;
revoke all on function public.notify_on_vote() from public, anon, authenticated;
revoke all on function public.notify_on_comment() from public, anon, authenticated;

-- 2. Friend requests are created only through send_friend_request (block checks, dedupe,
-- notification). The direct INSERT policy let a client skip the block check.
drop policy if exists "fr_insert" on public.friend_requests;
revoke insert, update, delete on public.friend_requests from anon, authenticated;

-- 3. Profiles: the app only edits nickname, avatar_url and style_preferences directly
-- (onboarding goes through save_onboarding). id, created_at and account_code are not
-- client-writable, and nickname/avatar_url get server-side validation.
revoke update on public.profiles from anon, authenticated;
grant update (nickname, avatar_url, style_preferences) on public.profiles to authenticated;

alter table public.profiles drop constraint if exists profiles_nickname_format;
alter table public.profiles
    add constraint profiles_nickname_format
    check (char_length(nickname) between 2 and 30 and nickname !~ '[[:cntrl:]]');

-- An avatar URL is fetched by every viewer's phone, so it must point at this project's own
-- public avatars bucket, inside the owner's folder, not at an arbitrary third-party host.
alter table public.profiles drop constraint if exists profiles_avatar_url_own_folder;
alter table public.profiles
    add constraint profiles_avatar_url_own_folder
    check (
        avatar_url is null
        or avatar_url ~ ('^https://exbozksjwpyvstqhcyqy\.supabase\.co/storage/v1/object/public/avatars/'
                         || id::text || '/[A-Za-z0-9._-]+$')
    );

-- 4. Defense in depth: signed-out callers have no policies on any public table, so they get
-- no table privileges either (permission denied instead of an empty result).
revoke all on all tables in schema public from anon;
