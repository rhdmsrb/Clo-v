-- Security hardening from the 2026-11-03 audit. Not yet applied to any database:
-- run against a DEV/branch project first (see supabase/tests/local/10_harden_security.sql).
-- Every function keeps its signature, so existing callers and grants carry over.
-- Not covered (needs `supabase db pull`): baseline RLS, storage policies,
-- block_user/is_blocked_pair, and the bump_*/notify_on_* trigger functions.

-- 1. Popular feed: hide posts when EITHER side blocked the other, and bound the offset.
create or replace function public.popular_fit_checks(
    p_limit integer default 20,
    p_offset integer default 0,
    p_window_days integer default 7
) returns table (id uuid, score bigint)
language sql
stable
security invoker
set search_path = ''
as $$
    select f.id,
           (f.vote_count + 2 * f.comment_count)::bigint as score
      from public.fit_checks f
     where f.is_public = true
       and f.status = 'live'
       and (f.expires_at is null or f.expires_at > now())
       and f.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_window_days, 7), 30)))
       and not public.is_blocked_pair(f.creator_id)
     order by score desc, f.created_at desc, f.id
     limit greatest(1, least(coalesce(p_limit, 20), 50))
     offset greatest(0, least(coalesce(p_offset, 0), 1000));
$$;
revoke all on function public.popular_fit_checks(integer, integer, integer) from public, anon;
grant execute on function public.popular_fit_checks(integer, integer, integer) to authenticated;

-- 2. Accepting a friend request must respect blocks (declining stays allowed).
create or replace function public.respond_friend_request(p_request_id uuid, p_accept boolean)
returns public.friendships
language plpgsql
security definer
set search_path = ''
as $$
declare r public.friend_requests; f public.friendships;
begin
  select * into r from public.friend_requests
   where id = p_request_id and addressee_id = auth.uid() and status = 'pending' for update;
  if r.id is null then
    raise exception 'Friend request not found' using errcode = 'P0002';
  end if;
  if p_accept and public.is_blocked_pair(r.requester_id) then
    raise exception 'This user is unavailable' using errcode = '42501';
  end if;
  update public.friend_requests
     set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
   where id = r.id;
  if not p_accept then return null; end if;
  insert into public.friendships (user_low, user_high)
  values (least(r.requester_id, r.addressee_id), greatest(r.requester_id, r.addressee_id))
  on conflict do nothing returning * into f;
  if f.user_low is null then
    select * into f from public.friendships
     where user_low = least(r.requester_id, r.addressee_id)
       and user_high = greatest(r.requester_id, r.addressee_id);
  end if;
  insert into public.notifications (recipient_id, actor_id, type)
  values (r.requester_id, auth.uid(), 'friend_accepted');
  return f;
end;
$$;

-- 3. Mutual-friend counts: bounded input, index-friendly joins, no blocked pairs.
create or replace function public.get_mutual_friend_counts(p_user_ids uuid[])
returns table (user_id uuid, mutual_count bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_user_ids, '{}'::uuid[])) > 100 then
    raise exception 'Too many users requested' using errcode = '22023';
  end if;
  return query
  with mine as (
    select f.user_high as friend_id from public.friendships f where f.user_low = auth.uid()
    union all
    select f.user_low from public.friendships f where f.user_high = auth.uid()
  ),
  cand as (
    select distinct c.id from unnest(coalesce(p_user_ids, '{}'::uuid[])) as c(id)
     where c.id <> auth.uid() and not public.is_blocked_pair(c.id)
  ),
  edges as (
    select cand.id as uid, f.user_high as other from cand join public.friendships f on f.user_low = cand.id
    union all
    select cand.id, f.user_low from cand join public.friendships f on f.user_high = cand.id
  )
  select e.uid, count(*)::bigint
    from edges e join mine m on m.friend_id = e.other
   group by e.uid;
end;
$$;

-- 4. Onboarding input limits (the table may also have constraints; this is the floor).
create or replace function public.save_onboarding(p_nickname text, p_style_preferences text[])
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_nickname text := trim(coalesce(p_nickname, ''));
  v_styles text[] := coalesce(p_style_preferences, '{}'::text[]);
  v_profile public.profiles;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if char_length(v_nickname) not between 2 and 30 or v_nickname ~ '[[:cntrl:]]' then
    raise exception 'Nickname must be 2-30 characters.' using errcode = '22023';
  end if;
  if cardinality(v_styles) > 20
     or exists (select 1 from unnest(v_styles) s where s is null or char_length(s) > 40) then
    raise exception 'Invalid style preferences.' using errcode = '22023';
  end if;

  insert into public.profiles (id, nickname, style_preferences)
  values (v_user_id, v_nickname, v_styles)
  on conflict (id) do update
    set nickname = excluded.nickname,
        style_preferences = excluded.style_preferences
  returning * into v_profile;

  return v_profile;
exception
  when unique_violation then
    raise exception 'That nickname is already taken.' using errcode = '23505';
end;
$$;

-- 5. Signed-in users only: drop the default PUBLIC/anon EXECUTE on client RPCs.
revoke all on function public.cancel_friend_request(uuid) from public, anon;
revoke all on function public.get_mutual_friend_counts(uuid[]) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.save_onboarding(text, text[]) from public, anon;
revoke all on function public.save_vote_reason(uuid, uuid, text[], text) from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.submit_content_report(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function public.cancel_friend_request(uuid) to authenticated;
grant execute on function public.get_mutual_friend_counts(uuid[]) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.save_onboarding(text, text[]) to authenticated;
grant execute on function public.save_vote_reason(uuid, uuid, text[], text) to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.submit_content_report(uuid, uuid, uuid, text, text) to authenticated;

-- 6. Strict wardrobe photo path: "<ownerId>/[<itemId>/]<file>" with a plain file name and an
-- image extension. Seeded rows use "<ownerId>/<name>.png", so .png and a missing item folder
-- are allowed. Blocks "..", "%", "\", "?", "#", ":" and any other owner's folder.
-- NOT VALID: new writes are checked now; run VALIDATE CONSTRAINT after confirming legacy rows.
alter table public.wardrobe_items
    drop constraint if exists wardrobe_items_image_url_strict_path;
alter table public.wardrobe_items
    add constraint wardrobe_items_image_url_strict_path
    check (
        image_url ~ ('^' || owner_id::text || '/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)?[A-Za-z0-9_-][A-Za-z0-9._-]*\.(jpg|jpeg|png|webp)$')
    ) not valid;

-- 7. Device tokens: bound the size on the direct-write path too.
alter table public.device_tokens
    drop constraint if exists device_tokens_token_length;
alter table public.device_tokens
    add constraint device_tokens_token_length check (char_length(token) between 1 and 512) not valid;

-- 8. Reports: reject a null reason explicitly.
create or replace function public.submit_content_report(
  p_fit_check_id uuid default null::uuid, p_comment_id uuid default null::uuid,
  p_reported_user_id uuid default null::uuid, p_reason text default 'other'::text,
  p_details text default null::text
)
returns public.content_reports
language plpgsql
security definer
set search_path = ''
as $$
declare r public.content_reports;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if num_nonnulls(p_fit_check_id, p_comment_id, p_reported_user_id) <> 1 then
    raise exception 'Choose exactly one item to report' using errcode = '22023';
  end if;
  if p_reason is null or p_reason not in ('inappropriate', 'harassment', 'spam', 'other') then
    raise exception 'Invalid report reason' using errcode = '22023';
  end if;
  insert into public.content_reports (reporter_id, fit_check_id, comment_id, reported_user_id, reason, details)
  values (auth.uid(), p_fit_check_id, p_comment_id, p_reported_user_id, p_reason,
          nullif(left(trim(coalesce(p_details, '')), 500), ''))
  on conflict do nothing returning * into r;
  if r.id is null then
    select * into r from public.content_reports
     where reporter_id = auth.uid()
       and ((p_fit_check_id is not null and fit_check_id = p_fit_check_id)
         or (p_comment_id is not null and comment_id = p_comment_id)
         or (p_reported_user_id is not null and reported_user_id = p_reported_user_id))
       and reason = p_reason
     order by created_at desc limit 1;
  end if;
  return r;
end;
$$;
revoke all on function public.submit_content_report(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function public.submit_content_report(uuid, uuid, uuid, text, text) to authenticated;
