-- ROLLBACK for 20261103000100_harden_security.sql.
-- Live function definitions and grants captured 2026-11-03 immediately before applying.
-- Run with: supabase db query --linked -f supabase/rollback/20261103000100_harden_security.sql

CREATE OR REPLACE FUNCTION public.cancel_friend_request(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.friend_requests
     set status = 'cancelled', responded_at = now()
   where id = p_request_id and requester_id = auth.uid() and status = 'pending';
end;
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.cancel_friend_request(p_request_id uuid) from public, anon, authenticated;
grant execute on function public.cancel_friend_request(p_request_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.get_mutual_friend_counts(p_user_ids uuid[])
 RETURNS TABLE(user_id uuid, mutual_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with mine as (
    select case when f.user_low = auth.uid() then f.user_high else f.user_low end as friend_id
      from public.friendships f
     where f.user_low = auth.uid() or f.user_high = auth.uid()
  )
  select candidate.user_id, count(*)::bigint
    from unnest(coalesce(p_user_ids, '{}'::uuid[])) as candidate(user_id)
    join public.friendships f on f.user_low = candidate.user_id or f.user_high = candidate.user_id
    join mine m on m.friend_id = case when f.user_low = candidate.user_id then f.user_high else f.user_low end
   where candidate.user_id <> auth.uid()
   group by candidate.user_id;
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.get_mutual_friend_counts(p_user_ids uuid[]) from public, anon, authenticated;
grant execute on function public.get_mutual_friend_counts(p_user_ids uuid[]) to authenticated;

CREATE OR REPLACE FUNCTION public.is_blocked_pair(p_other uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.blocked_users b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
       or (b.blocker_id = p_other and b.blocked_id = auth.uid())
  );
$function$;
-- captured ACL: {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
revoke all on function public.is_blocked_pair(p_other uuid) from public, anon, authenticated;
grant execute on function public.is_blocked_pair(p_other uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.popular_fit_checks(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_window_days integer DEFAULT 7)
 RETURNS TABLE(id uuid, score bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    -- vote_count / comment_count are maintained by live AFTER INSERT/DELETE
    -- triggers (bump_vote_count, bump_comment_count), so no per-row counting.
    select f.id,
           (f.vote_count + 2 * f.comment_count)::bigint as score
      from public.fit_checks f
     where f.is_public = true
       and f.status = 'live'
       and (f.expires_at is null or f.expires_at > now())
       and f.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_window_days, 7), 30)))
       and not exists (
             select 1 from public.blocked_users b where b.blocked_id = f.creator_id
           )
     order by score desc, f.created_at desc, f.id
     limit greatest(1, least(coalesce(p_limit, 20), 50))
     offset greatest(0, coalesce(p_offset, 0));
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.popular_fit_checks(p_limit integer, p_offset integer, p_window_days integer) from public, anon, authenticated;
grant execute on function public.popular_fit_checks(p_limit integer, p_offset integer, p_window_days integer) to authenticated;

CREATE OR REPLACE FUNCTION public.respond_friend_request(p_request_id uuid, p_accept boolean)
 RETURNS friendships
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.friend_requests; f public.friendships;
begin
  select * into r from public.friend_requests
   where id = p_request_id and addressee_id = auth.uid() and status = 'pending' for update;
  if r.id is null then
    raise exception 'Friend request not found' using errcode = 'P0002';
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
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.respond_friend_request(p_request_id uuid, p_accept boolean) from public, anon, authenticated;
grant execute on function public.respond_friend_request(p_request_id uuid, p_accept boolean) to authenticated;

CREATE OR REPLACE FUNCTION public.save_onboarding(p_nickname text, p_style_preferences text[])
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  insert into public.profiles (id, nickname, style_preferences)
  values (v_user_id, trim(p_nickname), coalesce(p_style_preferences, '{}'::text[]))
  on conflict (id) do update
    set nickname = excluded.nickname,
        style_preferences = excluded.style_preferences
  returning * into v_profile;

  return v_profile;
exception
  when unique_violation then
    raise exception 'That nickname is already taken.' using errcode = '23505';
end;
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.save_onboarding(p_nickname text, p_style_preferences text[]) from public, anon, authenticated;
grant execute on function public.save_onboarding(p_nickname text, p_style_preferences text[]) to authenticated;

CREATE OR REPLACE FUNCTION public.save_vote_reason(p_fit_check_id uuid, p_photo_id uuid, p_reason_tags text[] DEFAULT '{}'::text[], p_reason_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.fit_check_votes
     set reason_tags = coalesce(p_reason_tags, '{}'::text[]),
         reason_comment = nullif(left(btrim(coalesce(p_reason_comment, '')), 280), '')
   where fit_check_id = p_fit_check_id and photo_id = p_photo_id and voter_id = auth.uid();
  if not found then
    raise exception 'Vote not found' using errcode = 'P0002';
  end if;
end;
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.save_vote_reason(p_fit_check_id uuid, p_photo_id uuid, p_reason_tags text[], p_reason_comment text) from public, anon, authenticated;
grant execute on function public.save_vote_reason(p_fit_check_id uuid, p_photo_id uuid, p_reason_tags text[], p_reason_comment text) to authenticated;

CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid)
 RETURNS friend_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.friend_requests;
begin
  if auth.uid() is null or p_addressee_id is null or p_addressee_id = auth.uid() then
    raise exception 'Invalid friend request' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_addressee_id) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.blocked_users
     where (blocker_id = auth.uid() and blocked_id = p_addressee_id)
        or (blocker_id = p_addressee_id and blocked_id = auth.uid())
  ) then
    raise exception 'This user is unavailable' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.friendships
     where user_low = least(auth.uid(), p_addressee_id)
       and user_high = greatest(auth.uid(), p_addressee_id)
  ) then
    raise exception 'You are already friends' using errcode = '23505';
  end if;
  select * into r from public.friend_requests
   where requester_id = auth.uid() and addressee_id = p_addressee_id and status = 'pending';
  if r.id is not null then return r; end if;
  select * into r from public.friend_requests
   where requester_id = p_addressee_id and addressee_id = auth.uid() and status = 'pending';
  if r.id is not null then
    update public.friend_requests set status = 'accepted', responded_at = now() where id = r.id;
    insert into public.friendships
    values (least(auth.uid(), p_addressee_id), greatest(auth.uid(), p_addressee_id), now())
    on conflict do nothing;
    insert into public.notifications (recipient_id, actor_id, type)
    values (r.requester_id, auth.uid(), 'friend_accepted');
    return r;
  end if;
  insert into public.friend_requests (requester_id, addressee_id)
  values (auth.uid(), p_addressee_id) returning * into r;
  insert into public.notifications (recipient_id, actor_id, type)
  values (p_addressee_id, auth.uid(), 'friend_request');
  return r;
end;
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.send_friend_request(p_addressee_id uuid) from public, anon, authenticated;
grant execute on function public.send_friend_request(p_addressee_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.submit_content_report(p_fit_check_id uuid DEFAULT NULL::uuid, p_comment_id uuid DEFAULT NULL::uuid, p_reported_user_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT 'other'::text, p_details text DEFAULT NULL::text)
 RETURNS content_reports
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.content_reports;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if num_nonnulls(p_fit_check_id, p_comment_id, p_reported_user_id) <> 1 then
    raise exception 'Choose exactly one item to report' using errcode = '22023';
  end if;
  if p_reason not in ('inappropriate', 'harassment', 'spam', 'other') then
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
$function$;
-- captured ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
revoke all on function public.submit_content_report(p_fit_check_id uuid, p_comment_id uuid, p_reported_user_id uuid, p_reason text, p_details text) from public, anon, authenticated;
grant execute on function public.submit_content_report(p_fit_check_id uuid, p_comment_id uuid, p_reported_user_id uuid, p_reason text, p_details text) to authenticated;

alter table public.wardrobe_items drop constraint if exists wardrobe_items_image_url_strict_path;
alter table public.device_tokens drop constraint if exists device_tokens_token_length;
