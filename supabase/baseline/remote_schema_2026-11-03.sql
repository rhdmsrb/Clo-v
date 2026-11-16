


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "public"."block_user"("p_blocked_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null or p_blocked_id is null or p_blocked_id = auth.uid() then
    raise exception 'Invalid user' using errcode = '22023';
  end if;
  insert into public.blocked_users(blocker_id, blocked_id)
    values (auth.uid(), p_blocked_id) on conflict do nothing;
  delete from public.friend_requests
    where (requester_id = auth.uid() and addressee_id = p_blocked_id)
       or (requester_id = p_blocked_id and addressee_id = auth.uid());
  delete from public.friendships
    where user_low = least(auth.uid(), p_blocked_id)
      and user_high = greatest(auth.uid(), p_blocked_id);
  delete from public.profile_follows
    where (follower_id = auth.uid() and following_id = p_blocked_id)
       or (follower_id = p_blocked_id and following_id = auth.uid());
end;
$$;


ALTER FUNCTION "public"."block_user"("p_blocked_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_comment_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."bump_comment_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_vote_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."bump_vote_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_friend_request"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.friend_requests
     set status = 'cancelled', responded_at = now()
   where id = p_request_id and requester_id = auth.uid() and status = 'pending';
end;
$$;


ALTER FUNCTION "public"."cancel_friend_request"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text" DEFAULT NULL::"text", "p_group_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_group_id is not null and not public.is_group_member(p_group_id) then raise exception 'Group membership required' using errcode='42501'; end if;
 insert into public.fit_checks(id,creator_id,caption,status,is_public,group_id)
 values(p_id,auth.uid(),nullif(btrim(p_caption),''),'draft',p_group_id is null,p_group_id)
 on conflict(id) do nothing;
 select * into f from public.fit_checks where id=p_id for update;
 if f.creator_id is distinct from auth.uid() or f.status<>'draft'
 or f.group_id is distinct from p_group_id or f.caption is distinct from nullif(btrim(p_caption),'') then
  raise exception 'Draft request conflicts with an existing post' using errcode='22023';
 end if;
 return f.id;
end; $$;


ALTER FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text" DEFAULT NULL::"text", "p_group_id" "uuid" DEFAULT NULL::"uuid", "p_occasion" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_group_id is not null and not public.is_group_member(p_group_id) then raise exception 'Group membership required' using errcode='42501'; end if;
 insert into public.fit_checks(id,creator_id,caption,occasion,status,is_public,group_id) values(p_id,auth.uid(),nullif(btrim(p_caption),''),nullif(btrim(p_occasion),''),'draft',p_group_id is null,p_group_id) on conflict(id) do nothing;
 select * into f from public.fit_checks where id=p_id for update;
 if f.creator_id is distinct from auth.uid() or f.status<>'draft' or f.group_id is distinct from p_group_id or f.caption is distinct from nullif(btrim(p_caption),'') or f.occasion is distinct from nullif(btrim(p_occasion),'') then raise exception 'Draft request conflicts with an existing post' using errcode='22023'; end if;
 return f.id;
end; $$;


ALTER FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid", "p_occasion" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "creator_id" "uuid" NOT NULL,
    "invite_code" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."groups" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_group_with_owner"("p_name" "text", "p_code" "text") RETURNS SETOF "public"."groups"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare g public.groups;
begin
if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
if char_length(btrim(p_name)) not between 2 and 40 or p_name is null then raise exception 'Group name must be 2-40 characters' using errcode = '22023'; end if;
if p_code is null or p_code !~ '^[A-Z0-9]{6}$' then raise exception 'Invalid invite code' using errcode = '22023'; end if;
insert into public.groups(name, creator_id, invite_code) values (btrim(p_name), auth.uid(), p_code) returning * into g;
insert into public.group_members(group_id, profile_id) values (g.id, auth.uid()); return next g;
end; $_$;


ALTER FUNCTION "public"."create_group_with_owner"("p_name" "text", "p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- Deleting storage.objects with SQL only removes metadata, not the files.
  -- Reject an incomplete client cleanup so the account can safely retry.
  if exists (
    select 1 from storage.objects
    where bucket_id in ('avatars', 'fit-check-photos', 'wardrobe-items')
      and name like v_user_id::text || '/%'
  ) then
    raise exception 'Account photos must be removed first' using errcode = '23514';
  end if;

  -- The explicit profile delete repairs the old function even for a database
  -- where the FK has not yet been validated. Dependent app rows cascade.
  delete from public.profiles where id = v_user_id;
  delete from auth.users where id = v_user_id;
end;
$$;


ALTER FUNCTION "public"."delete_my_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."device_tokens_enforce_cap"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
    delete from public.device_tokens
     where token in (
        select token from public.device_tokens
         where user_id = new.user_id and token <> new.token
         order by updated_at desc
         offset 19
     );
    return new;
end;
$$;


ALTER FUNCTION "public"."device_tokens_enforce_cap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid" DEFAULT NULL::"uuid", "p_sort" "text" DEFAULT 'newest'::"text", "p_offset" integer DEFAULT 0, "p_limit" integer DEFAULT 12) RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_sort is null or p_sort not in ('newest','votes') or p_offset is null or p_offset<0 or p_offset>10000 or p_limit is null or p_limit not between 1 and 24 then raise exception 'Invalid feed page' using errcode='22023'; end if;
 return query
 with page as materialized (
 select f.* from public.fit_checks f
 where f.status='live' and (f.expires_at is null or f.expires_at>now())
 and ((p_group_id is null and f.is_public) or (p_group_id is not null and f.group_id=p_group_id))
 order by case when p_sort='votes' then f.vote_count end desc, f.created_at desc,f.id desc
 limit p_limit offset p_offset)
 select jsonb_build_object(
 'id',f.id,'creator_id',f.creator_id,'caption',f.caption,'created_at',f.created_at,'expires_at',f.expires_at,
 'vote_count',f.vote_count,'comment_count',f.comment_count,
 'my_vote',(select v.photo_id from public.fit_check_votes v where v.fit_check_id=f.id and v.voter_id=auth.uid()),
 'photo_vote_counts',coalesce((select jsonb_agg(jsonb_build_object('photo_id',v.photo_id,'count',v.n)) from
 (select photo_id,count(*) as n from public.fit_check_votes where fit_check_id=f.id group by photo_id) v),'[]'::jsonb),
 'fit_check_photos',coalesce((select jsonb_agg(to_jsonb(p) order by p.position) from public.fit_check_photos p where p.fit_check_id=f.id),'[]'::jsonb),
 'profiles',(select jsonb_build_object('nickname',p.nickname,'avatar_url',p.avatar_url) from public.profiles p where p.id=f.creator_id))
 from page f
 order by case when p_sort='votes' then f.vote_count end desc,f.created_at desc,f.id desc;
end; $$;


ALTER FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid", "p_sort" "text", "p_offset" integer, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_profiles_by_contact"("p_contact" "text") RETURNS TABLE("id" "uuid", "nickname" "text", "account_code" "text", "avatar_url" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  caller uuid := auth.uid();
  needle text := lower(trim(coalesce(p_contact, '')));
  digits text := regexp_replace(needle, '[^0-9]', '', 'g');
begin
  if caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if needle = '' then return; end if;
  if length(needle) > 254 then
    raise exception 'Invalid contact' using errcode = '22023';
  end if;

  -- Serialize concurrent calls for this caller before checking the budget.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(caller::text, 33));
  delete from public.contact_lookup_attempts
    where user_id = caller and searched_at < now() - interval '10 minutes';
  if (select count(*) from public.contact_lookup_attempts
      where user_id = caller and searched_at >= now() - interval '10 minutes') >= 20 then
    raise exception 'Too many contact searches. Please try again later.' using errcode = 'P0001';
  end if;
  insert into public.contact_lookup_attempts(user_id) values (caller);

  return query
  select p.id, p.nickname, p.account_code, p.avatar_url
  from auth.users u
  join public.profiles p on p.id = u.id
  where p.id <> caller
    and ((needle like '%@%' and lower(u.email) = needle)
      or (needle not like '%@%' and length(digits) >= 7
          and regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = digits));
end;
$$;


ALTER FUNCTION "public"."find_profiles_by_contact"("p_contact" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_mutual_friend_counts"("p_user_ids" "uuid"[]) RETURNS TABLE("user_id" "uuid", "mutual_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_mutual_friend_counts"("p_user_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_blocked_pair"("p_other" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.blocked_users b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
       or (b.blocker_id = p_other and b.blocked_id = auth.uid())
  );
$$;


ALTER FUNCTION "public"."is_blocked_pair"("p_other" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_group_member"("gid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.group_members
     where group_id = gid and profile_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."is_group_member"("gid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_group_by_code"("p_code" "text") RETURNS SETOF "public"."groups"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare g public.groups;
begin
if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,16));
if (select count(*) from public.group_join_attempts where profile_id = auth.uid() and attempted_at > now() - interval '10 minutes') >= 20 then raise exception 'Too many invite code attempts — try again later.' using errcode = 'P0001'; end if;
insert into public.group_join_attempts(profile_id) values (auth.uid());
select * into g from public.groups where invite_code = upper(regexp_replace(coalesce(p_code,''), '\s', '', 'g'));
if g.id is null then return; end if;
insert into public.group_members(group_id,profile_id) values (g.id,auth.uid()) on conflict (group_id,profile_id) do nothing; return next g;
end; $$;


ALTER FUNCTION "public"."join_group_by_code"("p_code" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wardrobe_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "image_url" "text" NOT NULL,
    "name" "text",
    "category" "text" NOT NULL,
    "subcategory" "text",
    "color" "text",
    "season" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "brand" "text",
    "wear_frequency" "text",
    "tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "wear_count" integer DEFAULT 0 NOT NULL,
    "last_worn_at" timestamp with time zone,
    CONSTRAINT "wardrobe_items_category_check" CHECK (("category" = ANY (ARRAY['top'::"text", 'bottom'::"text", 'dress'::"text", 'outerwear'::"text", 'shoes'::"text", 'accessory'::"text", 'set'::"text", 'other'::"text"]))),
    CONSTRAINT "wardrobe_items_season_check" CHECK ((("season" IS NULL) OR ("season" = ANY (ARRAY['spring'::"text", 'summer'::"text", 'fall'::"text", 'winter'::"text", 'all'::"text"])))),
    CONSTRAINT "wardrobe_items_wear_frequency_check" CHECK ((("wear_frequency" IS NULL) OR ("wear_frequency" = ANY (ARRAY['rarely'::"text", 'sometimes'::"text", 'often'::"text", 'favorite'::"text"]))))
);


ALTER TABLE "public"."wardrobe_items" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_wardrobe_wear"("p_item_id" "uuid") RETURNS "public"."wardrobe_items"
    LANGUAGE "sql"
    SET "search_path" TO 'public'
    AS $$
  -- security invoker: RLS still limits this to rows the caller owns; the
  -- owner_id check makes that explicit for readers of this function.
  update public.wardrobe_items
     set wear_count = wear_count + 1,
         last_worn_at = now()
   where id = p_item_id
     and owner_id = auth.uid()
  returning *;
$$;


ALTER FUNCTION "public"."log_wardrobe_wear"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_on_comment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id, comment_id)
  select f.creator_id, new.commenter_id, 'comment', new.fit_check_id, new.photo_id, new.id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.commenter_id;
  return new;
end;
$$;


ALTER FUNCTION "public"."notify_on_comment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_on_vote"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into notifications (recipient_id, actor_id, type, fit_check_id, photo_id)
  select f.creator_id, new.voter_id, 'vote', new.fit_check_id, new.photo_id
  from fit_checks f
  where f.id = new.fit_check_id
    and f.creator_id is distinct from new.voter_id;
  return new;
end;
$$;


ALTER FUNCTION "public"."notify_on_vote"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."popular_fit_checks"("p_limit" integer DEFAULT 20, "p_offset" integer DEFAULT 0, "p_window_days" integer DEFAULT 7) RETURNS TABLE("id" "uuid", "score" bigint)
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."popular_fit_checks"("p_limit" integer, "p_offset" integer, "p_window_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."publish_fit_check"("p_id" "uuid", "p_duration_seconds" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks;
begin select * into f from public.fit_checks where id=p_id for update; if auth.uid() is null or f.id is null or f.creator_id<>auth.uid() then raise exception 'Post unavailable' using errcode='42501'; end if; if f.status='live' then return; end if; if f.status<>'draft' or p_duration_seconds is null or p_duration_seconds not in(3600,21600,86400) then raise exception 'Invalid publication request' using errcode='22023'; end if; if f.group_id is not null and not public.is_group_member(f.group_id) then raise exception 'Group membership required' using errcode='42501'; end if; if (select count(*) from public.fit_check_photos where fit_check_id=p_id) not in (2,4) then raise exception 'Upload exactly 2 or 4 photos' using errcode='23514'; end if; if exists(select 1 from public.fit_check_photos p where p.fit_check_id=p_id and (p.image_url not like auth.uid()::text||'/'||p_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='fit-check-photos' and o.name=p.image_url))) then raise exception 'Photo upload is incomplete' using errcode='23514'; end if; update public.fit_checks set status='live',created_at=now(),expires_at=now()+make_interval(secs=>p_duration_seconds),ended_at=null where id=p_id; end;
$$;


ALTER FUNCTION "public"."publish_fit_check"("p_id" "uuid", "p_duration_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text" DEFAULT 'ios'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_token is null or char_length(p_token) not between 1 and 512 then
    raise exception 'invalid device token' using errcode = '22023';
  end if;
  if coalesce(p_platform, 'ios') <> 'ios' then
    raise exception 'invalid platform' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), 'ios', now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;


ALTER FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reserve_tryon_slot"("p_owner" "uuid", "p_max" integer, "p_window_seconds" integer) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
    v_recent integer;
    v_id text;
begin
    perform pg_advisory_xact_lock(hashtextextended(p_owner::text, 0));
    -- Placeholders older than the window never reached a provider job id and
    -- no longer count; drop them so they do not accumulate.
    delete from public.wardrobe_tryon_jobs
     where owner_id = p_owner
       and job_id like 'pending-%'
       and created_at < now() - make_interval(secs => p_window_seconds);
    select count(*) into v_recent
      from public.wardrobe_tryon_jobs
     where owner_id = p_owner
       and created_at >= now() - make_interval(secs => p_window_seconds);
    if v_recent >= p_max then
        return null;
    end if;
    v_id := 'pending-' || gen_random_uuid()::text;
    insert into public.wardrobe_tryon_jobs (job_id, owner_id) values (v_id, p_owner);
    return v_id;
end;
$$;


ALTER FUNCTION "public"."reserve_tryon_slot"("p_owner" "uuid", "p_max" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."friendships" (
    "user_low" "uuid" NOT NULL,
    "user_high" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "friendships_check" CHECK (("user_low" < "user_high"))
);


ALTER TABLE "public"."friendships" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."respond_friend_request"("p_request_id" "uuid", "p_accept" boolean) RETURNS "public"."friendships"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."respond_friend_request"("p_request_id" "uuid", "p_accept" boolean) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "nickname" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "style_preferences" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "avatar_url" "text",
    "account_code" "text" DEFAULT ('CLOV-'::"text" || "upper"("substr"("encode"("extensions"."gen_random_bytes"(6), 'hex'::"text"), 1, 8))) NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_onboarding"("p_nickname" "text", "p_style_preferences" "text"[]) RETURNS "public"."profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."save_onboarding"("p_nickname" "text", "p_style_preferences" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_vote_reason"("p_fit_check_id" "uuid", "p_photo_id" "uuid", "p_reason_tags" "text"[] DEFAULT '{}'::"text"[], "p_reason_comment" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."save_vote_reason"("p_fit_check_id" "uuid", "p_photo_id" "uuid", "p_reason_tags" "text"[], "p_reason_comment" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."friend_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "addressee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "friend_requests_check" CHECK (("requester_id" <> "addressee_id")),
    CONSTRAINT "friend_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."friend_requests" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_friend_request"("p_addressee_id" "uuid") RETURNS "public"."friend_requests"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."send_friend_request"("p_addressee_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "fit_check_id" "uuid",
    "comment_id" "uuid",
    "reported_user_id" "uuid",
    "reason" "text" NOT NULL,
    "details" "text",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "content_reports_check" CHECK (("num_nonnulls"("fit_check_id", "comment_id", "reported_user_id") = 1)),
    CONSTRAINT "content_reports_check1" CHECK ((("reported_user_id" IS NULL) OR ("reported_user_id" <> "reporter_id"))),
    CONSTRAINT "content_reports_reason_check" CHECK (("reason" = ANY (ARRAY['inappropriate'::"text", 'harassment'::"text", 'spam'::"text", 'other'::"text"]))),
    CONSTRAINT "content_reports_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'reviewing'::"text", 'resolved'::"text", 'dismissed'::"text"])))
);


ALTER TABLE "public"."content_reports" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_content_report"("p_fit_check_id" "uuid" DEFAULT NULL::"uuid", "p_comment_id" "uuid" DEFAULT NULL::"uuid", "p_reported_user_id" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT 'other'::"text", "p_details" "text" DEFAULT NULL::"text") RETURNS "public"."content_reports"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."submit_content_report"("p_fit_check_id" "uuid", "p_comment_id" "uuid", "p_reported_user_id" "uuid", "p_reason" "text", "p_details" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."terminate_fit_check"("p_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks;
begin
 select * into f from public.fit_checks where id=p_id for update;
 if auth.uid() is null or f.id is null or f.creator_id<>auth.uid() then raise exception 'Post unavailable' using errcode='42501'; end if;
 if f.status='draft' then raise exception 'Post is not published' using errcode='22023'; end if;
 if f.status='live' then
  update public.fit_checks set status=case when expires_at<=now() then 'expired' else 'archived' end,
  ended_at=case when expires_at<=now() then expires_at else now() end where id=p_id;
 end if;
end; $$;


ALTER FUNCTION "public"."terminate_fit_check"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_tryon_poll"("p_job_id" "text", "p_owner" "uuid", "p_min_interval_seconds" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
    v_updated integer;
begin
    update public.wardrobe_tryon_jobs
       set last_polled_at = now()
     where job_id = p_job_id
       and owner_id = p_owner
       and (last_polled_at is null
            or last_polled_at <= now() - make_interval(secs => p_min_interval_seconds));
    get diagnostics v_updated = row_count;
    return v_updated = 1;
end;
$$;


ALTER FUNCTION "public"."touch_tryon_poll"("p_job_id" "text", "p_owner" "uuid", "p_min_interval_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_wardrobe_item"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$ begin new.updated_at=now(); return new; end; $$;


ALTER FUNCTION "public"."touch_wardrobe_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_draft_photo"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks; target uuid;
begin
 target=case when tg_op='DELETE' then old.fit_check_id else new.fit_check_id end;
 select * into f from public.fit_checks where id=target for update;
 if tg_op='DELETE' and f.id is null then return old; end if; -- parent cascade
 if f.id is null or f.status<>'draft' or f.creator_id is distinct from auth.uid() then raise exception 'Only draft photos may change' using errcode='42501'; end if;
 if tg_op='DELETE' then return old; end if;
 if new.image_url not like f.creator_id::text||'/'||f.id::text||'/%' then raise exception 'Invalid photo path' using errcode='23514'; end if;
 return new;
end; $$;


ALTER FUNCTION "public"."validate_draft_photo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_fit_check_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare f public.fit_checks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into f from public.fit_checks where id=new.fit_check_id for update;
 if not (f.is_public or f.creator_id=auth.uid() or public.is_group_member(f.group_id)) then raise exception 'Post unavailable' using errcode='42501'; end if;
 if f.id is null or f.status<>'live' or f.expires_at<=now() then raise exception 'Fit-Check is not live' using errcode='23514'; end if;
 if new.photo_id is not null and not exists(select 1 from public.fit_check_photos p where p.id=new.photo_id and p.fit_check_id=new.fit_check_id) then
  raise exception 'Photo does not belong to this Fit-Check' using errcode='23514';
 end if;
 return new;
end; $$;


ALTER FUNCTION "public"."validate_fit_check_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."allow_only_operation"("expected_operation" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION "storage"."allow_only_operation"("expected_operation" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_lifecycle_objects"("object_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "is_delete_marker" boolean, "metadata" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    object_id uuid;
    deleted_row storage.objects%ROWTYPE;
    deleted_ids uuid[];
    deleted_markers boolean[];
    deleted_metadata jsonb[];
    bulk_deleted boolean := false;
BEGIN
    -- Surface pre-existing deferred violations instead of treating them as blocked rows.
    SET CONSTRAINTS ALL IMMEDIATE;
    PERFORM set_config('storage.allow_delete_query', 'true', true);

    -- One subxact keeps the subxid cache from overflowing; rows return only once it commits.
    BEGIN
        WITH deleted AS (
            DELETE FROM storage.objects AS object_row
              WHERE object_row.id = ANY(object_ids) AND object_row.archived_at IS NOT NULL
              RETURNING object_row.id, object_row.is_delete_marker, object_row.metadata
        )
        SELECT array_agg(deleted.id), array_agg(deleted.is_delete_marker), array_agg(deleted.metadata)
          INTO deleted_ids, deleted_markers, deleted_metadata
          FROM deleted;
        bulk_deleted := true;
    EXCEPTION
        WHEN OTHERS THEN
            -- User triggers may use insufficient_privilege to block a row.
            IF SQLSTATE <> '42501' AND left(SQLSTATE, 2) IN ('08', '40', '42', '53', '55', '57', '58', 'XX') THEN
                RAISE;
            END IF;
    END;
    IF bulk_deleted THEN
        RETURN QUERY SELECT * FROM unnest(deleted_ids, deleted_markers, deleted_metadata);
        RETURN;
    END IF;

    FOREACH object_id IN ARRAY object_ids LOOP
        BEGIN
            DELETE FROM storage.objects AS object_row
              WHERE object_row.id = object_id AND object_row.archived_at IS NOT NULL
              RETURNING object_row.* INTO deleted_row;
            IF FOUND THEN
                id := deleted_row.id;
                is_delete_marker := deleted_row.is_delete_marker;
                metadata := deleted_row.metadata;
                RETURN NEXT;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLSTATE <> '42501' AND left(SQLSTATE, 2) IN ('08', '40', '42', '53', '55', '57', '58', 'XX') THEN
                    RAISE;
                END IF;
        END;
    END LOOP;
END;
$$;


ALTER FUNCTION "storage"."delete_lifecycle_objects"("object_ids" "uuid"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_lifecycle_service_role"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
BEGIN
  IF current_user::text IS DISTINCT FROM TG_ARGV[0] THEN
    -- Keep this check AFTER caller RLS accepts the proposed row. The API
    -- recognizes this exact signal after rolling back its permission probe.
    RAISE EXCEPTION 'bucket control columns may only be changed by the configured storage service role'
      USING ERRCODE = 'PST01',
            SCHEMA = TG_TABLE_SCHEMA,
            TABLE = TG_TABLE_NAME,
            CONSTRAINT = TG_NAME;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."enforce_bucket_lifecycle_service_role"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_versioning_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.versioning_status = OLD.versioning_status THEN
        RETURN NEW;
    END IF;

    IF NEW.versioning_status = 'DISABLED' OR
       (OLD.versioning_status = 'DISABLED' AND NEW.versioning_status = 'SUSPENDED') THEN
        RAISE EXCEPTION 'Cannot transition bucket versioning status from % to %',
            OLD.versioning_status, NEW.versioning_status;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."enforce_versioning_status_transition"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
SELECT CASE
    WHEN p_delimiter <> ''
         AND position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(
        p_key,
        length(p_prefix)
            + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1))
            + length(p_delimiter) - 1
    )
    ELSE NULL
END;
$$;


ALTER FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"("noncurrent_versions" "text" DEFAULT 'include'::"text", "delete_markers" "text" DEFAULT 'include'::"text") RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'include');
    delete_markers := COALESCE(delete_markers, 'include');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'include';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'include';
    END IF;

    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        where (noncurrent_versions != 'exclude' OR obj.archived_at IS NULL)
          and (noncurrent_versions != 'only' OR obj.archived_at IS NOT NULL)
          and (delete_markers != 'exclude' OR NOT obj.is_delete_marker)
          and (delete_markers != 'only' OR obj.is_delete_marker)
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"("noncurrent_versions" "text", "delete_markers" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text", "raw_prefix_param" "text" DEFAULT NULL::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE
    AS $_$
WITH candidates AS (
    SELECT
        upload.key AS object_key,
        CASE
            WHEN position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0
            THEN left(
                upload.key,
                length(coalesce($7, $2))
                    + position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1))
                    + length($3) - 1
            )
            ELSE upload.key
        END AS result_key,
        upload.id,
        upload.created_at,
        position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0 AS is_common_prefix
    FROM storage.s3_multipart_uploads AS upload
    WHERE upload.bucket_id = $1
      AND upload.key COLLATE "C" LIKE $2 || '%'
), filtered AS (
    SELECT candidate.*
    FROM candidates AS candidate
    WHERE $5 = ''
       OR candidate.result_key COLLATE "C" > $5
       OR (
           candidate.result_key COLLATE "C" = $5
           AND NOT candidate.is_common_prefix
           AND $6 <> ''
           -- A completed or aborted marker repeats the remaining same-key uploads.
           AND COALESCE(
               (candidate.created_at, candidate.id COLLATE "C") > (
                   SELECT marker.created_at, marker.id COLLATE "C"
                   FROM storage.s3_multipart_uploads AS marker
                   WHERE marker.bucket_id = $1
                     AND marker.key COLLATE "C" = $5
                     AND marker.id = $6
               ),
               TRUE
           )
       )
), ranked AS (
    SELECT
        filtered.*,
        row_number() OVER (
            PARTITION BY filtered.result_key COLLATE "C"
            ORDER BY filtered.created_at, filtered.id COLLATE "C"
        ) AS prefix_rank
    FROM filtered
)
SELECT ranked.result_key, ranked.id, ranked.created_at
FROM ranked
WHERE NOT ranked.is_common_prefix OR ranked.prefix_rank = 1
ORDER BY ranked.result_key COLLATE "C", ranked.created_at, ranked.id COLLATE "C"
LIMIT $4;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text", "raw_prefix_param" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "noncurrent_versions" "text" DEFAULT 'exclude'::"text", "delete_markers" "text" DEFAULT 'exclude'::"text", "next_token_archived_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "next_token_version" "text" DEFAULT ''::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "version" "text", "archived_at" timestamp with time zone, "is_delete_marker" boolean, "is_versioned" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_start_relative TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;

    -- true when noncurrent_versions can return >1 row per name; keeps them
    -- ordered most-recent-first and lets pagination resume mid-key
    v_multi_row BOOLEAN;
    v_name_order TEXT;
    v_exact_range_predicate TEXT;
    v_strict_range_predicate TEXT;
    v_inclusive_range_predicate TEXT;

    -- Seek state for the current name. archived_at is normalized to JavaScript's
    -- millisecond precision and version breaks ties within the same millisecond.
    -- Current rows use 'infinity'; NULL means no tiebreak has been established.
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_cursor_is_folder BOOLEAN;
    v_count INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_batch_query_strict TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');
    v_name_order := CASE WHEN v_is_asc THEN 'ASC' ELSE 'DESC' END;

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Keep caller-provided cursors inside the requested prefix range.
    IF v_start <> '' AND v_upper_bound IS NOT NULL THEN
        IF v_is_asc THEN
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                v_start := '';
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                RETURN;
            END IF;
        ELSE
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                RETURN;
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                v_start := '';
            END IF;
        END IF;
    END IF;

    v_start_relative := substring(v_start FROM length(v_prefix) + 1);

    -- Direction affects only the indexed name range and its ordering. Cursor
    -- state transitions and within-key version ordering stay shared.
    IF v_is_asc THEN
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" > $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" >= $2';
        IF v_upper_bound IS NOT NULL THEN
            v_exact_range_predicate := 'o.name COLLATE "C" < $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" < $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" < $3';
        END IF;
    ELSE
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" < $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" < $2';
        IF v_prefix <> '' THEN
            v_exact_range_predicate := 'o.name COLLATE "C" >= $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" >= $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" >= $3';
        END IF;
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    -- The multi-row order matches the externally serialized cursor exactly:
    -- archived_at at millisecond precision, then version as the final tiebreak.
    --
    -- When v_multi_row, the seek is a keyset tuple comparison ("name > $2 OR
    -- (name = $2 AND tiebreak)") - Postgres won't split that OR into indexable
    -- form (confirmed even with fully literal values), so as one WHERE clause
    -- it forces a full bucket scan filtered row-by-row. Splitting it into two
    -- independently-indexable branches (exact name match with the tiebreak
    -- filter, vs. strictly-past names) combined with UNION ALL lets each
    -- branch keep name as a real index condition; the outer ORDER BY/LIMIT
    -- re-merges them into the same page the single query used to produce.
    IF v_multi_row THEN
        v_batch_query := format(
            $sql$
            SELECT *
            FROM (
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND o.name COLLATE "C" = $2
                      AND %s
                      AND NOT $7::boolean
                      AND (
                          $5::timestamptz IS NULL
                          OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < $5
                          OR (
                              COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = $5
                              AND COALESCE(o.version, '') > $6
                          )
                      )
                      %s
                    ORDER BY
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
                UNION ALL
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND %s
                      %s
                    ORDER BY
                        o.name COLLATE "C" %s,
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
            ) sub
            ORDER BY
                sub.name COLLATE "C" %s,
                COALESCE(date_trunc('milliseconds', sub.archived_at), 'infinity'::timestamptz) DESC,
                COALESCE(sub.version, '') ASC
            LIMIT $4
            $sql$,
            v_exact_range_predicate,
            v_version_filter,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order,
            v_name_order
        );
    ELSE
        v_batch_query := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_inclusive_range_predicate,
            v_version_filter,
            v_name_order
        );

        -- Strict counterpart of the query above: used once the single-row
        -- ASC batch advance (below) has left v_next_seek pointing at the
        -- last row already emitted, so an inclusive predicate would
        -- re-match it forever. Only single-row mode ever sets strict mode,
        -- so this variant is never needed when v_multi_row.
        v_batch_query_strict := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order
        );
    END IF;

    -- The static peek predicates cannot use the partial delete-marker index
    -- once PL/pgSQL switches to a generic plan because whether
    -- is_delete_marker is required remains parameter-dependent. Reuse the
    -- already-specialized batch query with a one-row limit for this sparse
    -- filter so the plan sees a literal `o.is_delete_marker` predicate.
    IF delete_markers = 'only' THEN
        v_delete_marker_peek_query :=
            'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        IF NOT v_multi_row THEN
            v_delete_marker_peek_query_strict :=
                'SELECT marker_page.name FROM (' || v_batch_query_strict || ') marker_page LIMIT 1';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor performs one specialized initial seek so
            -- partial current-version and delete-marker indexes remain available.
            EXECUTE format(
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY o.name COLLATE "C" DESC LIMIT 1',
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND o.name COLLATE "C" >= $2 AND o.name COLLATE "C" < $3'
                    ELSE ''
                END,
                v_version_filter
            )
            INTO v_next_seek
            USING _bucket_id, v_prefix, v_upper_bound;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Folder continuation tokens retain their trailing delimiter. A
        -- delimiter-less startAfter is always a literal key boundary.
        v_cursor_is_folder := delimiter_param <> ''
            AND v_start_relative <> ''
            AND right(v_start_relative, length(delimiter_param)) = delimiter_param;

        IF v_cursor_is_folder THEN
            v_next_seek := CASE
                WHEN right(v_start, length(delimiter_param)) = delimiter_param
                    THEN v_start
                ELSE v_start || delimiter_param
            END;
            IF v_is_asc THEN
                v_next_seek := left(v_next_seek, -1)
                    || chr(ascii(right(v_next_seek, 1)) + 1);
            END IF;
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- leaf object: when v_multi_row, stay on v_start with the
            -- caller-supplied tiebreak so a page boundary mid-key resumes
            -- that key's remaining rows instead of skipping them. Truncate
            -- to milliseconds like every other v_next_seek_at assignment -
            -- harmless today since object.ts's cursor always round-trips
            -- through JS Date first, but this shouldn't rely on that.
            IF v_multi_row THEN
                v_next_seek := v_start;
                v_next_seek_at := date_trunc('milliseconds', next_token_archived_at);
                v_next_seek_version := coalesce(next_token_version, '');
                v_next_seek_strict := coalesce(next_token, '') = '';
            ELSIF v_is_asc THEN
                v_next_seek := v_start;
                v_next_seek_strict := true;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        -- v_multi_row is branched here (rather than folded into the WHERE
        -- clause as a bound parameter) so each concrete query keeps an
        -- unconditional seek predicate - once PL/pgSQL switches to its
        -- cached generic plan (after 5 calls), a parameter-gated
        -- "(NOT v_multi_row AND name >= $x) OR (v_multi_row AND ...)"
        -- predicate stops the planner from using name as an index
        -- condition at all, degrading every subsequent peek to a full
        -- index scan filtered row-by-row instead of a bounded range scan.
        -- v_multi_row's seek predicate is a keyset tuple comparison
        -- ("name > x OR (name = x AND tiebreak)") - Postgres does not
        -- split this OR into indexable form even with fully literal
        -- values, so it falls back to a full scan filtered row-by-row.
        -- Splitting it into two independently-indexable branches (exact
        -- name match with the tiebreak filter, vs. strictly-past name)
        -- combined with UNION ALL lets each branch keep name as a real
        -- index condition; the outer ORDER BY/LIMIT picks whichever of
        -- the (at most 2) rows sorts first.
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING _bucket_id, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END,
                    1, v_next_seek_at, v_next_seek_version, v_next_seek_strict;
        ELSIF v_multi_row THEN
            IF v_is_asc THEN
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" < v_upper_bound
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek AND o.name COLLATE "C" < v_upper_bound
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" >= v_prefix
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        ELSE
            -- Single-row mode is always noncurrent_versions='exclude'. Keep
            -- this predicate literal so generic plans use the current index.
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.name COLLATE "C" >= v_prefix
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := v_common_prefix;
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            version := NULL;
            archived_at := NULL;
            is_delete_marker := NULL;
            is_versioned := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1)
                    || chr(ascii(right(v_common_prefix, 1)) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row THEN v_batch_query_strict ELSE v_batch_query END
                USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size, v_next_seek_at, v_next_seek_version,
                v_next_seek_strict
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN v_current.name
                        ELSE v_current.name || delimiter_param
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                version := v_current.version;
                archived_at := v_current.archived_at;
                is_delete_marker := v_current.is_delete_marker;
                is_versioned := v_current.is_versioned;
                RETURN NEXT;
                v_count := v_count + 1;

                -- when v_multi_row, stay on this name and record its
                -- archived_at as the new tiebreak so remaining rows for the
                -- same key are picked up before moving to the next name
                IF v_multi_row THEN
                    v_next_seek := v_current.name;
                    v_next_seek_at := COALESCE(date_trunc('milliseconds', v_current.archived_at), 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                    v_next_seek_strict := false;
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor
                    -- would skip a real key like `name || '!'` (or any
                    -- character sorting below the delimiter), which sorts
                    -- between `name` and `name || delimiter`. Track the real
                    -- name and mark the next comparison strict instead.
                    v_next_seek := v_current.name;
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.list_objects_with_delimiter made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text", "sort_order" "text", "noncurrent_versions" "text", "delete_markers" "text", "next_token_archived_at" timestamp with time zone, "next_token_version" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_active_lifecycle_states"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM storage.bucket_lifecycle_states
        WHERE bucket_id = OLD.id
          AND NOT (
              continuation IS NULL
              OR (continuation @> '{"continuationVersion": 1}' AND continuation #> '{batch,inFlight}' IS NULL)
          )
    ) THEN
        RAISE EXCEPTION 'update or delete on table "buckets" violates foreign key constraint "bucket_lifecycle_states_bucket_id_fkey" on table "bucket_lifecycle_states"'
            USING ERRCODE = 'foreign_key_violation',
                  DETAIL = format('Key (id)=(%s) is still referenced from table "bucket_lifecycle_states".', OLD.id),
                  SCHEMA = 'storage',
                  TABLE = 'bucket_lifecycle_states',
                  CONSTRAINT = 'bucket_lifecycle_states_bucket_id_fkey';
    END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION "storage"."protect_active_lifecycle_states"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_bucket_control_columns"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  configuration_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.lifecycle_configuration IS NOT NULL
       OR NEW.lifecycle_configuration_generation IS NOT NULL THEN
      IF NOT pg_has_role(current_user, TG_ARGV[0], 'MEMBER') THEN
        RAISE EXCEPTION 'only members of the configured storage service role may insert lifecycle policy state'
          USING ERRCODE = '42501',
                HINT = format(
                  'Insert with both lifecycle columns NULL and configure lifecycle through the Storage API afterward, or insert as a member of %I.',
                  TG_ARGV[0]
                );
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  configuration_changed =
    OLD.lifecycle_configuration IS DISTINCT FROM NEW.lifecycle_configuration
    OR OLD.lifecycle_configuration_generation IS DISTINCT FROM NEW.lifecycle_configuration_generation;

  IF NOT configuration_changed THEN
    RETURN NEW;
  END IF;

  IF NEW.type IS DISTINCT FROM 'STANDARD' THEN
    RAISE EXCEPTION 'bucket versioning and lifecycle controls require a Standard bucket'
      USING ERRCODE = '0A000';
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     AND NEW.lifecycle_configuration_generation IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     OR NEW.lifecycle_configuration_generation IS NULL
     OR OLD.lifecycle_configuration IS NOT DISTINCT FROM NEW.lifecycle_configuration
     OR OLD.lifecycle_configuration_generation IS NOT DISTINCT FROM NEW.lifecycle_configuration_generation THEN
    RAISE EXCEPTION 'a changed lifecycle policy requires a new non-null generation'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."protect_bucket_control_columns"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."protect_delete"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."reconcile_lifecycle_state"("target_bucket_id" "text", "policy_changed" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
    bucket storage.buckets%ROWTYPE;
    active boolean;
    idle boolean;
    state_generation uuid;
BEGIN
    SELECT * INTO bucket FROM storage.buckets WHERE id = target_bucket_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT continuation IS NULL OR (
               continuation @> '{"continuationVersion": 1}'
               AND continuation #> '{batch,inFlight}' IS NULL
           ), generation
    INTO idle, state_generation
    FROM storage.bucket_lifecycle_states
    WHERE bucket_id = target_bucket_id
    FOR UPDATE;

    IF bucket.lifecycle_configuration IS NULL THEN
        DELETE FROM storage.bucket_lifecycle_states
        WHERE bucket_id = target_bucket_id
          AND idle IS TRUE;

        UPDATE storage.bucket_lifecycle_states
        SET next_run_at = clock_timestamp(), updated_at = clock_timestamp()
        WHERE bucket_id = target_bucket_id
          AND idle IS NOT TRUE;
        RETURN;
    END IF;

    active := bucket.versioning_status <> 'DISABLED'
        AND bucket.lifecycle_configuration @> '{"rules":[{"status":"Enabled"}]}'::jsonb;

    -- The state row records the generation it was reconciled with so callers need not detect
    -- policy changes. Rows without a recorded generation keep their work.
    policy_changed := policy_changed OR (
        state_generation IS NOT NULL AND state_generation <> bucket.lifecycle_configuration_generation
    );

    INSERT INTO storage.bucket_lifecycle_states AS state (bucket_id, generation, next_run_at)
    VALUES (bucket.id, bucket.lifecycle_configuration_generation, CASE WHEN active THEN clock_timestamp() END)
    ON CONFLICT (bucket_id) DO UPDATE
    SET next_run_at = CASE
            WHEN policy_changed THEN
                CASE WHEN active OR idle IS NOT TRUE THEN clock_timestamp() END
            ELSE EXCLUDED.next_run_at
        END,
        generation = EXCLUDED.generation,
        claim_id = CASE WHEN policy_changed AND idle IS TRUE
                        THEN NULL ELSE state.claim_id END,
        claim_until = CASE WHEN policy_changed AND idle IS TRUE
                           THEN NULL ELSE state.claim_until END,
        continuation = CASE WHEN policy_changed AND idle IS TRUE
                            THEN NULL ELSE state.continuation END,
        failure_count = CASE WHEN policy_changed AND idle IS TRUE
                             THEN 0 ELSE state.failure_count END,
        last_error = CASE WHEN policy_changed AND idle IS TRUE
                          THEN NULL ELSE state.last_error END,
        updated_at = clock_timestamp()
    WHERE policy_changed OR (state.next_run_at IS NULL AND EXCLUDED.next_run_at IS NOT NULL);
END;
$$;


ALTER FUNCTION "storage"."reconcile_lifecycle_state"("target_bucket_id" "text", "policy_changed" boolean) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text", "noncurrent_versions" "text" DEFAULT 'exclude'::"text", "delete_markers" "text" DEFAULT 'exclude'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb", "version" "text", "archived_at" timestamp with time zone, "is_delete_marker" boolean, "is_versioned" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_prefix_len INT;
    v_prefix_start INT;
    v_combined_levels INT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;
    v_multi_row BOOLEAN;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_count INT := 0;
    v_skipped INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;
    v_previous_skipped INT;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_prefix_len := length(coalesce(prefix, ''));
    v_prefix_start := coalesce(array_length(string_to_array(coalesce(prefix, ''), v_delimiter), 1), 1);
    v_combined_levels := coalesce(array_length(string_to_array(v_prefix, v_delimiter), 1), 1);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT array_to_string(path_tokens[$1:$2], '/') AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $3 || '%%'
                  AND bucket_id = $4
                  AND array_length(objects.path_tokens, 1) <> $2
                  AND ($7 != 'exclude' OR objects.archived_at IS NULL)
                  AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
                  AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
                  AND ($8 != 'only' OR objects.is_delete_marker)
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata,
                   NULL::text AS version,
                   NULL::timestamptz AS archived_at,
                   NULL::boolean AS is_delete_marker,
                   NULL::boolean AS is_versioned FROM folders)
            UNION ALL
            (SELECT array_to_string(path_tokens[$1:$2], '/') AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata,
                   version, archived_at, is_delete_marker, is_versioned
             FROM storage.objects
             WHERE objects.name ILIKE $3 || '%%'
               AND bucket_id = $4
               AND array_length(objects.path_tokens, 1) = $2
               AND ($7 != 'exclude' OR objects.archived_at IS NULL)
               AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
               AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
               AND ($8 != 'only' OR objects.is_delete_marker)
             -- name, then version, as tiebreaks so two versions of the same
             -- key tying on the sort column still sort deterministically
             ORDER BY %I %s, name COLLATE "C" %s, COALESCE(version, '') %s)
            LIMIT $5 OFFSET $6
            $sql$, v_sort_order, v_order_by, v_sort_order, v_sort_order, v_sort_order
        ) USING v_prefix_start, v_combined_levels, v_prefix, bucketname, v_limit, offsets, noncurrent_versions, delete_markers;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build a resume-safe batch query. The exact-name branch returns remaining
    -- versions after the current (archived_at, version) boundary; the strict
    -- name branch returns subsequent keys. UNION ALL keeps both predicates
    -- independently indexable.
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2 AND lower(o.name) COLLATE "C" < $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 AND lower(o.name) COLLATE "C" >= $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    END IF;

    -- Keep the delete-marker predicate literal so the cached generic
    -- plan can use idx_objects_delete_markers during the main-loop peek.
    IF delete_markers = 'only' THEN
        IF v_multi_row THEN
            v_delete_marker_peek_query :=
                'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        ELSIF v_is_asc THEN
            -- Two separate literal query strings, not one gated by a bound
            -- boolean: folding "$n AND op1 OR NOT $n AND op2" into a single
            -- query defeats the generic plan's ability to push either
            -- comparison into the index. Branching in PL/pgSQL control flow
            -- instead keeps each query's index condition intact.
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" >= $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
            -- Strict variant: used once the single-row ASC batch advance
            -- (below) has left v_next_seek pointing at the last row already
            -- emitted, so a plain >= would re-match it forever.
            v_delete_marker_peek_query_strict :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" > $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
        ELSE
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" < $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" >= $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC performs one specialized initial seek so partial current-version
        -- and delete-marker indexes remain available.
        EXECUTE format(
            'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1',
            CASE WHEN v_upper_bound IS NOT NULL
                THEN ' AND lower(o.name) COLLATE "C" >= $2 AND lower(o.name) COLLATE "C" < $3'
                ELSE ''
            END,
            v_version_filter
        )
        INTO v_peek_name
        USING bucketname, v_prefix_lower, v_upper_bound;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch and
    -- the delete-marker-only path
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;
        v_previous_skipped := v_skipped;

        -- STEP 1: PEEK
        v_peek_name := NULL;
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END,
                    1, v_next_seek_at, v_next_seek_version;
        ELSIF v_multi_row AND v_next_seek_at IS NOT NULL THEN
            SELECT o.name INTO v_peek_name
            FROM storage.objects o
            WHERE o.bucket_id = bucketname
              AND lower(o.name) COLLATE "C" = v_next_seek
              AND (COALESCE(o.archived_at, 'infinity'::timestamptz) < v_next_seek_at
                   OR (COALESCE(o.archived_at, 'infinity'::timestamptz) = v_next_seek_at
                       AND COALESCE(o.version, '') > v_next_seek_version))
              AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
              AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
              AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
              AND (delete_markers != 'only' OR o.is_delete_marker)
            ORDER BY COALESCE(o.archived_at, 'infinity'::timestamptz) DESC,
                     COALESCE(o.version, '') ASC
            LIMIT 1;

            -- The current key is exhausted. Clear its version boundary and
            -- make the following ASC name peek strict. Appending '/' is not a
            -- valid lexical successor because keys ending in characters such
            -- as '!' sort between the exhausted name and name || '/'.
            IF v_peek_name IS NULL THEN
                IF v_is_asc THEN
                    v_next_seek_strict := true;
                END IF;
                v_next_seek_at := NULL;
                v_next_seek_version := '';
            END IF;
        END IF;

        -- Single-row mode is always noncurrent_versions='exclude'. Keep the
        -- current-row predicate literal so generic plans use the current index.
        IF delete_markers != 'only' AND v_peek_name IS NULL AND NOT v_multi_row THEN
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL AND v_is_asc THEN
            IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_next_seek_strict THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- If the peek landed on a different key than we were tracking, any
        -- version boundary belongs to the OLD key and must not leak into the
        -- new one - e.g. the deleteMarkers='only' peek doesn't know or care
        -- whether it's continuing the same key or jumping to a new one, so
        -- it never clears these itself.
        IF lower(v_peek_name) IS DISTINCT FROM v_next_seek THEN
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        END IF;

        -- The peek is authoritative for the next key to process. This is
        -- especially important after exhausting a multi-version key: the
        -- version boundary has been cleared, so executing the batch against
        -- a stale v_next_seek would replay every version of that old key.
        v_next_seek := lower(v_peek_name);
        v_next_seek_strict := false;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := substring(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter) from v_prefix_len + 1);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                version := NULL;
                archived_at := NULL;
                is_delete_marker := NULL;
                is_versioned := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size,
                    v_next_seek_at, v_next_seek_version
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too - it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN lower(v_current.name)
                        ELSE lower(v_current.name) || v_delimiter
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := substring(v_current.name from v_prefix_len + 1);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    version := v_current.version;
                    archived_at := v_current.archived_at;
                    is_delete_marker := v_current.is_delete_marker;
                    is_versioned := v_current.is_versioned;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Multi-row mode must remain on this key until all of its
                -- versions have crossed the internal batch boundary.
                IF v_multi_row THEN
                    v_next_seek := lower(v_current.name);
                    v_next_seek_at := COALESCE(v_current.archived_at, 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor would
                    -- skip a real key like `name || '!'` (or any character
                    -- sorting below the delimiter), which sorts between `name`
                    -- and `name || delimiter`. Track the real name and mark the
                    -- next comparison strict instead - same fix as the
                    -- exhausted-key case above.
                    v_next_seek := lower(v_current.name);
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_skipped = v_previous_skipped
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.search made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text", "noncurrent_versions" "text", "delete_markers" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text", "noncurrent_versions" "text" DEFAULT 'exclude'::"text", "delete_markers" "text" DEFAULT 'exclude'::"text", "p_start_after_version" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb", "version" "text", "archived_at" timestamp with time zone, "is_delete_marker" boolean, "is_versioned" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
    v_prefix_pattern text;
    v_sort_order text;
    v_sort_column text;
    v_version_tiebreak text;
BEGIN
    v_prefix := coalesce(p_prefix, '');
    -- Keep the raw prefix for common-prefix calculations and escape only LIKE metacharacters.
    v_prefix_pattern := replace(v_prefix, chr(92), chr(92) || chr(92));
    v_prefix_pattern := replace(v_prefix_pattern, '%', chr(92) || '%');
    v_prefix_pattern := replace(v_prefix_pattern, '_', chr(92) || '_');

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    -- $9 is only populated in multi-row mode; it's always '' otherwise, so
    -- only use each row's real version as a tiebreak in multi-row mode.
    v_version_tiebreak := CASE WHEN noncurrent_versions IN ('only', 'include') THEN 'COALESCE(version, '''')' ELSE '''''' END;

    -- Defense-in-depth: this function is independently reachable and must
    -- not trust p_sort_order/p_sort_column to already be validated by a
    -- caller. Normalize to the same strict allow-list storage.search_v2
    -- uses before interpolating anything into dynamic SQL below.
    v_sort_order := lower(coalesce(p_sort_order, 'asc'));
    IF v_sort_order NOT IN ('asc', 'desc') THEN
        v_sort_order := 'asc';
    END IF;

    v_sort_column := lower(coalesce(p_sort_column, 'updated_at'));
    IF v_sort_column NOT IN ('updated_at', 'created_at') THEN
        v_sort_column := 'updated_at';
    END IF;

    IF v_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                o.version AS obj_version,
                o.archived_at AS obj_archived_at,
                o.is_delete_marker AS obj_is_delete_marker,
                o.is_versioned AS obj_is_versioned,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $10 || '%%'
              AND ($7 != 'exclude' OR o.archived_at IS NULL)
              AND ($7 != 'only' OR o.archived_at IS NOT NULL)
              AND ($8 != 'exclude' OR NOT o.is_delete_marker)
              AND ($8 != 'only' OR o.is_delete_marker)
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                common_prefix AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                NULL::text AS version,
                NULL::timestamptz AS archived_at,
                NULL::boolean AS is_delete_marker,
                NULL::boolean AS is_versioned,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                obj_version AS version,
                obj_archived_at AS archived_at,
                obj_is_delete_marker AS is_delete_marker,
                obj_is_versioned AS is_versioned,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz),
                    name COLLATE "C",
                    %s
                ) %s ROW(
                    -- truncated the same way as the stored value above
                    date_trunc('milliseconds', COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz)),
                    $5,
                    $9
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata,
            version,
            archived_at,
            is_delete_marker,
            is_versioned
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s,
            COALESCE(version, '') %s
        LIMIT $4
    $sql$,
        v_sort_column,
        v_version_tiebreak,
        v_cursor_op,
        v_sort_column,
        v_sort_order,
        v_sort_order,
        v_sort_order
    );

    -- version is the third tiebreak component for two versions of the same
    -- key tying on both timestamp and name (see filtered CTE / ORDER BY above)
    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after, noncurrent_versions, delete_markers, coalesce(p_start_after_version, ''), v_prefix_pattern;
END;
$_$;


ALTER FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text", "noncurrent_versions" "text", "delete_markers" "text", "p_start_after_version" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text", "noncurrent_versions" "text" DEFAULT 'exclude'::"text", "delete_markers" "text" DEFAULT 'exclude'::"text", "start_after_archived_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "start_after_version" "text" DEFAULT ''::"text", "start_after_is_continuation" boolean DEFAULT false) RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb", "version" "text", "archived_at" timestamp with time zone, "is_delete_marker" boolean, "is_versioned" boolean)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata,
            l.version,
            l.archived_at,
            l.is_delete_marker,
            l.is_versioned
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            CASE WHEN start_after_is_continuation THEN '' ELSE start_after END,
            CASE WHEN start_after_is_continuation THEN start_after ELSE '' END,
            v_sort_ord,
            noncurrent_versions,
            delete_markers,
            start_after_archived_at,
            start_after_version
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after,
            noncurrent_versions, delete_markers, start_after_version
        );
    END IF;
END;
$$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text", "noncurrent_versions" "text", "delete_markers" "text", "start_after_archived_at" timestamp with time zone, "start_after_version" "text", "start_after_is_continuation" boolean) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."wake_lifecycle_state"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.lifecycle_configuration IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM storage.reconcile_lifecycle_state(NEW.id, false);
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."wake_lifecycle_state"() OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "public"."blocked_users" (
    "blocker_id" "uuid" NOT NULL,
    "blocked_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "blocked_users_check" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."blocked_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_lookup_attempts" (
    "user_id" "uuid" NOT NULL,
    "searched_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."contact_lookup_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_tokens" (
    "user_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "platform" "text" DEFAULT 'ios'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feed_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fit_check_id" "uuid" NOT NULL,
    "event" "text" NOT NULL,
    "value" double precision,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feed_events_event_check" CHECK (("event" = ANY (ARRAY['impression'::"text", 'open_detail'::"text", 'vote'::"text", 'save'::"text", 'share'::"text", 'follow'::"text", 'unfollow'::"text", 'not_interested'::"text"])))
);


ALTER TABLE "public"."feed_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fit_check_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fit_check_id" "uuid" NOT NULL,
    "photo_id" "uuid",
    "commenter_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "comments_body_length" CHECK ((("char_length"("btrim"("body")) >= 1) AND ("char_length"("btrim"("body")) <= 280)))
);


ALTER TABLE "public"."fit_check_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fit_check_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fit_check_id" "uuid" NOT NULL,
    "image_url" "text" NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT "fit_check_photos_position_check" CHECK ((("position" >= 1) AND ("position" <= 4)))
);


ALTER TABLE "public"."fit_check_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fit_check_votes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fit_check_id" "uuid" NOT NULL,
    "photo_id" "uuid" NOT NULL,
    "voter_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reason_tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "reason_comment" "text"
);


ALTER TABLE "public"."fit_check_votes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fit_checks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "creator_id" "uuid" NOT NULL,
    "caption" "text",
    "status" "text" DEFAULT 'live'::"text" NOT NULL,
    "is_public" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "group_id" "uuid",
    "expires_at" timestamp with time zone,
    "vote_count" integer DEFAULT 0 NOT NULL,
    "comment_count" integer DEFAULT 0 NOT NULL,
    "occasion" "text",
    CONSTRAINT "fit_checks_caption_length" CHECK (("char_length"("caption") <= 280)),
    CONSTRAINT "fit_checks_occasion_length" CHECK (("char_length"("occasion") <= 80)),
    CONSTRAINT "fit_checks_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'live'::"text", 'archived'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."fit_checks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_join_attempts" (
    "profile_id" "uuid" NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."group_join_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_members" (
    "group_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."group_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "fit_check_id" "uuid",
    "photo_id" "uuid",
    "comment_id" "uuid",
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['vote'::"text", 'comment'::"text", 'friend_request'::"text", 'friend_accepted'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profile_follows" (
    "follower_id" "uuid" NOT NULL,
    "following_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "profile_follows_check" CHECK (("follower_id" <> "following_id"))
);


ALTER TABLE "public"."profile_follows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wardrobe_tryon_jobs" (
    "job_id" "text" NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_polled_at" timestamp with time zone
);


ALTER TABLE "public"."wardrobe_tryon_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "storage"."bucket_lifecycle_states" (
    "bucket_id" "text" NOT NULL,
    "generation" "uuid",
    "next_run_at" timestamp with time zone,
    "claim_id" "uuid",
    "claim_until" timestamp with time zone,
    "continuation" "jsonb",
    "last_started_at" timestamp with time zone,
    "last_completed_at" timestamp with time zone,
    "last_success_at" timestamp with time zone,
    "last_result" "jsonb",
    "failure_count" integer DEFAULT 0 NOT NULL,
    "last_error" "jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "bucket_lifecycle_continuation_object_check" CHECK ((("continuation" IS NULL) OR ("jsonb_typeof"("continuation") = 'object'::"text"))),
    CONSTRAINT "bucket_lifecycle_failure_count_check" CHECK (("failure_count" >= 0)),
    CONSTRAINT "bucket_lifecycle_last_result_object_check" CHECK ((("last_result" IS NULL) OR ("jsonb_typeof"("last_result") = 'object'::"text"))),
    CONSTRAINT "bucket_lifecycle_recovery_due_check" CHECK ((("next_run_at" IS NOT NULL) OR (NOT "jsonb_path_exists"(COALESCE("continuation", '{}'::"jsonb"), '$."batch"."inFlight"'::"jsonpath"))))
);


ALTER TABLE "storage"."bucket_lifecycle_states" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL,
    "versioning_status" "text" DEFAULT 'DISABLED'::"text" NOT NULL,
    "lifecycle_configuration" "jsonb",
    "lifecycle_configuration_generation" "uuid",
    CONSTRAINT "buckets_lifecycle_configuration_pair_check" CHECK ((("lifecycle_configuration" IS NULL) = ("lifecycle_configuration_generation" IS NULL))),
    CONSTRAINT "buckets_lifecycle_configuration_shape_check" CHECK ((("lifecycle_configuration" IS NULL) OR (("jsonb_typeof"("lifecycle_configuration") = 'object'::"text") AND ("lifecycle_configuration" ? 'rules'::"text") AND
CASE
    WHEN ("jsonb_typeof"(("lifecycle_configuration" -> 'rules'::"text")) = 'array'::"text") THEN (("jsonb_array_length"(("lifecycle_configuration" -> 'rules'::"text")) >= 1) AND ("jsonb_array_length"(("lifecycle_configuration" -> 'rules'::"text")) <= 1000))
    ELSE false
END))),
    CONSTRAINT "buckets_lifecycle_configuration_standard_only_check" CHECK ((("type" = 'STANDARD'::"storage"."buckettype") OR (("lifecycle_configuration" IS NULL) AND ("lifecycle_configuration_generation" IS NULL)))),
    CONSTRAINT "buckets_versioning_standard_only_check" CHECK ((("type" = 'STANDARD'::"storage"."buckettype") OR ("versioning_status" = 'DISABLED'::"text"))),
    CONSTRAINT "buckets_versioning_status_check" CHECK (("versioning_status" = ANY (ARRAY['DISABLED'::"text", 'ENABLED'::"text", 'SUSPENDED'::"text"])))
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."lifecycle_abandoned_artifacts" (
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "version" "text",
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."lifecycle_abandoned_artifacts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb",
    "archived_at" timestamp with time zone,
    "is_delete_marker" boolean DEFAULT false NOT NULL,
    "is_versioned" boolean DEFAULT false NOT NULL
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_pkey" PRIMARY KEY ("blocker_id", "blocked_id");



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("token");



ALTER TABLE "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_platform_check" CHECK (("platform" = 'ios'::"text")) NOT VALID;



ALTER TABLE "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_token_length" CHECK ((("char_length"("token") >= 1) AND ("char_length"("token") <= 512))) NOT VALID;



ALTER TABLE ONLY "public"."feed_events"
    ADD CONSTRAINT "feed_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fit_check_comments"
    ADD CONSTRAINT "fit_check_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fit_check_photos"
    ADD CONSTRAINT "fit_check_photos_fit_check_id_position_key" UNIQUE ("fit_check_id", "position");



ALTER TABLE ONLY "public"."fit_check_photos"
    ADD CONSTRAINT "fit_check_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fit_check_votes"
    ADD CONSTRAINT "fit_check_votes_fit_check_id_voter_id_key" UNIQUE ("fit_check_id", "voter_id");



ALTER TABLE ONLY "public"."fit_check_votes"
    ADD CONSTRAINT "fit_check_votes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fit_checks"
    ADD CONSTRAINT "fit_checks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."friend_requests"
    ADD CONSTRAINT "friend_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_pkey" PRIMARY KEY ("user_low", "user_high");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_pkey" PRIMARY KEY ("group_id", "profile_id");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_invite_code_key" UNIQUE ("invite_code");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profile_follows"
    ADD CONSTRAINT "profile_follows_pkey" PRIMARY KEY ("follower_id", "following_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_nickname_key" UNIQUE ("nickname");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE "public"."wardrobe_items"
    ADD CONSTRAINT "wardrobe_items_image_url_owner_prefix" CHECK ((("image_url" ~~ (("owner_id")::"text" || '/%'::"text")) AND ("image_url" !~~ '%..%'::"text") AND ("image_url" !~~ '%://%'::"text"))) NOT VALID;



ALTER TABLE "public"."wardrobe_items"
    ADD CONSTRAINT "wardrobe_items_image_url_strict_path" CHECK (("image_url" ~ (('^'::"text" || ("owner_id")::"text") || '/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)?[A-Za-z0-9_-][A-Za-z0-9._-]*\.(jpg|jpeg|png|webp)$'::"text"))) NOT VALID;



ALTER TABLE ONLY "public"."wardrobe_items"
    ADD CONSTRAINT "wardrobe_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wardrobe_tryon_jobs"
    ADD CONSTRAINT "wardrobe_tryon_jobs_pkey" PRIMARY KEY ("job_id");



ALTER TABLE ONLY "storage"."bucket_lifecycle_states"
    ADD CONSTRAINT "bucket_lifecycle_states_pkey" PRIMARY KEY ("bucket_id");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."lifecycle_abandoned_artifacts"
    ADD CONSTRAINT "lifecycle_abandoned_artifacts_pkey" PRIMARY KEY ("bucket_id", "key");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE INDEX "comments_fit_check_created_idx" ON "public"."fit_check_comments" USING "btree" ("fit_check_id", "created_at" DESC);



CREATE INDEX "contact_lookup_attempts_user_time_idx" ON "public"."contact_lookup_attempts" USING "btree" ("user_id", "searched_at");



CREATE UNIQUE INDEX "content_reports_one_comment_idx" ON "public"."content_reports" USING "btree" ("reporter_id", "comment_id", "reason") WHERE ("comment_id" IS NOT NULL);



CREATE UNIQUE INDEX "content_reports_one_target_idx" ON "public"."content_reports" USING "btree" ("reporter_id", "fit_check_id", "reason") WHERE ("fit_check_id" IS NOT NULL);



CREATE UNIQUE INDEX "content_reports_one_user_idx" ON "public"."content_reports" USING "btree" ("reporter_id", "reported_user_id", "reason") WHERE ("reported_user_id" IS NOT NULL);



CREATE INDEX "content_reports_status_idx" ON "public"."content_reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "feed_events_fit_check_idx" ON "public"."feed_events" USING "btree" ("fit_check_id", "created_at" DESC);



CREATE INDEX "feed_events_user_created_idx" ON "public"."feed_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "fit_checks_expiry_idx" ON "public"."fit_checks" USING "btree" ("expires_at") WHERE ("status" = 'live'::"text");



CREATE INDEX "fit_checks_group_newest_idx" ON "public"."fit_checks" USING "btree" ("group_id", "created_at" DESC, "id" DESC) WHERE ("status" = 'live'::"text");



CREATE INDEX "fit_checks_public_newest_idx" ON "public"."fit_checks" USING "btree" ("created_at" DESC, "id" DESC) WHERE (("status" = 'live'::"text") AND "is_public");



CREATE INDEX "fit_checks_public_votes_idx" ON "public"."fit_checks" USING "btree" ("vote_count" DESC, "created_at" DESC, "id" DESC) WHERE (("status" = 'live'::"text") AND "is_public");



CREATE INDEX "friend_requests_addressee_idx" ON "public"."friend_requests" USING "btree" ("addressee_id", "status", "created_at" DESC);



CREATE UNIQUE INDEX "friend_requests_one_pending_idx" ON "public"."friend_requests" USING "btree" ("requester_id", "addressee_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "friend_requests_requester_idx" ON "public"."friend_requests" USING "btree" ("requester_id", "status", "created_at" DESC);



CREATE INDEX "friendships_high_idx" ON "public"."friendships" USING "btree" ("user_high", "created_at" DESC);



CREATE INDEX "group_join_attempts_profile_time_idx" ON "public"."group_join_attempts" USING "btree" ("profile_id", "attempted_at");



CREATE INDEX "group_members_profile_idx" ON "public"."group_members" USING "btree" ("profile_id", "group_id");



CREATE INDEX "notifications_recipient_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC);



CREATE INDEX "profile_follows_following_idx" ON "public"."profile_follows" USING "btree" ("following_id", "created_at" DESC);



CREATE UNIQUE INDEX "profiles_account_code_idx" ON "public"."profiles" USING "btree" ("account_code");



CREATE INDEX "votes_fit_check_photo_idx" ON "public"."fit_check_votes" USING "btree" ("fit_check_id", "photo_id");



CREATE INDEX "wardrobe_items_owner_idx" ON "public"."wardrobe_items" USING "btree" ("owner_id", "created_at" DESC);



CREATE INDEX "wardrobe_tryon_jobs_owner_created_idx" ON "public"."wardrobe_tryon_jobs" USING "btree" ("owner_id", "created_at" DESC);



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE INDEX "bucket_lifecycle_states_due_idx" ON "storage"."bucket_lifecycle_states" USING "btree" ("next_run_at", "bucket_id") WHERE ("next_run_at" IS NOT NULL);



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_bucket_id_name_lower" ON "storage"."objects" USING "btree" ("bucket_id", "lower"("name") COLLATE "C");



CREATE UNIQUE INDEX "idx_objects_current_version" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C") WHERE ("archived_at" IS NULL);



CREATE INDEX "idx_objects_delete_markers" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C") WHERE "is_delete_marker";



CREATE UNIQUE INDEX "idx_objects_null_version" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C") WHERE (NOT "is_versioned");



CREATE INDEX "lifecycle_abandoned_artifacts_attempted_at_idx" ON "storage"."lifecycle_abandoned_artifacts" USING "btree" ("attempted_at");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE INDEX "objects_archived_due_idx" ON "storage"."objects" USING "btree" ("bucket_id", "archived_at", "name" COLLATE "C") INCLUDE ("id", "version", "is_delete_marker") WHERE ("archived_at" IS NOT NULL);



CREATE UNIQUE INDEX "objects_archived_order_uq" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C", "archived_at") WHERE ("archived_at" IS NOT NULL);



CREATE UNIQUE INDEX "objects_bucket_id_name_version_key" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C", "version") NULLS NOT DISTINCT;



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE TRIGGER "device_tokens_cap" BEFORE INSERT ON "public"."device_tokens" FOR EACH ROW EXECUTE FUNCTION "public"."device_tokens_enforce_cap"();



CREATE OR REPLACE TRIGGER "trg_bump_comment_count_delete" AFTER DELETE ON "public"."fit_check_comments" FOR EACH ROW EXECUTE FUNCTION "public"."bump_comment_count"();



CREATE OR REPLACE TRIGGER "trg_bump_comment_count_insert" AFTER INSERT ON "public"."fit_check_comments" FOR EACH ROW EXECUTE FUNCTION "public"."bump_comment_count"();



CREATE OR REPLACE TRIGGER "trg_bump_vote_count_delete" AFTER DELETE ON "public"."fit_check_votes" FOR EACH ROW EXECUTE FUNCTION "public"."bump_vote_count"();



CREATE OR REPLACE TRIGGER "trg_bump_vote_count_insert" AFTER INSERT ON "public"."fit_check_votes" FOR EACH ROW EXECUTE FUNCTION "public"."bump_vote_count"();



CREATE OR REPLACE TRIGGER "trg_notify_on_comment" AFTER INSERT ON "public"."fit_check_comments" FOR EACH ROW EXECUTE FUNCTION "public"."notify_on_comment"();



CREATE OR REPLACE TRIGGER "trg_notify_on_vote" AFTER INSERT ON "public"."fit_check_votes" FOR EACH ROW EXECUTE FUNCTION "public"."notify_on_vote"();



CREATE OR REPLACE TRIGGER "validate_comment_before_insert" BEFORE INSERT ON "public"."fit_check_comments" FOR EACH ROW EXECUTE FUNCTION "public"."validate_fit_check_activity"();



CREATE OR REPLACE TRIGGER "validate_draft_photo_write" BEFORE INSERT OR DELETE ON "public"."fit_check_photos" FOR EACH ROW EXECUTE FUNCTION "public"."validate_draft_photo"();



CREATE OR REPLACE TRIGGER "validate_vote_before_insert" BEFORE INSERT ON "public"."fit_check_votes" FOR EACH ROW EXECUTE FUNCTION "public"."validate_fit_check_activity"();



CREATE OR REPLACE TRIGGER "wardrobe_items_touch" BEFORE UPDATE ON "public"."wardrobe_items" FOR EACH ROW EXECUTE FUNCTION "public"."touch_wardrobe_item"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "enforce_versioning_status_transition" BEFORE UPDATE OF "versioning_status" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_versioning_status_transition"();



CREATE OR REPLACE TRIGGER "protect_active_lifecycle_states" BEFORE DELETE ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."protect_active_lifecycle_states"();



CREATE OR REPLACE TRIGGER "protect_bucket_control_insert" BEFORE INSERT ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."protect_bucket_control_columns"('service_role');



CREATE OR REPLACE TRIGGER "protect_bucket_control_update" BEFORE UPDATE OF "lifecycle_configuration", "lifecycle_configuration_generation" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."protect_bucket_control_columns"();



CREATE OR REPLACE TRIGGER "protect_bucket_control_update_role" AFTER UPDATE OF "lifecycle_configuration", "lifecycle_configuration_generation" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_lifecycle_service_role"('service_role');



CREATE OR REPLACE TRIGGER "protect_buckets_delete" BEFORE DELETE ON "storage"."buckets" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "protect_objects_delete" BEFORE DELETE ON "storage"."objects" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "wake_lifecycle_on_policy_write" AFTER INSERT OR UPDATE OF "lifecycle_configuration_generation" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."wake_lifecycle_state"();



CREATE OR REPLACE TRIGGER "wake_lifecycle_on_versioning_enable" AFTER UPDATE OF "versioning_status" ON "storage"."buckets" FOR EACH ROW WHEN (("new"."lifecycle_configuration" IS NOT NULL)) EXECUTE FUNCTION "storage"."wake_lifecycle_state"();



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_lookup_attempts"
    ADD CONSTRAINT "contact_lookup_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."fit_check_comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_reported_user_id_fkey" FOREIGN KEY ("reported_user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feed_events"
    ADD CONSTRAINT "feed_events_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feed_events"
    ADD CONSTRAINT "feed_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_comments"
    ADD CONSTRAINT "fit_check_comments_commenter_id_fkey" FOREIGN KEY ("commenter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_comments"
    ADD CONSTRAINT "fit_check_comments_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_comments"
    ADD CONSTRAINT "fit_check_comments_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."fit_check_photos"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."fit_check_photos"
    ADD CONSTRAINT "fit_check_photos_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_votes"
    ADD CONSTRAINT "fit_check_votes_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_votes"
    ADD CONSTRAINT "fit_check_votes_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."fit_check_photos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_check_votes"
    ADD CONSTRAINT "fit_check_votes_voter_id_fkey" FOREIGN KEY ("voter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_checks"
    ADD CONSTRAINT "fit_checks_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fit_checks"
    ADD CONSTRAINT "fit_checks_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."friend_requests"
    ADD CONSTRAINT "friend_requests_addressee_id_fkey" FOREIGN KEY ("addressee_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friend_requests"
    ADD CONSTRAINT "friend_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_user_high_fkey" FOREIGN KEY ("user_high") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_user_low_fkey" FOREIGN KEY ("user_low") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_join_attempts"
    ADD CONSTRAINT "group_join_attempts_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."fit_check_comments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_fit_check_id_fkey" FOREIGN KEY ("fit_check_id") REFERENCES "public"."fit_checks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_photo_id_fkey" FOREIGN KEY ("photo_id") REFERENCES "public"."fit_check_photos"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_follows"
    ADD CONSTRAINT "profile_follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_follows"
    ADD CONSTRAINT "profile_follows_following_id_fkey" FOREIGN KEY ("following_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE NOT VALID;



ALTER TABLE ONLY "public"."wardrobe_items"
    ADD CONSTRAINT "wardrobe_items_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wardrobe_tryon_jobs"
    ADD CONSTRAINT "wardrobe_tryon_jobs_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."bucket_lifecycle_states"
    ADD CONSTRAINT "bucket_lifecycle_states_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "public"."blocked_users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bu_delete" ON "public"."blocked_users" FOR DELETE TO "authenticated" USING (("blocker_id" = "auth"."uid"()));



CREATE POLICY "bu_insert" ON "public"."blocked_users" FOR INSERT TO "authenticated" WITH CHECK ((("blocker_id" = "auth"."uid"()) AND ("blocker_id" <> "blocked_id")));



CREATE POLICY "bu_read" ON "public"."blocked_users" FOR SELECT TO "authenticated" USING (("blocker_id" = "auth"."uid"()));



ALTER TABLE "public"."contact_lookup_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_reports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device tokens: owner manages" ON "public"."device_tokens" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."device_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."feed_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feed_events: insert own" ON "public"."feed_events" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "feed_events: read own" ON "public"."feed_events" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."fit_check_comments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fit_check_comments: delete own" ON "public"."fit_check_comments" FOR DELETE TO "authenticated" USING (("commenter_id" = "auth"."uid"()));



CREATE POLICY "fit_check_comments: insert (self, live post)" ON "public"."fit_check_comments" FOR INSERT TO "authenticated" WITH CHECK ((("commenter_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id" = "fit_check_comments"."fit_check_id") AND ("f"."status" = 'live'::"text") AND (("f"."expires_at" IS NULL) OR ("f"."expires_at" > "now"())))))));



CREATE POLICY "fit_check_comments: read (parent visible)" ON "public"."fit_check_comments" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE ("f"."id" = "fit_check_comments"."fit_check_id"))) AND (NOT "public"."is_blocked_pair"("commenter_id"))));



ALTER TABLE "public"."fit_check_photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fit_check_photos: delete on own draft" ON "public"."fit_check_photos" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id" = "fit_check_photos"."fit_check_id") AND ("f"."creator_id" = "auth"."uid"()) AND ("f"."status" = 'draft'::"text")))));



CREATE POLICY "fit_check_photos: insert on own draft" ON "public"."fit_check_photos" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id" = "fit_check_photos"."fit_check_id") AND ("f"."creator_id" = "auth"."uid"()) AND ("f"."status" = 'draft'::"text")))));



CREATE POLICY "fit_check_photos: read (parent visible)" ON "public"."fit_check_photos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE ("f"."id" = "fit_check_photos"."fit_check_id"))));



ALTER TABLE "public"."fit_check_votes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fit_check_votes: delete own" ON "public"."fit_check_votes" FOR DELETE TO "authenticated" USING (("voter_id" = "auth"."uid"()));



CREATE POLICY "fit_check_votes: insert (self, live post, not own)" ON "public"."fit_check_votes" FOR INSERT TO "authenticated" WITH CHECK ((("voter_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id" = "fit_check_votes"."fit_check_id") AND ("f"."creator_id" <> "auth"."uid"()) AND ("f"."status" = 'live'::"text") AND (("f"."expires_at" IS NULL) OR ("f"."expires_at" > "now"())))))));



CREATE POLICY "fit_check_votes: read (parent visible)" ON "public"."fit_check_votes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id" = "fit_check_votes"."fit_check_id") AND (("f"."creator_id" = "auth"."uid"()) OR (("f"."status" = 'live'::"text") AND (("f"."expires_at" IS NULL) OR ("f"."expires_at" > "now"()))))))));



ALTER TABLE "public"."fit_checks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fit_checks: delete own" ON "public"."fit_checks" FOR DELETE TO "authenticated" USING (("creator_id" = "auth"."uid"()));



CREATE POLICY "fit_checks: insert own" ON "public"."fit_checks" FOR INSERT TO "authenticated" WITH CHECK (("creator_id" = "auth"."uid"()));



CREATE POLICY "fit_checks: read (published audience or owner)" ON "public"."fit_checks" FOR SELECT TO "authenticated" USING ((("creator_id" = "auth"."uid"()) OR (("status" <> 'draft'::"text") AND (NOT "public"."is_blocked_pair"("creator_id")) AND ("is_public" OR (("group_id" IS NOT NULL) AND "public"."is_group_member"("group_id"))))));



CREATE POLICY "fit_checks: update own" ON "public"."fit_checks" FOR UPDATE TO "authenticated" USING (("creator_id" = "auth"."uid"())) WITH CHECK (("creator_id" = "auth"."uid"()));



CREATE POLICY "fr_insert" ON "public"."friend_requests" FOR INSERT TO "authenticated" WITH CHECK ((("requester_id" = "auth"."uid"()) AND ("requester_id" <> "addressee_id")));



CREATE POLICY "fr_read" ON "public"."friend_requests" FOR SELECT TO "authenticated" USING ((("requester_id" = "auth"."uid"()) OR ("addressee_id" = "auth"."uid"())));



ALTER TABLE "public"."friend_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."friendships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fs_read" ON "public"."friendships" FOR SELECT TO "authenticated" USING ((("user_low" = "auth"."uid"()) OR ("user_high" = "auth"."uid"())));



ALTER TABLE "public"."group_join_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "group_members: creator joins own group" ON "public"."group_members" FOR INSERT TO "authenticated" WITH CHECK ((("profile_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."groups" "g"
  WHERE (("g"."id" = "group_members"."group_id") AND ("g"."creator_id" = "auth"."uid"()))))));



CREATE POLICY "group_members: leave self or owner removes" ON "public"."group_members" FOR DELETE TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."groups" "g"
  WHERE (("g"."id" = "group_members"."group_id") AND ("g"."creator_id" = "auth"."uid"()))))));



CREATE POLICY "group_members: read (self / same group)" ON "public"."group_members" FOR SELECT TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR "public"."is_group_member"("group_id")));



ALTER TABLE "public"."groups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "groups: delete own" ON "public"."groups" FOR DELETE TO "authenticated" USING (("creator_id" = "auth"."uid"()));



CREATE POLICY "groups: insert own" ON "public"."groups" FOR INSERT TO "authenticated" WITH CHECK (("creator_id" = "auth"."uid"()));



CREATE POLICY "groups: read (own / member)" ON "public"."groups" FOR SELECT TO "authenticated" USING ((("creator_id" = "auth"."uid"()) OR "public"."is_group_member"("id")));



CREATE POLICY "groups: update own" ON "public"."groups" FOR UPDATE TO "authenticated" USING (("creator_id" = "auth"."uid"())) WITH CHECK (("creator_id" = "auth"."uid"()));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications: read own" ON "public"."notifications" FOR SELECT TO "authenticated" USING (("recipient_id" = "auth"."uid"()));



CREATE POLICY "notifications: update own" ON "public"."notifications" FOR UPDATE TO "authenticated" USING (("recipient_id" = "auth"."uid"())) WITH CHECK (("recipient_id" = "auth"."uid"()));



ALTER TABLE "public"."profile_follows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profile_follows: delete self" ON "public"."profile_follows" FOR DELETE TO "authenticated" USING (("follower_id" = "auth"."uid"()));



CREATE POLICY "profile_follows: insert self" ON "public"."profile_follows" FOR INSERT TO "authenticated" WITH CHECK ((("follower_id" = "auth"."uid"()) AND (NOT "public"."is_blocked_pair"("following_id"))));



CREATE POLICY "profile_follows: read signed in" ON "public"."profile_follows" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles: read (signed in)" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "profiles: update self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "reports: reporter creates" ON "public"."content_reports" FOR INSERT TO "authenticated" WITH CHECK (("reporter_id" = "auth"."uid"()));



CREATE POLICY "reports: reporter reads own" ON "public"."content_reports" FOR SELECT TO "authenticated" USING (("reporter_id" = "auth"."uid"()));



ALTER TABLE "public"."wardrobe_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wardrobe_items: owner delete" ON "public"."wardrobe_items" FOR DELETE TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "wardrobe_items: owner insert" ON "public"."wardrobe_items" FOR INSERT TO "authenticated" WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "wardrobe_items: owner read" ON "public"."wardrobe_items" FOR SELECT TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "wardrobe_items: owner update" ON "public"."wardrobe_items" FOR UPDATE TO "authenticated" USING (("owner_id" = "auth"."uid"())) WITH CHECK (("owner_id" = "auth"."uid"()));



ALTER TABLE "public"."wardrobe_tryon_jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "avatars: insert own folder" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "avatars: owner delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "avatars: owner read" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



ALTER TABLE "storage"."bucket_lifecycle_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fit-check-photos: insert own draft" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'fit-check-photos'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text") AND (EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE ((("f"."id")::"text" = ("storage"."foldername"("objects"."name"))[2]) AND ("f"."creator_id" = "auth"."uid"()) AND ("f"."status" = 'draft'::"text"))))));



CREATE POLICY "fit-check-photos: owner delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'fit-check-photos'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "fit-check-photos: read visible parent or own orphan" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'fit-check-photos'::"text") AND ((EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE ((("f"."id")::"text" = ("storage"."foldername"("objects"."name"))[2]) AND (("f"."creator_id")::"text" = ("storage"."foldername"("objects"."name"))[1])))) OR ((("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text") AND (NOT (EXISTS ( SELECT 1
   FROM "public"."fit_checks" "f"
  WHERE (("f"."id")::"text" = ("storage"."foldername"("objects"."name"))[2]))))))));



ALTER TABLE "storage"."lifecycle_abandoned_artifacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wardrobe-items: owner delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'wardrobe-items'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "wardrobe-items: owner insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'wardrobe-items'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "wardrobe-items: owner read" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'wardrobe-items'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "wardrobe-items: owner update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'wardrobe-items'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text"))) WITH CHECK ((("bucket_id" = 'wardrobe-items'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



REVOKE ALL ON FUNCTION "public"."block_user"("p_blocked_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."block_user"("p_blocked_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."block_user"("p_blocked_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_vote_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_vote_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_vote_count"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_friend_request"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_friend_request"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_friend_request"("p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid", "p_occasion" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid", "p_occasion" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_fit_check_draft"("p_id" "uuid", "p_caption" "text", "p_group_id" "uuid", "p_occasion" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."groups" TO "anon";
GRANT ALL ON TABLE "public"."groups" TO "authenticated";
GRANT ALL ON TABLE "public"."groups" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_group_with_owner"("p_name" "text", "p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_group_with_owner"("p_name" "text", "p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_group_with_owner"("p_name" "text", "p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_my_account"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."device_tokens_enforce_cap"() TO "anon";
GRANT ALL ON FUNCTION "public"."device_tokens_enforce_cap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."device_tokens_enforce_cap"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid", "p_sort" "text", "p_offset" integer, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid", "p_sort" "text", "p_offset" integer, "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid", "p_sort" "text", "p_offset" integer, "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."find_profiles_by_contact"("p_contact" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."find_profiles_by_contact"("p_contact" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."find_profiles_by_contact"("p_contact" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_mutual_friend_counts"("p_user_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_mutual_friend_counts"("p_user_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_mutual_friend_counts"("p_user_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_blocked_pair"("p_other" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_blocked_pair"("p_other" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_blocked_pair"("p_other" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_group_member"("gid" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_group_member"("gid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_group_member"("gid" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."join_group_by_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."join_group_by_code"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_group_by_code"("p_code" "text") TO "service_role";



GRANT ALL ON TABLE "public"."wardrobe_items" TO "authenticated";
GRANT ALL ON TABLE "public"."wardrobe_items" TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_wardrobe_wear"("p_item_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_wardrobe_wear"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_wardrobe_wear"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_on_vote"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_on_vote"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_on_vote"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."popular_fit_checks"("p_limit" integer, "p_offset" integer, "p_window_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."popular_fit_checks"("p_limit" integer, "p_offset" integer, "p_window_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."popular_fit_checks"("p_limit" integer, "p_offset" integer, "p_window_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_fit_check"("p_id" "uuid", "p_duration_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_fit_check"("p_id" "uuid", "p_duration_seconds" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."publish_fit_check"("p_id" "uuid", "p_duration_seconds" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reserve_tryon_slot"("p_owner" "uuid", "p_max" integer, "p_window_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reserve_tryon_slot"("p_owner" "uuid", "p_max" integer, "p_window_seconds" integer) TO "service_role";



GRANT ALL ON TABLE "public"."friendships" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."friendships" TO "authenticated";
GRANT ALL ON TABLE "public"."friendships" TO "service_role";



REVOKE ALL ON FUNCTION "public"."respond_friend_request"("p_request_id" "uuid", "p_accept" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."respond_friend_request"("p_request_id" "uuid", "p_accept" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."respond_friend_request"("p_request_id" "uuid", "p_accept" boolean) TO "service_role";



GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_onboarding"("p_nickname" "text", "p_style_preferences" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_onboarding"("p_nickname" "text", "p_style_preferences" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_onboarding"("p_nickname" "text", "p_style_preferences" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_vote_reason"("p_fit_check_id" "uuid", "p_photo_id" "uuid", "p_reason_tags" "text"[], "p_reason_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_vote_reason"("p_fit_check_id" "uuid", "p_photo_id" "uuid", "p_reason_tags" "text"[], "p_reason_comment" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_vote_reason"("p_fit_check_id" "uuid", "p_photo_id" "uuid", "p_reason_tags" "text"[], "p_reason_comment" "text") TO "service_role";



GRANT ALL ON TABLE "public"."friend_requests" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."friend_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."friend_requests" TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_friend_request"("p_addressee_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_friend_request"("p_addressee_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_friend_request"("p_addressee_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."content_reports" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."content_reports" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."submit_content_report"("p_fit_check_id" "uuid", "p_comment_id" "uuid", "p_reported_user_id" "uuid", "p_reason" "text", "p_details" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_content_report"("p_fit_check_id" "uuid", "p_comment_id" "uuid", "p_reported_user_id" "uuid", "p_reason" "text", "p_details" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_content_report"("p_fit_check_id" "uuid", "p_comment_id" "uuid", "p_reported_user_id" "uuid", "p_reason" "text", "p_details" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."terminate_fit_check"("p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."terminate_fit_check"("p_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."terminate_fit_check"("p_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."touch_tryon_poll"("p_job_id" "text", "p_owner" "uuid", "p_min_interval_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."touch_tryon_poll"("p_job_id" "text", "p_owner" "uuid", "p_min_interval_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_wardrobe_item"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_wardrobe_item"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_wardrobe_item"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_draft_photo"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_draft_photo"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_fit_check_activity"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_fit_check_activity"() TO "service_role";



REVOKE ALL ON FUNCTION "storage"."delete_lifecycle_objects"("object_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "storage"."delete_lifecycle_objects"("object_ids" "uuid"[]) TO "postgres";
GRANT ALL ON FUNCTION "storage"."delete_lifecycle_objects"("object_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "storage"."protect_active_lifecycle_states"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "storage"."reconcile_lifecycle_state"("target_bucket_id" "text", "policy_changed" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "storage"."reconcile_lifecycle_state"("target_bucket_id" "text", "policy_changed" boolean) TO "postgres";
GRANT ALL ON FUNCTION "storage"."reconcile_lifecycle_state"("target_bucket_id" "text", "policy_changed" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "storage"."wake_lifecycle_state"() FROM PUBLIC;



GRANT ALL ON TABLE "public"."blocked_users" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."blocked_users" TO "authenticated";
GRANT ALL ON TABLE "public"."blocked_users" TO "service_role";



GRANT ALL ON TABLE "public"."contact_lookup_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."device_tokens" TO "anon";
GRANT ALL ON TABLE "public"."device_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."device_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."feed_events" TO "authenticated";
GRANT ALL ON TABLE "public"."feed_events" TO "service_role";



GRANT ALL ON TABLE "public"."fit_check_comments" TO "anon";
GRANT ALL ON TABLE "public"."fit_check_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."fit_check_comments" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fit_check_photos" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fit_check_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."fit_check_photos" TO "service_role";



GRANT ALL ON TABLE "public"."fit_check_votes" TO "anon";
GRANT ALL ON TABLE "public"."fit_check_votes" TO "authenticated";
GRANT ALL ON TABLE "public"."fit_check_votes" TO "service_role";



GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fit_checks" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fit_checks" TO "authenticated";
GRANT ALL ON TABLE "public"."fit_checks" TO "service_role";



GRANT ALL ON TABLE "public"."group_join_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."group_members" TO "anon";
GRANT ALL ON TABLE "public"."group_members" TO "authenticated";
GRANT ALL ON TABLE "public"."group_members" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notifications" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT UPDATE("is_read") ON TABLE "public"."notifications" TO "authenticated";



GRANT ALL ON TABLE "public"."profile_follows" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_follows" TO "service_role";



GRANT ALL ON TABLE "public"."wardrobe_tryon_jobs" TO "service_role";



GRANT ALL ON TABLE "storage"."bucket_lifecycle_states" TO "postgres";
GRANT ALL ON TABLE "storage"."bucket_lifecycle_states" TO "service_role";



REVOKE ALL ON TABLE "storage"."buckets" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."buckets" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."buckets" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";



GRANT ALL ON TABLE "storage"."lifecycle_abandoned_artifacts" TO "postgres";
GRANT ALL ON TABLE "storage"."lifecycle_abandoned_artifacts" TO "service_role";



REVOKE ALL ON TABLE "storage"."objects" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."objects" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."objects" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";




